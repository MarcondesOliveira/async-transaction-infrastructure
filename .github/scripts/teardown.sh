#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${STACK:?Select stack}"
: "${OPERATION:?Select plan/destroy}"
: "${STACK_CONFIG_JSON:?Provide configuration}"
: "${AWS_ACCOUNT_ID:?Configure expected account}"
: "${AWS_REGION:?Configure region}"
: "${TF_STATE_BUCKET:?Configure backend}"
: "${RUNNER_TEMP:?Provide temporary workspace}"
[[ "$STACK" == core || "$STACK" == external-simulator ]]
workspace="$(mktemp -d "$RUNNER_TEMP/final-teardown.XXXXXX")"
printf '%s' "$STACK_CONFIG_JSON" > "$workspace/base.json"
python3 .github/scripts/infrastructure.py config "$STACK" "$workspace/base.json" \
  ".github/config/$STACK.json" "$workspace/config.json"
python3 .github/scripts/teardown.py intent "$OPERATION" "$STACK" "$workspace/config.json" \
  "${CONFIRMATION:-}" "${TEARDOWN_ENABLED:-false}"
test "$(aws sts get-caller-identity --query Account --output text)" = "$AWS_ACCOUNT_ID"
project="$(jq -r '.project_name' "$workspace/config.json")"
environment="$(jq -r '.environment' "$workspace/config.json")"
test "$(jq -r '.aws_region' "$workspace/config.json")" = "$AWS_REGION"
directory="stacks/$STACK"
terraform -chdir="$directory" init -input=false -no-color \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=$project/$environment/$STACK.tfstate" \
  -backend-config="region=$AWS_REGION" -backend-config=encrypt=true \
  -backend-config=use_lockfile=true > "$workspace/init.log" 2>&1 || {
    tail -n 60 "$workspace/init.log"; exit 1;
  }
# Destroy does not need ZIP values. Defaults are deliberately not applied as code.
terraform -chdir="$directory" plan -destroy -input=false -no-color -lock-timeout=10m \
  -var-file="$workspace/config.json" -out="$workspace/destroy.tfplan" \
  > "$workspace/plan.log" 2>&1 || { tail -n 80 "$workspace/plan.log"; exit 1; }
terraform -chdir="$directory" show -json "$workspace/destroy.tfplan" > "$workspace/plan.json"
python3 .github/scripts/teardown.py plan "$workspace/plan.json" "$workspace/config.json" | tee "$workspace/summary.json"
cat "$workspace/summary.json" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
if [[ "$OPERATION" == plan ]]; then
  echo 'Teardown plan only; nothing deleted.'
  exit 0
fi
terraform -chdir="$directory" apply -input=false -no-color -lock-timeout=10m \
  "$workspace/destroy.tfplan" > "$workspace/apply.log" 2>&1 || {
    tail -n 80 "$workspace/apply.log"; exit 1;
  }
terraform -chdir="$directory" show -json > "$workspace/remaining.json"
python3 .github/scripts/teardown.py empty "$workspace/remaining.json"
