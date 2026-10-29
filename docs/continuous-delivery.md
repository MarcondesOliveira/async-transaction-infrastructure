# Continuous delivery — implementation in progress

## Required outcome

A push to main in any service must validate, test, package, publish the exact ZIP
and trigger the infrastructure deployment pipeline. Deployment must apply the
matching S3 key/hash through Terraform, verify the affected Lambda and run an
appropriate smoke check. No local command should be needed to finish routine
delivery. PRs validate without deployment credentials. Infrastructure changes
use the infrastructure repository pipeline. Destroy remains separately confirmed.

This chain is not complete yet. Existing CI/package jobs and manual publication
workflows are already validated; publication alone is not deployment. The central
workflow below is prepared but must be validated in GitHub before service pushes
are connected to it. Infrastructure-push apply and destroy automation are still
separate pending increments; they are not implied by the new static CI workflow.

## Central service deployment workflow

`Deploy service` accepts an allowlisted service, the full published commit SHA
and `operation` (`plan` by default, or `deploy`). It is dispatchable on main so
application delivery can later invoke it using `INFRA_WORKFLOW_TOKEN`.

The job assumes the infrastructure OIDC role, reads the commit's S3 manifest and
object checksum/metadata, initializes the correct existing backend and reads the
latest Terraform state. It preserves the other services' deployed key/hash before
overriding only the requested service. The simulator always updates its two
functions together. A plan guard permits only code updates to those functions;
deletion, replacement, configuration changes and updates to unrelated resources
fail visibly instead of being applied as a routine service delivery.

`plan` validates without applying. `deploy` applies that same saved plan, waits
for updates, verifies the deployed hash/runtime/architecture and runs a synthetic
main-API transaction through the full asynchronous flow to SUCCEEDED/APPROVED.
Smoke transactions use synthetic data only; this check creates demonstration
records when deploy is explicitly selected. A failed smoke does not roll back
automatically; inspect the correlated evidence before deciding recovery.

Jobs serialize per stack with GitHub's `queue: max` (up to 100 queued jobs), not
the default single-pending behavior that replaces another pending deployment.
Terraform's backend lock remains enabled, and stale plans fail rather than
silently overwriting a concurrent change. All future infrastructure-mutating
workflows must share these stack groups; deploy ordering and out-of-band manual
changes still require care. A queue overflow/cancel must fail delivery visibly.

Backend, account, role, artifact bucket and smoke URL are repository variables:
`AWS_REGION`, `AWS_ACCOUNT_ID`, `AWS_TERRAFORM_ROLE_ARN`, `TF_STATE_BUCKET`,
`ARTIFACT_BUCKET`, `SMOKE_API_URL`. Stable non-artifact stack settings are stored
as `CORE_CONFIG_JSON` and `SIMULATOR_CONFIG_JSON` secrets. Snapshots were taken
from the existing local Terraform variable values, excluding artifact pins;
update them deliberately when infrastructure configuration changes. Real values
remain outside source and raw state/plan files are not uploaded as public artifacts.

`Infrastructure CI` runs on PR/main push and validates formatting, Terraform
configuration with backend disabled, shell syntax and delivery/smoke safeguards.
It requires no AWS credentials and never deploys.

First validation after push: dispatch `Deploy service` on main with
`service=async-transaction-api`,
`source_commit=30b253fe88ffb7fb04c493d32687f5e834075199`, `operation=plan`.
Do not select deploy or repeat already-published S3 writes just to test OIDC.

## Simplest cross-repository authentication for this lab

The owner chose a short-lived fine-grained personal access token rather than a
GitHub App. Create it in GitHub, select only the infrastructure repository and
grant repository Actions read/write (Metadata read is implicit). Set a short
expiry, for example seven days. The token needs no AWS permission, source write,
administration permission or access to the other application repositories.

Store the same token in the four application repositories as the Actions secret
`INFRA_WORKFLOW_TOKEN`. Do not put it in chat, source, shell history, tfvars,
workflow inputs, artifacts or logs. It is used only to dispatch/check the central
deployment workflow; normal checkout uses the repository-scoped GITHUB_TOKEN.
Revoke the temporary token and remove its secrets when the demonstration ends.
Expiry must fail the dispatch visibly, not silently leave S3 publication reported
as a completed deployment. A GitHub App remains the long-lived alternative.

AWS access continues via OIDC: application jobs publish only, and the central
infrastructure workflow assumes the separate Terraform role from main. The
infrastructure repository's immutable OIDC subject has been verified and its
legacy trust entry corrected after owner approval. This change adds no IAM
administration to routine deployment.

## Deployment rules to preserve

- Use an allowlisted service/stack mapping and verified artifact metadata; never
  evaluate event input as shell code or execute code from downloaded artifacts.
- Serialize deployments for the same state. Refresh other services' deployed
  artifact key/hash from current state under that serialization, rather than
  restoring stale defaults when a different service changes.
- Apply the reviewed/generated plan from the same execution. Reject unintended
  resource deletion/replacement in a routine code delivery. No latest mutable ZIP.
- Verify the deployed package hash and function update status; distinguish those
  checks from application smoke tests. Report failed deployment back to the
  initiating delivery instead of reporting only a successful dispatch.
- Keep backend/configuration values and credentials outside tracked source.
- Full bootstrap/IAM provisioning is not a routine code update. Existing least
  privilege restrictions remain unless a specific new permission is reviewed.
- Destroy must not be triggered by a service push, test or cleanup side effect.

## Current prerequisite evidence — 2026-10-29

Terraform fmt/validate passed. Saved bootstrap plan
`stage13-infrastructure-oidc.tfplan`: **0 add, 1 in-place change, 0 destroy**,
only the Terraform deployer's subject changes to the infrastructure repository's
verified immutable main-branch identity. Audience and all identity permissions
remain unchanged. Real IDs are in ignored tfvars, with generic tracked inputs.
After explicit owner approval, the saved plan was applied: **0 added, 1 changed,
0 destroyed**. Live IAM inspection confirmed the immutable infrastructure main
subject and STS audience. The post-apply plan returned exit code 0 with no changes.
Real runner OIDC access remains untested; this is configuration verification only.
The owner created the temporary
token and registered `INFRA_WORKFLOW_TOKEN` in all four application repositories.
Read-only secret-name queries confirmed its presence in each; its value was not
read or supplied to the agent. Token scope/validity still require the actual
dispatch test. No central delivery workflow has been executed and no new
application deployment has occurred in this preparation.

Local central-workflow preparation: 18 isolated unit tests passed, covering
preservation of other service versions, artifact mismatches, destructive/config
plan rejection, the simulator pair, deployed hashes and smoke outcomes. YAML/shell
checks and Terraform fmt passed. A plan-only run with the owner's local identity
and the actual existing state/published API artifact passed, proposing only the
API package update. No apply or real smoke transaction was run. This does not
prove permissions of the GitHub OIDC role; its first runner plan remains pending.

References: [GITHUB_TOKEN and additional authentication](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token),
[workflow dispatch permission](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event).
See also [deployment concurrency queues](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
