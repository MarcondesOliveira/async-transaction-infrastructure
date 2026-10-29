# Async Transaction Infrastructure

For this temporary portfolio lab, operational inspection uses structured CloudWatch
logs, native service metrics and existing DLQs. Custom alarm metrics and operational
SNS email notifications are intentionally deferred to a future production-oriented
extension; no automated incident detection is claimed for the current lab.

The [Stage 12 security review](docs/security-review.md) records scanner results,
IAM/configuration findings and the limits of this temporary lab. Open findings
must not be mistaken for production security approval.

The [lab operations guide](docs/lab-operations.md) records configuration handling,
timeout/retention tradeoffs and the manual inspection/recovery procedure for each
failure queue. Stage 12 adds no custom alarms or production recovery platform.

Terraform infrastructure for the Async Transaction Processing portfolio project.

This repository owns AWS resources only. Application source code is built in independent repositories and supplied as immutable ZIP artifacts.

## Current scope

The current stage defines:

- encrypted and versioned S3 remote state;
- native S3 state locking;
- encrypted S3 deployment artifacts with lifecycle cleanup;
- GitHub Actions authentication through the existing AWS OIDC provider;
- separate roles for Terraform deployment and artifact publication;
- optional USD 5 monthly AWS Budget with email alerts;
- DynamoDB table with TTL and Streams;
- Transaction API Lambda using managed `dotnet10` on `arm64`;
- API Gateway HTTP API;
- CloudWatch log groups and access logs;
- least-privilege runtime permissions for the Transaction API.
- encrypted Processing Requests and Failed Requests SQS queues with redrive;
- EventBridge Pipes routing only `INSERT + PENDING` transaction records;
- Request Handler Lambda with partial SQS batch failure reporting;
- least-privilege runtime roles for the Request Handler and EventBridge Pipes.
- independent external simulator stack with an HTTP API, two Lambdas, its own DynamoDB Stream table and a callback failure destination.
- regional REST callback API integrated directly with SNS, raw delivery to Processing Results, Failed Results DLQ and the Callback Handler Lambda.

No AWS resource is created by cloning or validating this repository. Creation requires an explicit `terraform apply`.

## Delivery automation — in progress

All four application repositories have validated GitHub Actions CI, versioned
ARM64 Lambda packages and manually dispatched S3 publication through OIDC.
Publication checks the approved CI run, package identity/checksums and conditional
S3 writes. It does not update any Lambda or invoke Terraform.

The required final path is a service push to main followed by CI, packaging,
artifact publication, infrastructure plan/deploy and smoke verification, without
local deployment commands. Infrastructure changes must use its own pipeline.
That full chain is not implemented or validated yet; existing role definitions
and successful S3 publication alone do not demonstrate continuous deployment.

Pipeline work resumes with infrastructure OIDC and a controlled central deployment
workflow. Publication and deployment permissions remain separate; concurrent
service changes must be serialized per Terraform stack without losing another
service's deployed version. PR validation must not receive deployment credentials.
Secrets stay outside source. Privileged bootstrap/IAM work remains owner-operated
unless an explicit reviewed permission change is approved.

See [continuous delivery implementation notes](docs/continuous-delivery.md) for
the cross-repository token setup, deployment rules and current prerequisites.

Destroy is a separate, explicitly confirmed workflow, never a push-triggered job.
Do not perform teardown until demonstration/evidence is complete and authorized.

## Repository structure

```text
bootstrap/
  Creates remote state, artifact storage, OIDC roles and the cost budget.
stacks/core/
  Creates the Transaction API and asynchronous request/result pipelines.
stacks/external-simulator/
  Hosts the independent simulator with a separate Terraform state.
modules/
  Receives reusable components only after actual repetition exists.
policies/
  Reserved for policy checks introduced in the security stage.
```

## Region and cost posture

The temporary development environment uses `us-east-1`. Serverless, on-demand resources were selected to avoid fixed compute cost:

- API Gateway HTTP API;
- Lambda;
- DynamoDB on-demand;
- short CloudWatch Logs retention;
- no VPC, NAT Gateway, EKS or provisioned capacity.

The infrastructure is designed to be destroyed after the portfolio demonstration.

## Prerequisites

- Terraform 1.14 or newer;
- AWS CLI authenticated to the intended account;
- permission to manage S3, IAM roles, AWS Budgets and the serverless services in scope;
- the GitHub OIDC provider `token.actions.githubusercontent.com` already registered in the AWS account.

No access key or AWS account identifier is stored in this repository.

## 1. Validate the bootstrap

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap fmt -check
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap plan
```

Before the first apply, copy `bootstrap/terraform.tfvars.example` to a non-versioned `terraform.tfvars` and set `budget_alert_email`. Leaving the value null intentionally skips the budget and its alerts.

## 2. Apply the bootstrap

Run the bootstrap only after its plan has been reviewed:

```bash
terraform -chdir=bootstrap apply
```

The outputs provide the state bucket, artifact bucket and GitHub Actions role ARNs.

## 3. Configure the core backend

After the bootstrap exists, copy the example and replace the bucket name with the `terraform_state_bucket` output:

```bash
cp stacks/core/backend.hcl.example stacks/core/backend.hcl
terraform -chdir=stacks/core init -backend-config=backend.hcl
```

The ignored `backend.hcl` contains no credentials. Authentication uses the AWS credential chain locally and OIDC in GitHub Actions.

## 4. Supply the application artifacts

The Transaction API repository will publish an immutable ZIP with this key format:

```text
async-transaction-api/<git-sha>/async-transaction-api.zip
```

The Request Handler uses the equivalent immutable key:

```text
async-transaction-request-handler/<git-sha>/async-transaction-request-handler.zip
```

Copy `stacks/core/terraform.tfvars.example` to `stacks/core/terraform.tfvars` and replace both artifact keys and Base64 SHA-256 values before any apply. The defaults in `variables.tf` are deliberate non-deployable planning placeholders.

Until the simulator and callback are deployed, the Request Handler uses reserved
`.invalid` HTTPS domains. This intentionally produces transient failures so the
SQS retry and DLQ behavior can be demonstrated without contacting a real system.

## 5. Plan the core stack

```bash
terraform -chdir=stacks/core fmt -check
terraform -chdir=stacks/core validate
terraform -chdir=stacks/core plan -out=core.tfplan
```

Review the plan before applying. The first core apply belongs to the next project stage.

## Security boundaries

- Application workflows from `main` may publish artifacts only.
- The applied Stage 12 security change restricts infrastructure OIDC trust to `main`; PR and environment-only subjects are excluded. Verify the repository's actual OIDC subject format before enabling Stage 13 workflows.
- The routine Terraform role uses project-service permissions instead of `PowerUserAccess`. It can read/use seven existing runtime roles, but cannot create/edit IAM roles or manage its own permissions. Bootstrap and IAM changes remain owner-operated.
- Existing API Gateway IDs and event-source mapping UUIDs are supplied in ignored bootstrap tfvars. Initial provisioning, replacement APIs/mappings and complete teardown require the owner; update these identifiers after replacement. Routine CI is not an administrator or a bootstrap identity.
- Runtime access is separate: the Transaction API Lambda can write logs and read/create records only in its DynamoDB table.
- The Request Handler can consume only Processing Requests and conditionally update only the project table.
- EventBridge Pipes can read only the transaction Stream and send only to Processing Requests.
- The simulator API can read/create only simulator operations; its worker can read only that Stream, write its own logs and send failure metadata to its own queue.
- OIDC removes the need for permanent AWS keys in GitHub.

These security corrections were deployed on 2026-10-29. Both stacks' post-apply
plans showed no differences, and live IAM policies were checked. A manual API
POST/GET regression passed with a final SUCCEEDED result and an Applied callback.
The security review records validation scope
and remaining limitations; simulated allow/deny results do not prove real
infrastructure OIDC/deployment. That integration is required but not yet validated;
application artifact publishing OIDC was validated separately in all four
application repositories.

## Destruction

The product stack must be destroyed before the bootstrap because its state and artifacts depend on bootstrap buckets:

```bash
terraform -chdir=stacks/external-simulator destroy
terraform -chdir=stacks/core destroy
terraform -chdir=bootstrap destroy
```

The final project checklist requires a separate AWS inventory and cost check after destruction.

See [the simulator stack guide](stacks/external-simulator/README.md) for backend setup, artifact configuration, review steps and manual tests. Simulator deployment and core endpoint wiring are separate reviewed changes.

See [the callback pipeline guide](docs/callback-pipeline.md) for the REST/SNS choice, callback acknowledgement, permissions, logging boundary and manual test sequence. Callback Handler deployment requires its own immutable artifact key/hash.
