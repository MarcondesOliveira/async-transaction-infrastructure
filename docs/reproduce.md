# Reproduce the complete lab

Return to the [project entry point](../README.md).

Use **your own AWS account and GitHub repositories**, not the author's account.
The implementation has two distinct phases: owner-operated first provisioning,
then automatic routine delivery. This runbook was inspected against source and
existing deployment evidence; it was not replayed in a second empty account
during documentation work. It is not a promise of one-click account setup.

## 1. Choose a reproduction scope

- Code/tests only: section 2 requires no AWS resources or GitHub secrets.
- AWS runtime: sections 2–6 provision billable services with your owner identity.
- Automatic delivery: sections 7–9 configure CI/CD after runtime exists.
- Final removal: section 10 is a separate, explicitly authorized operation.

Use synthetic data only. Endpoints lack caller authentication and webhook
signatures. Repositories may require access while private; this guide does not
change visibility or grant reuse rights.

## 2. Obtain the five repositories and test locally

Use Linux/Bash (pipelines use Ubuntu 24.04), Git, .NET SDK 10.0, Python 3,
Terraform >=1.14 and <2, AWS CLI v2, GitHub CLI, jq, OpenSSL, zip/unzip and GNU
sha256sum/realpath. Workflows pin Terraform 1.16.1. Preserve provider lock files;
check application `global.json` for SDK roll-forward. AWS CLI must support the
S3 conditional-write/checksum options used in `.github/scripts/publish.sh`.

For reading/tests, clone accessible author repositories. For your own delivery,
first obtain authorized forks/copies under your owner. Keep the five repository
names unchanged. Assuming those copies already exist:

```bash
set -euo pipefail
export LAB_OWNER=YOUR_GITHUB_LOGIN
mkdir -p async-transaction-lab
cd async-transaction-lab
export LAB_WORKSPACE="$PWD"
for repository in async-transaction-api async-transaction-request-handler async-transaction-callback-handler external-transaction-processor-simulator async-transaction-infrastructure; do
  git clone "https://github.com/$LAB_OWNER/$repository.git"
done
```

Never copy the author's ignored tfvars, backend files, state, plans or `.terraform`
directory. Each account needs its own state/configuration. Run tests:

```bash
set -euo pipefail
for repository in async-transaction-api async-transaction-request-handler async-transaction-callback-handler external-transaction-processor-simulator; do
  (
    cd "$LAB_WORKSPACE/$repository"
    dotnet restore --disable-parallel
    dotnet test --configuration Release --no-restore --disable-build-servers -m:1
    python3 -m unittest discover -s tests/delivery -v
  )
done
cd "$LAB_WORKSPACE/async-transaction-infrastructure"
python3 -m unittest discover -s tests/delivery -v
terraform fmt -check -recursive
```

Stop on any failure. Tests use controlled substitutes, not live AWS. A local
Swagger host does not emulate DynamoDB, queues or the Stream worker; a production
adapter POST needs AWS resources. No LocalStack setup is included.

## 3. Prepare ownership, AWS identity and OIDC

Until section 8, disable each application's `Deliver ...` workflow (`publish.yml`)
and infrastructure's `Deliver infrastructure` (`infrastructure.yml`) in your
copies. Leave CI enabled. Do not assume fork defaults alone prevent delivery.
Do not execute `Final lab teardown` now.

In **each of the four application copies**, edit `REPOSITORY` in
`.github/scripts/deploy.py` to `YOUR_GITHUB_LOGIN/async-transaction-infrastructure`.
It is a public repository reference, not a secret. Keep `SERVICE` and repository
names unchanged; renaming services requires other package/IAM/allowlist changes.
Commit adaptations before building: package identity must describe a clean
checked-out commit, not uncommitted source changes.

Authenticate with an owner-approved lab profile/SSO session capable of first
IAM/S3/serverless provisioning. Never put permanent AWS keys in GitHub:

```bash
export AWS_PROFILE=YOUR_LAB_PROFILE
export AWS_REGION=us-east-1
aws sts get-caller-identity
gh auth status
```

Check the AWS account yourself before any apply. Keep account outputs local.
Bootstrap expects an **existing** IAM OIDC provider for
`https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
Have the owner register it if absent; do not delete/replace a shared provider.
[AWS setup](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/).

Inspect the actual subject configuration for all five of your repositories:

```bash
gh api "repos/$LAB_OWNER/async-transaction-infrastructure/actions/oidc/customization/sub"
```

Repeat for the applications. When available, copy verified `sub_claim_prefix`
values into the ignored bootstrap prefix variables. Never reuse author IDs or
relax trust to a wildcard. If no prefix is supplied, verify the actual subject
format before enabling access; Terraform's legacy name fallback must match it.
[GitHub OIDC/AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

## 4. Owner-provision bootstrap once

```bash
cd "$LAB_WORKSPACE/async-transaction-infrastructure"
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
```

Edit the ignored file: set `github_owner` and verified infrastructure/application
OIDC prefixes. This guide keeps `project_name=async-transaction-processing`,
`environment=dev` and `us-east-1`. If changed, update backend keys and config JSON
too. Leave API/mapping ID sets empty until resources exist. Keep
`enable_destroy_role=false`; final-teardown IAM is not needed now.
Budget email null skips the optional alert. A budget is not a spending cap.

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap plan -out=initial-bootstrap.tfplan
```

Inspect the resource/IAM/cost changes. Only after explicit owner approval:

```bash
terraform -chdir=bootstrap apply initial-bootstrap.tfplan
```

Preserve the ignored **local bootstrap state** securely, separately from remote
runtime states. Do not commit or discard it. Capture outputs in your shell:

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ARTIFACT_BUCKET="$(terraform -chdir=bootstrap output -raw artifact_bucket)"
export TF_STATE_BUCKET="$(terraform -chdir=bootstrap output -raw terraform_state_bucket)"
export AWS_ARTIFACT_ROLE_ARN="$(terraform -chdir=bootstrap output -raw artifact_publisher_role_arn)"
export AWS_TERRAFORM_ROLE_ARN="$(terraform -chdir=bootstrap output -raw terraform_deployer_role_arn)"
```

The routine role cannot administer IAM or create arbitrary API/mapping IDs.
Owner credentials provision the first runtime stacks; do not grant that role
administrator access to bypass this intentional boundary.

## 5. Build and publish four initial packages once

Automatic delivery expects existing Lambda state. Use the checked-in scripts
with your owner credentials for the first packages; this is a one-time setup,
not a local requirement for subsequent delivery. Ensure adaptations are committed
and every checkout is clean. Keep package files outside repositories:

```bash
set -euo pipefail
export LAB_ARTIFACT_ROOT="$(mktemp -d)"
for repository in async-transaction-api async-transaction-request-handler async-transaction-callback-handler external-transaction-processor-simulator; do
  (
    cd "$LAB_WORKSPACE/$repository"
    test -z "$(git status --porcelain)"
    export GITHUB_SHA="$(git rev-parse HEAD)"
    bash .github/scripts/package.sh "$LAB_ARTIFACT_ROOT/$repository"
    SOURCE_COMMIT="$GITHUB_SHA" bash .github/scripts/publish.sh "$LAB_ARTIFACT_ROOT/$repository" --verify-only
    SOURCE_COMMIT="$GITHUB_SHA" bash .github/scripts/publish.sh "$LAB_ARTIFACT_ROOT/$repository" --publish
  )
done
```

Stop if any build/upload fails. Each directory contains a ZIP, checksum file and
`build-manifest.json`. Inspect `service`, `commit`, `s3Key` and `sourceCodeHash`.
Use **your exact manifest's** key/hash, not author values or placeholder hashes.
S3 rejects existing keys instead of overwriting. Do not blindly rerun after a
partial upload or rebuild/replace the same commit's package. Inspect receipts,
objects and checksums; there is no atomic multi-object upload or auto-rollback.

## 6. Owner-provision simulator, then core

Create ignored backend/tfvars files. Replace backend buckets with your
`TF_STATE_BUCKET`; keep different keys for the two stacks:

```bash
cd "$LAB_WORKSPACE/async-transaction-infrastructure"
cp stacks/external-simulator/backend.hcl.example stacks/external-simulator/backend.hcl
cp stacks/core/backend.hcl.example stacks/core/backend.hcl
cp stacks/external-simulator/terraform.tfvars.example stacks/external-simulator/terraform.tfvars
cp stacks/core/terraform.tfvars.example stacks/core/terraform.tfvars
```

Populate inputs from your manifests:

| Variable prefix | Package manifest |
| --- | --- |
| core `lambda_` | `async-transaction-api` |
| core `request_handler_` | `async-transaction-request-handler` |
| core `callback_handler_` | `async-transaction-callback-handler` |
| simulator `simulator_` | `external-transaction-processor-simulator` |

For each prefix, `<prefix>artifact_key` receives `s3Key` and
`<prefix>source_code_hash` receives `sourceCodeHash` (Base64, not hexadecimal).
Align operational values with `.github/config/*.json`, which later delivery
uses as desired settings. Core `callback_url=null` uses its own callback endpoint.

Provision the simulator independently with the owner identity:

```bash
terraform -chdir=stacks/external-simulator init -backend-config=backend.hcl
terraform -chdir=stacks/external-simulator validate
terraform -chdir=stacks/external-simulator plan -out=initial-simulator.tfplan
```

Review the simulator plan and obtain owner approval before applying:

```bash
terraform -chdir=stacks/external-simulator apply initial-simulator.tfplan
terraform -chdir=stacks/external-simulator output -raw simulator_api_url
```

Put that URL into core's ignored `external_processor_base_url`; do not keep the
`.invalid` example for end-to-end tests. Then:

```bash
terraform -chdir=stacks/core init -backend-config=backend.hcl
terraform -chdir=stacks/core validate
terraform -chdir=stacks/core plan -out=initial-core.tfplan
```

Review the core plan and obtain owner approval before applying:

```bash
terraform -chdir=stacks/core apply initial-core.tfplan
export API_BASE_URL="$(terraform -chdir=stacks/core output -raw transactions_api_url)"
```

Open `$API_BASE_URL/swagger/index.html` and follow the
[main POST/GET demonstration](../README.md#manual-demonstration) before enabling
delivery. The simulator receives the callback URL in each submission; it has no
access to the main transaction table.

## 7. Scope routine deployment to the created resources

Collect **your** core HTTP/REST API IDs, simulator HTTP API ID and the three
event-source mapping UUIDs from AWS or filtered state. Example:

```bash
terraform -chdir=stacks/core show -json | jq '[.values.root_module.resources[] | select(.type == "aws_lambda_event_source_mapping") | .values.uuid]'
terraform -chdir=stacks/external-simulator output -raw worker_event_source_mapping_uuid
```

For API IDs filter state by `aws_apigatewayv2_api`/`aws_api_gateway_rest_api` and
read `.values.id`; do not print/upload raw state. Put values into ignored bootstrap
`deployment_http_api_ids`, `deployment_rest_api_ids` and
`deployment_event_source_mapping_ids`. Owner-review a new saved bootstrap plan
and apply it to scope the routine role. Replacement IDs later need owner review.

After automatic deploys, initial runtime tfvars contain stale package pins.
**Do not reuse them for routine local apply:** they could revert services.
The central scripts preserve current packages from remote state instead.

## 8. Configure GitHub, then enable delivery

Set Actions variables in **your own repositories**:

| Location | Variables |
| --- | --- |
| Each application | `AWS_REGION`, `AWS_ACCOUNT_ID`, `ARTIFACT_BUCKET`, `AWS_ARTIFACT_ROLE_ARN` |
| Infrastructure | `AWS_REGION`, `AWS_ACCOUNT_ID`, `TF_STATE_BUCKET`, `ARTIFACT_BUCKET`, `AWS_TERRAFORM_ROLE_ARN`, `SMOKE_API_URL` |

`SMOKE_API_URL` is the main `transactions_api_url`, not simulator/callback.
ARN values come from bootstrap. These are metadata, not AWS credentials; keep
real values outside source. Leave `TEARDOWN_ENABLED` unset or `false` and do not
configure a destroy role as the deploy role.

Create infrastructure Actions secrets `CORE_CONFIG_JSON` and
`SIMULATOR_CONFIG_JSON`. Minimal core JSON (replace the URL locally):

```json
{
  "aws_region": "us-east-1",
  "project_name": "async-transaction-processing",
  "environment": "dev",
  "external_processor_base_url": "https://replace-with-your-simulator.invalid",
  "callback_url": null
}
```

Minimal simulator JSON:

```json
{
  "aws_region": "us-east-1",
  "project_name": "async-transaction-processing",
  "environment": "dev"
}
```

For local copies use ignored names ending `.tfvars.json`. GitHub receives JSON
**contents**, not filenames or double-encoded quoted JSON. Do not include package
keys/hashes: scripts reject stale pins in base secrets. Operational values come
from the tracked `.github/config/*.json` files shared by both delivery paths.

Create a short-lived fine-grained GitHub token restricted to **your infrastructure
repository**, Actions **read/write** (Metadata read is implicit). Store it as
`INFRA_WORKFLOW_TOKEN` in each application using the secret UI or interactive
`gh secret set`. Never paste tokens into source, workflow inputs, shell history
or screenshots. The token dispatches/checks central delivery; AWS uses OIDC.
A GitHub App is a possible future long-lived alternative.
[Token permissions](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens).

Re-enable all four `Deliver ...` workflows and `Deliver infrastructure` only
when these prerequisites are ready. Leave teardown unexecuted. CI can remain
enabled during setup. Required branch checks/protection are separate owner settings,
not something a successful CI run creates automatically.

## 9. Validate automatic delivery and demonstrate behavior

1. Push a reviewed application change to main. Observe CI, `Deliver ...` and its
   linked central `Deploy service`. Confirm the exact commit and package identity;
   only that service changes (two functions for simulator).
2. Confirm Lambda hash/status and a fresh smoke reaching `SUCCEEDED/APPROVED`;
   the originating delivery must also succeed. Upload/dispatch alone is not enough.
3. Push a reviewed infrastructure change. Observe `Infrastructure CI` and
   `Deliver infrastructure` for both stacks, preserving packages. Each smoke uses
   an independent key. Guards reject IAM, destructive/replacement and out-of-scope
   changes visibly; they do not silently skip those actions.
4. Use the **main API** in Swagger/Bruno for POST/GET. `Idempotency-Key` is a
   header, not a body field. Same key/body replays; altered body returns `409`.
   New keys exercise success plus `reject-`/`fail-` destination scenarios. Compare
   transaction/correlation/processor IDs across logs; use no real account numbers.

Common errors: missing header → `400`; changed content with same key → `409`;
expired cross-repository token → dispatch/read failure; wrong subject → STS
denial; empty state → missing first-provisioning prerequisite. For denied provider
reads, inspect the exact action/resource before granting permission. Do not
overwrite immutable packages or repeatedly trigger deploy to repair an error.
[Delivery details](continuous-delivery.md) and [logs/DLQ recovery](lab-operations.md)
describe inspection and limits.

Routine delivery now completes through GitHub Actions without local deploy
commands. First provisioning and privileged IAM maintenance remain owner-operated.

## 10. Preserve evidence, then explicitly authorize final removal

Record commits, successful runs and synthetic results first. Not all records
expire in a day: main transactions have no TTL. Logs, queues, artifact versions
and Actions storage can continue consuming resources.

Follow [final teardown](final-teardown.md) only when ending the lab. Preview is
non-destructive. Actual deletion requires freeze, reviewed SHA, exact confirmation
and a separately enabled role; simulator precedes core and bootstrap is last.
**Both bootstrap buckets have `force_destroy=true`: approving their destruction
can purge objects and versions.** Preserve evidence/states first. Inventory
residual resources/costs, revoke the temporary token and leave delivery disabled
after closure so later pushes cannot recreate runtime.
