# Stage 7 — Asynchronous request pipeline

Date: `2026-10-28`  
Region: `us-east-1`  
Environment: `dev`

## Deployed artifact

- Application repository: `async-transaction-request-handler`
- Application commit: `03e8d3068271c3d36a2a47f5ce420000cbb1c278`
- S3 key: `async-transaction-request-handler/03e8d3068271c3d36a2a47f5ce420000cbb1c278/async-transaction-request-handler.zip`
- ZIP SHA-256: `3f5d816488040d414320f7e57f0a2394fb0ecd2a8ac6c79330a8dbde72d9f311`
- Lambda source hash: `P12BZIgEDUFDIPflfwojlPsOzSqKxseTMKjb3nLZ8xE=`
- Runtime: managed `dotnet10`
- Architecture: `arm64`

## Deployed pipeline

- EventBridge Pipe reads the DynamoDB Stream from `LATEST`.
- The Pipe filters only `INSERT` records whose new image is a `TRANSACTION` in `PENDING` state.
- The Pipe transforms the DynamoDB record into the version 1 `TransactionRequested` contract.
- Processing Requests is encrypted with SQS-managed encryption.
- Failed Requests retains dead-letter messages for 14 days.
- Processing Requests uses a 90-second visibility timeout and redrives after three receives.
- The Request Handler reports partial SQS batch failures.
- The Request Handler can consume only Processing Requests and update only the project table.
- The Pipe can read only the transaction Stream and send only to Processing Requests.

## Manual validation

Validated transaction: `1ebaaca6-b4c0-4cc2-bfed-061f8642a6e4`  
Correlation ID: `77777777-7777-4777-8777-777777777777`  
SQS message ID: `17d08f4f-6383-4f5e-b111-985cbdca4bb1`

The external processor intentionally used the reserved URL
`https://processor.invalid/`. This exercised the transient failure path without
contacting a real external service.

| Check | Result |
| --- | --- |
| Transaction API | `202 Accepted`, initial status `PENDING` |
| DynamoDB Stream to Pipe | event transformed and delivered to Processing Requests |
| Request Handler attempt 1 | transient DNS/HTTP failure at `20:43:52 UTC` |
| Request Handler attempt 2 | same message retried at `20:45:21 UTC` |
| Request Handler attempt 3 | same message retried at `20:46:51 UTC` |
| Visibility interval | approximately 90 seconds between attempts |
| Transaction state | remained `PENDING`, as required for transient failure |
| Processing Requests | empty after retry exhaustion |
| Failed Requests | exactly one visible message |
| DLQ payload | version 1 `TransactionRequested` for the validated transaction |
| Additional Lambda invocation | none after the third attempt |
| Terraform drift check | no changes |

The DLQ receive count became four only because the final evidence inspection used
`ReceiveMessage` with a zero-second visibility timeout. CloudWatch logs confirm that
the Lambda itself ran exactly three times.

## Scope boundary

The successful processor submission path is intentionally deferred. The simulator
and callback endpoints do not exist yet, so reserved `.invalid` URLs remain configured
until their respective implementation stages.
