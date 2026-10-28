# Stage 5 — First Transaction API deployment

Date: 2026-10-28  
Region: `us-east-1`  
Environment: `dev`

## Deployed artifact

- Application commit: `d7d41ae4d8bf28dbee8391d779afba2e00eb3f3f`
- S3 key: `async-transaction-api/d7d41ae4d8bf28dbee8391d779afba2e00eb3f3f/async-transaction-api.zip`
- ZIP SHA-256: `d74b75121281b0d53999bebe162e2d10c103d31fdc7e920f970fd6a2067cb049`
- Lambda runtime: managed `dotnet10`
- Architecture: `arm64`

## Public endpoint

`https://8st0dstrp8.execute-api.us-east-1.amazonaws.com`

## Validation results

| Check | Result |
|---|---|
| `GET /health` | `200 OK` |
| First valid `POST /transactions` | `202 Accepted` |
| `GET /transactions/{transactionId}` | `200 OK`, transaction returned as `PENDING` |
| Same idempotency key and body | `202 Accepted`, same transaction returned |
| Same idempotency key with different body | `409 Conflict`, `IDEMPOTENCY_KEY_REUSED` |
| DynamoDB persistence | Transaction item found with consistent read |
| DynamoDB Stream | Enabled with `NEW_IMAGE` |
| Stream transaction event | `INSERT`, `entityType=TRANSACTION`, `status=PENDING` |
| Stream idempotency event | `INSERT`, `entityType=IDEMPOTENCY` |
| API Gateway access logs | Requests and response codes recorded |
| Terraform drift check | No changes |

Validated transaction: `19660176-b74f-4644-a60e-bb26ccfd6abf`.

## Deployment correction

The first write test exposed a missing `dynamodb:PutItem` permission for the
`Put` operations inside `TransactWriteItems`. The runtime policy was corrected
on the same project table only. The deployment was retested after IAM
propagation and all checks above passed.

## Scope boundary

Only the synchronous Transaction API path is active. No EventBridge Pipe, SQS
request queue, request handler, external processor, callback endpoint, SNS or
result queue has been deployed yet.
