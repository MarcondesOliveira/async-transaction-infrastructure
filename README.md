# Async Transaction Infrastructure

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
- Infrastructure workflows may assume the Terraform role from `main`, pull requests or the protected `dev` environment.
- The Terraform role uses AWS `PowerUserAccess` plus IAM permissions limited to project-prefixed roles.
- Runtime access is separate: the Transaction API Lambda can write logs and read/create records only in its DynamoDB table.
- The Request Handler can consume only Processing Requests and conditionally update only the project table.
- EventBridge Pipes can read only the transaction Stream and send only to Processing Requests.
- The simulator API can read/create only simulator operations; its worker can read only that Stream, write its own logs and send failure metadata to its own queue.
- OIDC removes the need for permanent AWS keys in GitHub.

The deployment role will receive a further least-privilege review in the security stage.

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
