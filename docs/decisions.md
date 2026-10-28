# Infrastructure decisions

## Serverless API

API Gateway HTTP API and Lambda preserve the asynchronous service boundary without the fixed cost or operational overhead of a Kubernetes cluster.

## Terraform state locking

The S3 backend uses native lock files. A DynamoDB lock table is not created because DynamoDB-based backend locking is deprecated.

## Existing GitHub OIDC provider

The target AWS account already contains the GitHub Actions OIDC provider. Terraform reads it as data and manages only project-specific roles, preventing ownership conflicts with other repositories.

## Separate GitHub roles

Application repositories receive an artifact publisher role. The infrastructure repository receives a deployment role. This prevents application pipelines from changing infrastructure.

## Separate simulator state

The external processor simulator is hosted temporarily in the same AWS account but remains a separate stack, state and deployment boundary.

## Artifact placeholders

The core variables contain an intentionally invalid deployment location for planning before CI/CD exists. No apply may use the `not-published` key. A real immutable ZIP key and its Base64 SHA-256 are required in the next stage.

## Safe pre-simulator request pipeline

The Request Handler is deployed before the external simulator and callback endpoint.
Reserved `.invalid` HTTPS domains prevent accidental calls to real services while
allowing timeout, retry and DLQ behavior to be validated. Later stages replace both
URLs through Terraform variables.

## Request queue retry boundary

Processing Requests uses a 90-second visibility timeout for a 15-second Lambda and
moves a message to Failed Requests after three receives. Partial batch failure
reporting prevents successful messages in the same batch from being retried.
