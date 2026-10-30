# Final lab teardown — visitor runbook

[Project overview](../README.md) · [Full reproduction guide](reproduce.md)

**Where do I run this?** Runtime deletion starts in **your GitHub infrastructure
repository → Actions → Final lab teardown → Run workflow**. GitHub's runner
executes Terraform; you do not need this chat or an assistant to start it.
Preparing its restricted IAM role and deleting bootstrap afterward are separate
commands in **your local terminal, at the root of your infrastructure checkout**.
The detailed sequence and optional GitHub CLI equivalents are below.

This is an end-of-lab procedure, not part of initial deployment. Do not copy/run
all blocks as one script: previews, IAM provisioning, runtime deletion and final
bucket cleanup have separate review/approval gates. Examples target **your own**
repositories, state and AWS account. Deleting tables/queues/logs and purging
bucket versions cannot be undone by rerunning Terraform.

No resource should be deleted during CI/CD preparation or documentation. This
workflow is manual-only. Its default `plan` operation previews deletions and
never applies. Before freeze/role setup, it uses the existing deploy role. When
`TEARDOWN_ENABLED=true` and the destroy role is configured, a preview uses that
role too, including for recovery reads after partial deletion.
`destroy` uses a separate, optional
role which has not been provisioned by preparing these files.

## Protection boundaries

- Supply the full reviewed current main SHA. Preflight requires that SHA and a
  successful Infrastructure CI for it. No push, PR, schedule or service can
  automatically start this workflow.
- `destroy` requires infrastructure variable `TEARDOWN_ENABLED=true` and exact
  confirmation `DESTROY <project>-<environment>`, derived from the existing config.
  Delivery workflows fail visibly before AWS authentication while frozen.
- Simulator must succeed before core starts, via explicit job dependencies.
  Both use the same per-stack concurrency groups as deploy plus backend locks.
- Generate a fresh `plan -destroy`, reject anything except deletions of known
  runtime types and the seven exact existing runtime roles/inline policies, then
  apply that exact saved plan. No direct unreviewed `terraform destroy` command.
- Check each stack state has no remaining managed resources. This does not
  replace the final AWS inventory/cost check. No smoke POST follows deletion.
- Raw state/plans stay in private runner temporary files, not downloadable
  artifacts. Resource addresses to be deleted appear in logs/summary.

The ordinary deploy role remains unable to remove IAM. `enable_destroy_role`
defaults to false in bootstrap. Enabling it owner-side creates a separate role
and three inline policies: project runtime read/delete actions, removal of only
the seven runtime roles, and state/lock access plus artifact read. It has no IAM
create/update/grant permissions, bucket teardown, bootstrap-role deletion or
account-wide administrator policy. Existing API IDs/mapping UUIDs still bound
its runtime scope. No new permissions are attached to the routine deploy role.

Auxiliary teardown permissions include `iam:ListInstanceProfilesForRole` on the
seven runtime roles, needed before the provider deletes them. Deleted-mapping
polling also needs `lambda:GetEventSourceMapping` on `*`, limited by
`aws:RequestedRegion`; mutation remains scoped to the configured mapping UUIDs.
HTTP API stage removal needs legacy `logs:GetLogDelivery`, `logs:ListLogDeliveries`
and `logs:DeleteLogDelivery`. Those permission-only actions have no resource-level
ARN scope, so they use `*` with the same region restriction. This is a deliberate
regional permission exception in the temporary destroy role, not a claim that
every auxiliary permission is isolated to one project resource. It grants no
delivery creation/update, log resource-policy administration or bucket deletion.

Deleting REST API method settings also calls `UpdateStage` to reset those settings
before stage deletion. The temporary role therefore allows `apigateway:PATCH`
only on `/restapis/<configured-api-id>/stages/<environment>` for the existing REST
API IDs in bootstrap inputs. It does not grant PATCH on API roots, HTTP APIs or
other stages. This permission operates at stage level (not individual PATCH
fields); the reviewed teardown plan still permits deletion actions only.

OIDC trust is the infrastructure repository's verified main subject and STS
audience, like the existing infrastructure role. Workflow confirmations are not
a second independent security boundary against someone allowed to rewrite main.
Provision the privileged teardown role only for the final window, then remove
it with bootstrap cleanup. No additional GitHub environment/reviewer feature is
assumed to exist in this private lab repository.

## 1. Preserve evidence and identify your deployment

Keep required diagrams, source commits, Actions run links/results and synthetic
transaction evidence. Export any table data/logs you need **before deletion** to
approved private storage, not Git. Remote state versions are not application-data
backups. Stop manual API requests, external producers and client test loops.

Prerequisites: the existing deployment from the [reproduction guide](reproduce.md),
GitHub access to manage Actions/variables, GitHub CLI authentication, Terraform,
AWS CLI and owner-approved AWS credentials for the IAM/bootstrap steps. Retain
the original ignored bootstrap `terraform.tfvars` and local `terraform.tfstate`,
plus the runtime backend files. A fresh clone without that state is not enough
to safely remove the original bootstrap; do not initialize an unrelated account
or import/recreate resources to work around missing state.

**Local terminal:** replace all placeholder values, enter your checkout, and set
these variables for this session. Adjust project/environment/region if your
deployment used different values; they must match its configuration.

```bash
set -euo pipefail
cd /path/to/your/async-transaction-infrastructure
export LAB_OWNER=YOUR_GITHUB_LOGIN
export LAB_REPOSITORY="$LAB_OWNER/async-transaction-infrastructure"
export LAB_PROJECT=async-transaction-processing
export LAB_ENVIRONMENT=dev
export AWS_PROFILE=YOUR_LAB_PROFILE
export AWS_REGION=us-east-1
gh auth status
aws sts get-caller-identity
git status --short
test -z "$(git status --porcelain)"
export LAB_TEARDOWN_SHA="$(gh api "repos/$LAB_REPOSITORY/commits/main" --jq .sha)"
test "$(git rev-parse HEAD)" = "$LAB_TEARDOWN_SHA"
gh run list --repo "$LAB_REPOSITORY" --workflow ci.yml --commit "$LAB_TEARDOWN_SHA"
```

Check the returned AWS account yourself; do not publish it. Require a clean
checkout matching the reviewed remote main SHA and a successful Infrastructure CI
for that exact SHA. If local/remote differ, stop and update/review your checkout
without overwriting local state/configuration. If you push another change later,
refresh/review the SHA, wait for its CI and regenerate the deletion preview.

## 2. Freeze automatic delivery and drain active runs

**GitHub interface, in each of your four application repositories:**
open **Actions → Deliver API / Deliver Request Handler / Deliver Callback Handler /
Deliver Simulator** (the corresponding name in that repository), then the
workflow's **… menu → Disable workflow**. In infrastructure, disable
**Actions → Deliver infrastructure**. Leave **Infrastructure CI** and
**Final lab teardown** enabled. **Teardown stack helper** is an internal reusable
workflow; do not try to launch it directly. **Deploy service** is not the teardown
entry point; the freeze below prevents routine deployment through that path too.

In infrastructure, open **Settings → Secrets and variables → Actions → Variables
→ New repository variable** (or edit the existing variable):

| Name | Value |
| --- | --- |
| `TEARDOWN_ENABLED` | `true` |

**Alternative, local terminal:** these commands perform the same freeze; do not
repeat them if you already used the interface.

```bash
for repository in async-transaction-api async-transaction-request-handler async-transaction-callback-handler external-transaction-processor-simulator; do
  gh workflow disable publish.yml --repo "$LAB_OWNER/$repository"
done
gh workflow disable infrastructure.yml --repo "$LAB_REPOSITORY"
gh variable set TEARDOWN_ENABLED --repo "$LAB_REPOSITORY" --body true
```

In **Actions**, inspect all five repositories for running, queued or waiting
deliveries. Wait for them to finish or deliberately cancel them after inspection.
Disabling a workflow does not cancel already started runs. A recent-run listing
is useful, but is not proof that an older waiting run does not exist:

```bash
for repository in async-transaction-api async-transaction-request-handler async-transaction-callback-handler external-transaction-processor-simulator async-transaction-infrastructure; do
  gh run list --repo "$LAB_OWNER/$repository" --limit 100
done
```

Stop producers and wait for in-flight processing; do not receive/purge/redrive
messages just to make counts zero. Never unfreeze delivery during partial teardown.

## 3. Owner-provision the restricted teardown role

**Local terminal / editor:** edit your existing ignored
`bootstrap/terraform.tfvars`, changing only `enable_destroy_role = true`. Keep
your verified OIDC subjects, resource-ID scopes and other deployment inputs.
Do not replace the file with the example or put account values into source.

Generate and inspect a saved plan with your owner identity:

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap plan -out=final-teardown-role.tfplan
terraform -chdir=bootstrap show -no-color final-teardown-role.tfplan
```

For the first enablement, the expected change is the separate destroy role and
its three inline policies. If the plan changes existing roles, buckets or other
resources unexpectedly, stop and investigate; do not approve unrelated drift.
The routine deploy role remains unchanged. State and plans are private local
files covered by ignore rules, not files to attach to a public issue.

**Only after approving that IAM plan**, apply exactly it:

```bash
terraform -chdir=bootstrap apply final-teardown-role.tfplan
terraform -chdir=bootstrap output -raw terraform_destroyer_role_arn
```

Copy the output locally into infrastructure **Settings → Secrets and variables
→ Actions → Variables → New repository variable**, name `AWS_DESTROY_ROLE_ARN`.
Alternatively, set the value without printing it:

```bash
gh variable set AWS_DESTROY_ROLE_ARN --repo "$LAB_REPOSITORY" \
  --body "$(terraform -chdir=bootstrap output -raw terraform_destroyer_role_arn)"
```

This is the optional destroy role, not `AWS_TERRAFORM_ROLE_ARN`. Keep
`enable_destroy_role=true` in local inputs until final bootstrap cleanup, or a
later bootstrap apply could remove it prematurely.

## 4. Preview runtime deletion in GitHub Actions

In **your infrastructure repository**:

1. Open the **Actions** tab.
2. Select **Final lab teardown** in the workflow list on the left.
3. Click **Run workflow** on the right. If missing, verify the workflow exists on
   your default branch, is enabled and you have sufficient repository permissions.
4. Fill the form below and click the second **Run workflow** button to submit.

| Field | Preview value |
| --- | --- |
| Use workflow from / branch | `main` |
| `operation` | `plan` |
| `expected_commit` | Your full reviewed 40-character `LAB_TEARDOWN_SHA`, not the author's SHA |
| `confirmation` | Leave empty |

The preview can also run **before steps 2–3**: it uses the existing deploy role
and does not require freeze or a destroy role. After freeze and role setup, it
uses the configured teardown role instead, without applying the plan. This
supports reads of already-deleted mappings during recovery without broadening
routine deployment permissions. Neither preview order authorizes later deletion.
In the **local terminal**, this is the equivalent entry point:

```bash
gh workflow run destroy.yml --repo "$LAB_REPOSITORY" --ref main \
  -f operation=plan -f expected_commit="$LAB_TEARDOWN_SHA"
gh run list --repo "$LAB_REPOSITORY" --workflow destroy.yml --limit 5
```

Open the newly created run, checking its SHA, operation, time and actor rather
than assuming another concurrent run is yours. Read **Summary** and the jobs
**simulator / teardown** followed by **core / teardown**, specifically
**Generate deletion-only plan and optionally apply the saved plan**.
Each must show `resourcesToDelete` and **`Teardown plan only; nothing deleted.`**
For a known run ID, `gh run view YOUR_RUN_ID --repo "$LAB_REPOSITORY"` shows status.
The label “optionally apply” names a shared step; `operation=plan` never applies.

Review the addresses against your lab. Runtime deletion covers APIs, Lambdas,
tables, messaging, mappings, log groups and runtime IAM; the exact resource count
depends on the deployed revision. Bootstrap buckets/budget/GitHub roles and the
shared OIDC provider are not runtime targets. Stop on unexpected resources or
any failure. A preview does not export table contents or preserve logs for you.

## 5. Execute runtime deletion — explicit final approval required

**This step deletes runtime data and endpoints.** Require the reviewed preview,
preserved evidence, stopped traffic/producers, disabled delivery, drained active
runs, `TEARDOWN_ENABLED=true` and configured `AWS_DESTROY_ROLE_ARN` first.

Repeat **Actions → Final lab teardown → Run workflow**, branch `main`:

| Field | Destructive value |
| --- | --- |
| `operation` | `destroy` |
| `expected_commit` | Same reviewed current main SHA; refresh/review if it changed |
| `confirmation` | `DESTROY <project>-<environment>` exactly |

For the unchanged example project, confirmation is
`DESTROY async-transaction-processing-dev`. It is a safety phrase, not a token.
For your configured values, inspect `printf 'DESTROY %s-%s\n' "$LAB_PROJECT" "$LAB_ENVIRONMENT"`
locally and verify it matches both stack configurations.

**CLI alternative, only after the same explicit approval:**

```bash
gh workflow run destroy.yml --repo "$LAB_REPOSITORY" --ref main \
  -f operation=destroy -f expected_commit="$LAB_TEARDOWN_SHA" \
  -f confirmation="DESTROY $LAB_PROJECT-$LAB_ENVIRONMENT"
```

Do not run both the UI and CLI versions. The workflow generates a **fresh** saved
deletion plan, validates it and applies that exact plan; it does not reuse the
earlier preview's binary file. Simulator must finish before core starts. There
is no automatic rollback/retry after failure. Core is skipped if simulator fails.
Keep the freeze, inspect logs/state and approve recovery instead of switching
back to deploy or blindly rerunning. Teardown permissions/actual removal are not
proven by a successful preview alone.

If an apply fails with `AccessDenied`, keep the freeze and first distinguish
the delete call from a provider precheck or post-delete polling call. A resource
may already be gone while its address remains in state. Inspect AWS and the
current state read-only; do not remove addresses manually or recreate deleted
services. Review the smallest necessary owner-side IAM correction, its saved
plan and approval separately; then publish/review the current source SHA, run a
new preview and explicitly approve recovery of the remaining runtime. Never
assume a role that passed a read-only preview has exercised all delete-time
dependencies. Additional unexpected denials must be investigated, not replaced
with administrator access or an automatic retry loop.

## 6. Verify runtime removal, then clean bootstrap LAST

In the completed run, both stack jobs must report
**`Stack state has no remaining managed resources; final AWS inventory is still required.`**
Check the intended AWS account/region in the console for the project APIs,
Lambdas, Pipes, SQS/SNS, tables, mappings, logs and runtime roles. Do not send a
smoke POST after deletion. Empty Terraform state is not proof that manually
created/untracked resources are absent.

Only after runtime is removed, preserve required remote state history and package
evidence privately. Inspect both project S3 buckets, including versions and delete
markers. **Both have `force_destroy=true`; approving bootstrap removal can purge
all their objects/versions. Versioning does not protect against that apply.**
Do not remove the buckets/state while either runtime stack remains managed.

**Local terminal, still at the infrastructure root with your original bootstrap
state and owner credentials:** generate a separate final plan:

```bash
terraform -chdir=bootstrap plan -destroy -out=final-bootstrap-destroy.tfplan
terraform -chdir=bootstrap show -no-color final-bootstrap-destroy.tfplan
```

Review scope: project buckets/configuration, optional budget, GitHub publisher/
deployer roles and optional destroy role/policies. **Do not delete the shared
OIDC provider:** this configuration reads it as data, not an owned resource.
If scope differs or state is missing, stop. **Only after separate approval of
the bucket purge and bootstrap removal**, apply the saved plan:

```bash
terraform -chdir=bootstrap apply final-bootstrap-destroy.tfplan
terraform -chdir=bootstrap state list
```

No managed addresses should remain in bootstrap state. Retain any required local
state/plan evidence securely; do not commit it. This owner-operated step is not
part of the GitHub runtime workflow and does not run automatically.

## 7. Revoke temporary access and check residual costs

In each application's **Settings → Secrets and variables → Actions → Secrets**,
remove this lab's `INFRA_WORKFLOW_TOKEN`. In your GitHub account **Settings →
Developer settings → Personal access tokens → Fine-grained tokens**, revoke the
specific temporary token used for this lab. Do not revoke unrelated tokens.

Remove obsolete lab-only repository variables/secrets after preserving approved
reproduction information privately; do not copy tokens into evidence. Leave
delivery workflows disabled and the freeze in place after closure. CI may remain
enabled for code checks; a push must not recreate runtime.

Inspect AWS inventory and Billing/Cost Explorer for residual project resources
and charges. Billing data can lag; a zero balance is not an immediate deletion
test and prior usage can still be charged. Record actual removed resources,
failures/recovery, remaining items and verification time in your own closeout
notes. Source repositories and diagrams are not deleted by this procedure.

## Validation status

The author's AWS lab was removed on **2026-10-30** after explicit owner approvals:

- Runtime teardown completed in simulator → core order. The
  [successful final runtime run](https://github.com/MarcondesOliveira/async-transaction-infrastructure/actions/runs/41084698506)
  confirmed both stacks had no remaining managed resources.
- Earlier attempts partially deleted resources before encountering provider
  cleanup permission denials. Recovery kept delivery frozen, inspected the
  remaining state/resources, and applied separately reviewed, minimal corrections
  to the teardown role for polling/prechecks, log delivery and REST stage reset.
  Fresh previews and explicit approvals preceded destructive resumptions; there
  was no automatic retry, rollback or recreation of the deleted application.
- All S3 object versions of deployment packages and remote states, plus
  delete-marker metadata, were copied and verified privately before bootstrap
  removal. Those files contain private infrastructure information and are not
  repository assets or application-table/log backups.
- A separately reviewed owner-operated plan removed **20 bootstrap resources**:
  both buckets and their contents/configuration, three GitHub roles, seven inline
  policies and the project budget. The local bootstrap state ended without managed
  instances. The shared GitHub OIDC provider was preserved.
- Post-removal AWS reads confirmed no matching project APIs, Lambda functions or
  mappings, Pipes, DynamoDB tables, SQS queues, SNS topics, log groups, alarms or
  runtime roles in the reviewed prefixes/region. The two buckets, bootstrap roles
  and budget were also confirmed absent. Verification completed around
  **2026-10-30 16:36 UTC**; this is not an account-wide inventory or billing audit.
- Delivery workflows remain disabled and the freeze remains enabled. The four
  application `INFRA_WORKFLOW_TOKEN` secrets were removed and their absence
  verified. Account-level token revocation and delayed billing remain separate
  owner checks, not consequences proven by successful Terraform deletion.

These results describe the author's lab, not a second-account reproduction or a
production certification. A preview alone still does not prove deletion or
authorize it: visitors must review and explicitly approve their own IAM changes,
runtime teardown and final bucket purge. The procedure above remains applicable
to a newly provisioned reproduction, not to the already removed deployment.

## GitHub interface and CLI references

- [Run a workflow manually](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [Disable and enable workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows)
- [GitHub CLI: workflow run and inputs](https://cli.github.com/manual/gh_workflow_run)
- [CloudWatch Logs permission-only actions and resource scopes](https://docs.aws.amazon.com/service-authorization/latest/reference/list_logs.html)
- [HTTP API logging permissions](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-logging.html)
