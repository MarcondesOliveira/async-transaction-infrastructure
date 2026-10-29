# Continuous delivery — implementation in progress

## Required outcome

A push to main in any service must validate, test, package, publish the exact ZIP
and trigger the infrastructure deployment pipeline. Deployment must apply the
matching S3 key/hash through Terraform, verify the affected Lambda and run an
appropriate smoke check. No local command should be needed to finish routine
delivery. PRs validate without deployment credentials. Infrastructure changes
use the infrastructure repository pipeline. Destroy remains separately confirmed.

This chain is not complete yet. Existing CI/package jobs and manual publication
workflows are already validated; publication alone is not deployment.

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

References: [GITHUB_TOKEN and additional authentication](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token),
[workflow dispatch permission](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event).
