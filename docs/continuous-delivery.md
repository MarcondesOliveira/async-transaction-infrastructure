# Continuous delivery — implementation in progress

## Required outcome

A push to main in any service must validate, test, package, publish the exact ZIP
and trigger the infrastructure deployment pipeline. Deployment must apply the
matching S3 key/hash through Terraform, verify the affected Lambda and run an
appropriate smoke check. No local command should be needed to finish routine
delivery. PRs validate without deployment credentials. Infrastructure changes
use the infrastructure repository pipeline. Destroy remains separately confirmed.

The service chain has now been validated in all four repositories: automatic
push, CI/package, publication, central deploy, Lambda verification and synthetic
smoke, including source-workflow success propagation. Infrastructure-push delivery
is implemented below but its first GitHub execution is pending. Protected destroy
remains a separate pending increment. Historical preparation notes below do not
override this current status.

## Runtime infrastructure changes after a main push

`Deliver infrastructure` listens for successful `Infrastructure CI` from a push
to this repository's main, not PRs/forks/failed CI/manual CI. Manual dispatch on
main supports `plan` (default) and `deploy`. The runner checks out the exact CI
head commit and rejects it if main has since advanced. Matrix stacks are `core`
and `external-simulator`, with `max-parallel: 1`. Each job shares its existing
`terraform-<stack>` concurrency group with service delivery (`queue: max`) and
uses the backend lock. There is no atomic transaction across stacks: an applied
first stack is not rolled back if a later stack fails.

Operational values belong in the allowlisted, typed JSON files under
`.github/config/`. They intentionally override the old non-artifact setting
snapshots in `CORE_CONFIG_JSON` / `SIMULATOR_CONFIG_JSON`; only infrastructure
source edits and these tracked settings travel with a push. Region/project/env
and real endpoints remain configured outside source. Adding a new configurable
setting requires updating the allowlist/tests deliberately. Service delivery uses
the same merged settings, so a later code deploy cannot undo a previous setting
change. Terraform defaults may be overridden by tracked operational settings;
edit the JSON values to change those settings in the pipeline.

`infrastructure.sh` reads the latest state, preserves every deployed Lambda
key/hash, generates a saved plan, and checks it before applying. The guard permits
only creates/updates of known runtime resource types. It rejects deletes and
replacements, IAM mutations, unsupported resource types, new functions and package
changes. Thus this is routine runtime delivery, not unrestricted account
provisioning: IAM/bootstrap and permission expansion remain owner-operated,
as agreed. Such changes are not automatically applied by this workflow, even
when committed; runtime IAM diffs fail instead of broadening permissions.
Existing API/mapping IAM scopes still apply and may reject new resource creation;
show and review errors rather than granting wildcard access.

After apply, verify every existing function's package/status and run the synthetic
main-API smoke. Each matrix stack uses a distinct idempotency key, so the second
smoke creates a fresh transaction rather than reusing the first result.
State, raw plans and full environment config remain in private
runner temporary files, not uploaded artifacts. There is no automatic recovery,
rollback, destroy or second apply on failure. Inspect the per-resource action
summary and error before proceeding. A deliberate worker disable or integration
break will fail the end-to-end smoke; that's a real failed delivery, not hidden.

First validation: after the owner pushes, expect `Infrastructure CI` then
`Deliver infrastructure`. The initial settings match the existing environment;
the baseline local plans show no resource changes. A description-only update on
the main API Lambda is included to demonstrate a real infrastructure apply
without changing application code, capacity or behavior. The workflow will
validate both stacks and send synthetic test transactions. Inspect runner
results before claiming actual infrastructure changes are automated/validated.

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
update identity/endpoint values deliberately when they change. Operational
settings now come from the tracked JSON files described above. Real values
remain outside source and raw state/plan files are not uploaded as public artifacts.

`Infrastructure CI` runs on PR/main push and validates formatting, Terraform
configuration with backend disabled, shell syntax and delivery/smoke safeguards.
It requires no AWS credentials and never deploys.

Historical first validation dispatched `Deploy service` on main with
`service=async-transaction-api`,
`source_commit=30b253fe88ffb7fb04c493d32687f5e834075199`, `operation=plan`.
Do not reuse this historical artifact for a new deploy or repeat already-published
S3 writes just to test OIDC. Routine new service versions follow their automatic
delivery workflows; plan-only diagnostics should use the intended exact commit.

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

GitHub runner validation: Infrastructure CI `40964440758` passed for commit
`f640e0e15a57a22229a7d4896619a8157b1a65d6`. The first central plan
(`40973525879`) authenticated through OIDC but failed during Lambda refresh:
`lambda:GetFunctionCodeSigningConfig` was missing. After owner approval, a saved
bootstrap plan added only that read action within the existing project-function
scope: **0 added, 1 changed, 0 destroyed**. The post-apply bootstrap plan showed
no changes. Central plan `40974175954` then succeeded through OIDC, reporting only
`aws_lambda_function.transaction_api` as changed and no destructive changes.
It explicitly reported `Plan validated; nothing applied.` Application deployment,
real smoke execution and source-repository dispatch remain pending.

References: [GITHUB_TOKEN and additional authentication](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token),
[workflow dispatch permission](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event).
See also [deployment concurrency queues](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
