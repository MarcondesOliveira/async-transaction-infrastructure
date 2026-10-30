#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${STACK:?Select stack}"
: "${STACK_CONFIG_JSON:?Provide base config}"
: "${TF_STATE_BUCKET:?Configure backend}"
: "${AWS_ACCOUNT_ID:?Configure AWS account}"
: "${AWS_REGION:?Configure region}"
: "${RUNNER_TEMP:?Provide temporary workspace}"
[[ "$STACK" == core || "$STACK" == external-simulator ]]
operation="${OPERATION:-plan}"
[[ "$operation" == plan || "$operation" == deploy ]]
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]
test "$(aws sts get-caller-identity --query Account --output text)" = "$AWS_ACCOUNT_ID"
workspace="$(mktemp -d "$RUNNER_TEMP/infrastructure-delivery.XXXXXX")"
printf '%s' "$STACK_CONFIG_JSON" > "$workspace/base.json"
python3 .github/scripts/infrastructure.py config "$STACK" "$workspace/base.json" \
  ".github/config/$STACK.json" "$workspace/config.json"
project="$(jq -er '.project_name | select(test("^[a-z0-9-]+$"))' "$workspace/config.json")"
environment="$(jq -er '.environment | select(test("^[a-z0-9-]+$"))' "$workspace/config.json")"
test "$(jq -r '.aws_region' "$workspace/config.json")" = "$AWS_REGION"
directory="stacks/$STACK"
terraform -chdir="$directory" init -input=false -no-color \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=$project/$environment/$STACK.tfstate" \
  -backend-config="region=$AWS_REGION" -backend-config=encrypt=true \
  -backend-config=use_lockfile=true > "$workspace/init.log" 2>&1 || {
    tail -n 60 "$workspace/init.log"; exit 1;
  }
terraform -chdir="$directory" validate -no-color
terraform -chdir="$directory" show -json > "$workspace/state.json"
python3 .github/scripts/infrastructure.py inputs "$STACK" "$workspace/state.json" \
  "$workspace/config.json" "$workspace/deployment.tfvars.json" "$workspace/contexts.json"
terraform -chdir="$directory" plan -input=false -no-color -lock-timeout=10m \
  -var-file="$workspace/deployment.tfvars.json" -out="$workspace/deployment.tfplan" \
  > "$workspace/plan.log" 2>&1 || { tail -n 80 "$workspace/plan.log"; exit 1; }
terraform -chdir="$directory" show -json "$workspace/deployment.tfplan" > "$workspace/plan.json"
python3 .github/scripts/infrastructure.py plan "$workspace/plan.json" | tee "$workspace/summary.json"
cat "$workspace/summary.json" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
if [[ "$operation" == plan ]]; then
  echo 'Infrastructure plan validated; nothing applied.'
  exit 0
fi
terraform -chdir="$directory" apply -input=false -no-color -lock-timeout=10m \
  "$workspace/deployment.tfplan" > "$workspace/apply.log" 2>&1 || {
    tail -n 80 "$workspace/apply.log"; exit 1;
  }
index=0
while IFS= read -r function_name; do
  aws lambda wait function-updated-v2 --function-name "$function_name"
  aws lambda get-function-configuration --function-name "$function_name" \
    --query '{FunctionName:FunctionName,State:State,LastUpdateStatus:LastUpdateStatus,CodeSha256:CodeSha256,Runtime:Runtime,Architectures:Architectures}' \
    --output json > "$workspace/function-$index.json"
  index=$((index + 1))
done < <(jq -r '.[].functions[]' "$workspace/contexts.json")
jq -s '.' "$workspace"/function-*.json > "$workspace/functions.json"
python3 .github/scripts/infrastructure.py verify "$workspace/contexts.json" "$workspace/functions.json"
python3 .github/scripts/smoke.py
echo 'Infrastructure deployment and end-to-end smoke succeeded.'
