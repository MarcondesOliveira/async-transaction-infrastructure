# Stage 12 security review — 2026-10-29

This is a dated audit record: findings and intermediate validation limits below
refer to that stage. Subsequent automatic OIDC delivery and end-to-end smoke were
validated in stage 13; see [current delivery](continuous-delivery.md) and the
[project overview](../README.md). The later optional teardown role is prepared
separately, not evidence that destructive execution has been validated.

Status: initial audit completed; owner-approved IAM corrections deployed and
verified with live policy reads, no-drift plans and a successful manual API
regression. No application source was changed by these corrections. This is
not a production-security certification or a claim of zero risk.

## Scope and checks

- Reviewed Terraform bootstrap, core and simulator IAM policies, application
  configuration and Git exclusion rules. Compared the deploy role trust, attached
  managed policy and inline IAM-management scope against AWS with read-only calls.
- Trivy 0.75.0 scanned source/configuration with secret and misconfiguration
  scanners. The check bundle was updated on the audit date; raw results remain
  outside the repository. Generated build files, `.git`, `.terraform`, real tfvars,
  saved plans and state were excluded. No Git-history or deployed-log secret scan
  was performed. Trivy's cached vulnerability database was not used to claim
  dependency freshness; package auditing used the NuGet advisory feed separately.
- NuGet checks included direct and transitive dependencies in all projects/tests
  of the four application repositories. No vulnerable packages were returned on
  this date. This result does not cover vulnerabilities absent from that feed,
  operating-system images or AWS-managed runtime patch status.
- The simulator's first package check failed with an internal CLR error. Repeating
  without restore succeeded. No source/package versions were changed.
- AWS Access Analyzer ValidatePolicy checked a synthetic, non-sensitive copy of
  the API action list. This did not create or attach an IAM policy or analyzer.

## Secret/configuration results

Trivy reported **0 secret findings in the scanned files**. Real tfvars, state and
plans are covered by Git ignore rules; no matching real tfvars/state/plan files
were found tracked in the infrastructure repository. Applications use the AWS
credential chain/execution roles rather than embedded AWS access keys.

One exception to the documented configuration boundary was found and corrected:
`stacks/core/backend.hcl` was tracked even though the README describes it as local
and ignored. Its actual contents are bucket/state-path/region/locking settings,
not credentials. Keep the real file local, exclude it from future Git tracking
and retain only the existing illustrative backend example in the repository.
Do not delete the local backend configuration or Terraform state to fix tracking.
Account identifiers and resource names are deployment metadata, not access keys;
their presence alone is not evidence of credential compromise.

## Priority findings

### 1. Deployment role trust and privilege — correction required before CI/CD

The deployed role accepts infrastructure repository subjects for main, pull
requests and an environment name. It has `PowerUserAccess` attached. Its inline
policy allows role-policy/trust management and PassRole on a project-prefix
wildcard that also matches the deploy role itself.

This is too broad for a least-privilege CI identity. In particular, policy mutation
on a matching privileged role is an escalation path; a name prefix alone is not
a permissions boundary. No escalation attempt was executed. A job still needs a
valid matching OIDC token; the trust condition does not mean anonymous users can
directly assume the role.

Proposed correction: restrict the deployment trust to the intended protected
deployment context, exclude PR deployment credentials, and constrain deployment
permissions/self-management before enabling workflows. Do not claim that merely
removing the PR subject or limiting role names eliminates privilege escalation.
If CI must create runtime roles, enforce an appropriate permissions boundary or
separate privileged provisioning from routine deployment. Verify the actual OIDC
subject format and environment protection in Stage 13 rather than assuming them.

### 2. API DynamoDB action list — invalid/unnecessary entries

AWS ValidatePolicy returned:

```text
ERROR / INVALID_ACTION
The action dynamodb:TransactWriteItems does not exist.
```

TransactWriteItems is an API operation; IAM authorizes its constituent actions.
The current repository implementation uses GetItem and transactional Put actions,
so existing `dynamodb:GetItem` and `dynamodb:PutItem` cover those operations on the
project table. `dynamodb:DescribeTable` is not called by this implementation.
Proposed correction: remove the invalid action and unused DescribeTable grant,
then validate the resulting policy and test real POST/GET after reviewed apply.
The invalid entry is not itself a credential leak or a broader privilege grant.

### 3. Real backend file tracked — repository hygiene correction

Untrack the real backend file without deleting its local copy, extend ignore rules
consistently across stacks, preserve the example, and verify the staged changes
before the owner's manual commit. No history rewrite or key rotation is justified
by the observed backend contents alone.

## Runtime permission boundaries already present

The runtime policies target specific project log groups, tables, queues and
Streams, with separate identities for API, Request Handler, Callback Handler,
Pipe, callback gateway and simulator functions. The simulator does not receive
access to the main transaction table. Callback publication/consumption is scoped
to the project SNS/SQS resources. These observations are not an exhaustive IAM
simulation or live proof that every unnecessary action has been removed.

## Trivy infrastructure findings — triage, not silent suppression

Trivy reported **25 findings: 3 HIGH, 3 MEDIUM, 19 LOW**. No ignore/suppression file
was added. Scanner severity is retained, even when a recommendation is beyond the
temporary lab scope.

| Check | Count | Finding and proposed lab disposition |
| --- | ---: | --- |
| AWS-0132 | 2 | S3 uses AES256 server-side encryption, not customer-managed KMS keys. Not plaintext storage. Retain the simpler encryption for this temporary lab; do not add paid keys without approval. |
| AWS-0095 | 1 | Transaction Results SNS lacks at-rest topic encryption. Real limitation; use synthetic demo data only. A KMS change also needs service-integration permission review, not a blind toggle. |
| AWS-0001 | 1 | Callback REST API lacks access logging. Existing regional logging-role dependency was deliberately deferred; do not modify shared account settings implicitly. Lambda logs are not a substitute for callback gateway access logs. |
| AWS-0024 | 2 | DynamoDB point-in-time recovery disabled. Temporary disposable demo data; do not claim production recovery guarantees or enable additional paid retention without approval. |
| AWS-0089 | 2 | S3 access logging absent. Proposed production enhancement, not an automatic extra logging bucket. |
| AWS-0003 / AWS-0066 | 6 | X-Ray absent on REST stage/five Lambdas. Correlation logs are present; distributed tracing is a future enhancement. |
| AWS-0017 / AWS-0025 | 9 | Log groups/tables do not use customer-managed KMS keys. Existing service encryption is distinct from customer key control. |
| AWS-0004 | 1 | Callback method has no client authorization. HTTPS-only demonstration scope is intentional; no claim of caller authentication. |
| AWS-0190 | 1 | REST response caching disabled. Do not enable caching for callback POST just to clear this generic check. |

These are proposed scoped dispositions for the review, not a blanket acceptance of
all risks. Existing public demonstration endpoints and caller-supplied simulator
callback destinations are not production-safe authentication/allowlisting. Keep
callers and destinations controlled, use synthetic data and destroy the lab after
demonstration. The agreed HTTPS scope is unchanged; no HMAC/authentication scheme
was added or removed in this audit.

## Owner-approved corrections — applied 2026-10-29

The owner approved separating privileged IAM administration from routine deploys.
The applied changes implement that simpler boundary instead of adding IAM
creation privileges and new permissions-boundary machinery to the lab:

- OIDC deployment trust accepts the exact main-branch subject only (audience
  sts.amazonaws.com); PR/environment-only subjects are removed.
- The PowerUserAccess attachment is removed. A new inline deployment policy
  names the project services/actions/resources. No IAM mutation or STS AssumeRole
  action is granted. Read-only ListEventSourceMappings/DescribeLogGroups require
  resource `*` and are region-constrained; mutation is scoped more narrowly.
- IAM read and PassRole reference seven literal runtime role ARNs, excluding both
  GitHub roles. PassRole is additionally limited to Lambda, Pipes and API Gateway.
  The existing inline policy's legacy name is retained to avoid replacement churn,
  but its former IAM-management writes are removed.
- State object writes cover only core/simulator state and lock keys. Artifact
  access for the routine deployer remains read-only; publication is a separate role.
- Existing API Gateway IDs and event-source mapping UUIDs are literal local inputs,
  validated to exclude wildcard/path injection, with empty defaults in the public
  example. Real IDs are only in ignored tfvars. New APIs/mappings, IAM provisioning,
  bootstrap changes and complete teardown remain owner-operated. If resources are
  replaced, their identifiers must be refreshed before routine CI can manage them.
- API runtime policy keeps GetItem/PutItem on its table, removing the invalid
  TransactWriteItems action and unused DescribeTable.
- `backend.hcl` is ignored for all stacks. `git rm --cached` removed only the core
  backend from the index; its actual local file was verified still present, and the
  existing illustrative example remains tracked. The index deletion must be included
  in the owner's manual commit; this is not deletion of remote state or Git history.

The artifact-publisher policy is unchanged by these corrections. Application
workflows still share that publishing identity, so per-repository artifact isolation
and enforcement of immutable writes are not claimed here. Secrets detection was
not a Git-history audit, and accepted lab limitations from the triage still apply.

### Validation evidence

- Terraform configuration validation passed for bootstrap and core.
- Formatting and staged/unstaged diff checks passed. A new Trivy secret scan of
  the corrected infrastructure source returned zero findings (same generated/local
  file exclusions as the initial scan); raw scan output stays outside Git.
- AWS Access Analyzer ValidatePolicy returned no findings for all three candidate
  deployment identity policies. Their combined JSON size is 6,605 bytes, below the
  role's aggregate inline-policy limit.
- Before deployment, IAM SimulateCustomPolicy evaluated the **draft policies**,
  not a live role session. All 13 per-resource assertions passed: eight denied IAM mutations
  (four actions x own/runtime role), allowed project function code update, denied
  out-of-project update, allowed runtime PassRole to Lambda, denied passing the
  deploy role, and denied runtime PassRole to EC2. Aggregate action results alone
  were not used to infer an individual resource's authorization.
- Trust JSON was inspected for exact subject/audience matching. OIDC role
  assumption, all provider API calls, new-resource creation, and complete CI
  deployments have not been tested and must not be inferred from these simulations.

### Approved deployment and verification

1. Bootstrap: **1 add, 3 changes, 1 removal**. The addition is a project-service
   inline policy; changes narrow trust, role access and state access. The removal
   detaches PowerUserAccess only; no runtime role, bucket, budget or application is
   deleted. Apply with the owner's existing privileged identity, not the CI role.
2. Core: **0 adds, 1 change, 0 removals**, editing only the API runtime inline policy.
3. Verify both stacks' drift and actual policies after explicit approval/apply.
   Then have the owner POST a new transaction through Bruno/Swagger and confirm
   final state/GET. This validates the API's real transactional permissions, not CI
   role assumption or every infrastructure permission.

Both saved plans were applied successfully, in the order above, using the owner's
existing IAM identity rather than the CI role. Bootstrap completed with **1 added,
3 changed, 1 destroyed** (only the managed-policy attachment); core completed with
**0 added, 1 changed, 0 destroyed**. Both post-apply plans returned exit code 0 and
reported no changes. Live IAM inspection confirmed no attached managed policies
on the deploy role, exact main-branch/audience trust, the three expected inline
policies, read/PassRole rather than IAM mutation, and only GetItem/PutItem plus log
writes on the API runtime role. Manual POST/GET regression passed for transaction
`e3c03b53-6d75-40cd-8de7-b041caa72218`: API logs confirmed Create/202 and Get/200,
callback logs confirmed CallbackHandled/Applied, and GET returned SUCCEEDED/APPROVED.
This validates the application path after the runtime policy change, not CI access.

No paid security service, custom alarm, KMS key or production feature was enabled.
The IAM least-privilege review and its application regression are complete for
this increment; remaining configuration/scope decisions are not automatically
closed by that result. The subsequent [lab operations review](lab-operations.md)
records configuration handling, accepted resilience limits and DLQ recovery.

## Primary references

- [DynamoDB transactions and IAM](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis-iam.html)
- [DynamoDB operation-to-action mapping](https://docs.aws.amazon.com/service-authorization/latest/reference/list_dynamodb.html)
- [GitHub OIDC subjects](https://docs.github.com/en/actions/reference/security/oidc)
- [PowerUserAccess](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/PowerUserAccess.html)
- [IAM permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)
