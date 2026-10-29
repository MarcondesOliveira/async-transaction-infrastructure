# Stage 13 — OIDC and controlled artifact publication

## API trust prerequisite — 2026-10-29

Read-only GitHub inspection of the API repository's
`actions/oidc/customization/sub` endpoint returned `use_default: true`,
`use_immutable_subject: true`, and an immutable `sub_claim_prefix`.
Before correction, the live AWS artifact-publisher trust listed the legacy
name-only subject. Those strings did not match. No failed STS attempt or token dump was needed to
identify the mismatch; actual runner role assumption remains untested.

Terraform now accepts verified immutable application prefixes through
`github_application_oidc_subject_prefixes`. Real owner/repository IDs are in
ignored bootstrap tfvars only; the tracked example contains an empty map and
synthetic format guidance. Validation rejects unknown application repositories,
owner/name mismatches, branch suffixes and wildcards. The main-branch suffix is
always constructed in Terraform, not supplied by a workflow.

The API's verified prefix replaces its old subject; it is not added alongside it.
Audience `sts.amazonaws.com`, main-only restriction and all S3 permission actions
remain unchanged. Other repositories retain their current trust entries pending
their own inspection; their OIDC operation is not claimed here. The infrastructure
deployer trust is not changed by this API publishing increment.

Terraform fmt/validate and diff checks passed. The saved bootstrap plan has
**0 additions, 1 in-place change, 0 deletions**: only the artifact-publisher role's
API trust subject. After explicit owner approval, the saved plan was applied:
**0 added, 1 changed, 0 destroyed**. A live IAM read confirmed replacement of
the API subject, with the same audience/main restriction and other repository
entries preserved. The post-apply plan returned exit code 0 with no changes.
No GitHub variables/workflows were changed and no S3 object was uploaded.
The owner's infrastructure commit/push is pending. Next: prepare manual API
artifact publication with conditional S3 writes and verify the real OIDC workflow;
trust inspection alone does not prove successful runner role assumption.

The current publisher role is shared across application repositories and permits
GetObject/PutObject across the artifact bucket. This change does not introduce
per-repository prefix isolation or enforce immutability at bucket-policy level.
The planned publication workflow must explicitly use conditional writes and must
not be described as a new IAM isolation boundary.

Reference: [GitHub OIDC immutable subject format](https://docs.github.com/en/actions/reference/security/oidc).

## Request Handler prerequisite applied; workflow prepared — 2026-10-29

Read-only inspection confirmed that the Request Handler also uses an immutable
subject prefix. Its verified value was added only to ignored bootstrap tfvars;
no owner/repository/account IDs were added to tracked source. The saved plan
`stage13-request-oidc.tfplan` has **0 additions, 1 in-place change, 0 deletions**:
only its legacy trust subject is replaced. API trust, audience, main-only scope,
S3 permissions and other repository entries are unchanged. After explicit owner
approval, the saved plan was applied: **0 added, 1 changed, 0 destroyed**. Live IAM
inspection confirmed the Request Handler's immutable subject and preserved the
API trust, audience and main restriction. The post-apply plan returned exit code
0 with no changes. No real runner OIDC authentication or S3 upload has been
performed for this service.

The Request Handler publication workflow/script are prepared locally using the
API pattern, with the Node.js 24 AWS action pinned to v6.3.0's commit and no rg
dependency. Four non-secret deployment variables were configured in its GitHub
repository, with values kept outside source. Its actual CI artifact passed local
verification; an isolated AWS substitute validated three conditional puts and
final head verification, plus rejection of existing objects and wrong commits.
These tests do not prove real STS/S3 access. Workflow and documentation commits
remain owner-operated; trust apply is complete, while workflow push and first
manual publication remain pending.
