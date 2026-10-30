#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${SERVICE:?Select service}"
: "${SOURCE_COMMIT:?Select source commit}"
: "${STACK_CONFIG_JSON:?Provide stack configuration}"
: "${TF_STATE_BUCKET:?Configure state bucket}"
: "${ARTIFACT_BUCKET:?Configure artifact bucket}"
: "${AWS_ACCOUNT_ID:?Configure AWS account}"
: "${AWS_REGION:?Configure AWS region}"
: "${RUNNER_TEMP:?Provide temporary workspace}"
operation="${OPERATION:-plan}"
[[ "$operation" == plan || "$operation" == deploy ]]
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]
case "$SERVICE" in
  async-transaction-api|async-transaction-request-handler|async-transaction-callback-handler) stack=core ;;
  external-transaction-processor-simulator) stack=external-simulator ;;
  *) echo 'Service not allowlisted' >&2; exit 1 ;;
esac

workspace="$(mktemp -d "$RUNNER_TEMP/central-delivery.XXXXXX")"
printf '%s' "$STACK_CONFIG_JSON" > "$workspace/base.json"
python3 .github/scripts/infrastructure.py config "$stack" "$workspace/base.json" \
  ".github/config/$stack.json" "$workspace/config.json"
project="$(jq -er '.project_name | select(test("^[a-z0-9-]+$"))' "$workspace/config.json")"
environment="$(jq -er '.environment | select(test("^[a-z0-9-]+$"))' "$workspace/config.json")"
test "$(jq -r '.aws_region' "$workspace/config.json")" = "$AWS_REGION"
test "$(aws sts get-caller-identity --query Account --output text)" = "$AWS_ACCOUNT_ID"
directory="stacks/$stack"
key="$SERVICE/$SOURCE_COMMIT/$SERVICE.zip"
aws s3api get-object --bucket "$ARTIFACT_BUCKET" \
  --key "$SERVICE/$SOURCE_COMMIT/build-manifest.json" --expected-bucket-owner "$AWS_ACCOUNT_ID" \
  "$workspace/manifest.json" > /dev/null
aws s3api head-object --bucket "$ARTIFACT_BUCKET" --key "$key" \
  --expected-bucket-owner "$AWS_ACCOUNT_ID" --checksum-mode ENABLED \
  --output json > "$workspace/object.json"

terraform -chdir="$directory" init -input=false -no-color \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=$project/$environment/$stack.tfstate" \
  -backend-config="region=$AWS_REGION" -backend-config=encrypt=true \
  -backend-config=use_lockfile=true > "$workspace/init.log" 2>&1 || {
    tail -n 60 "$workspace/init.log"; exit 1;
  }
terraform -chdir="$directory" validate -no-color
terraform -chdir="$directory" show -json > "$workspace/state.json"
python3 .github/scripts/delivery.py inputs "$workspace/state.json" "$workspace/config.json" \
  "$workspace/manifest.json" "$workspace/object.json" "$SERVICE" "$SOURCE_COMMIT" \
  "$workspace/deployment.tfvars.json" "$workspace/context.json"
terraform -chdir="$directory" plan -input=false -no-color -lock-timeout=10m \
  -var-file="$workspace/deployment.tfvars.json" -out="$workspace/deployment.tfplan" \
  > "$workspace/plan.log" 2>&1 || { tail -n 80 "$workspace/plan.log"; exit 1; }
terraform -chdir="$directory" show -json "$workspace/deployment.tfplan" > "$workspace/plan.json"
python3 .github/scripts/delivery.py plan "$workspace/plan.json" "$SERVICE"
printf 'Service: %s\nSource commit: %s\nOperation: %s\n' "$SERVICE" "$SOURCE_COMMIT" "$operation" \
  >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
if [[ "$operation" == plan ]]; then
  echo 'Plan validated; nothing applied.'
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
done < <(jq -r '.functions[]' "$workspace/context.json")
jq -s '.' "$workspace"/function-*.json > "$workspace/functions.json"
python3 .github/scripts/delivery.py verify "$workspace/context.json" "$workspace/functions.json"
python3 .github/scripts/smoke.py
echo 'Deployment and end-to-end smoke succeeded.'
