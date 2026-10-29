# Stage 12 — Observability, security and resilience

Status: in progress. The following evidence covers only the Request Handler
observability increment, not completion of the entire stage.

## Request Handler package and reviewed plan

- Owner-pushed application commit, confirmed against GitHub `main`:
  `6501839bd2356138534e9b3b38b7d27df2f2c8e6`.
- Framework-dependent Release publish for `net10.0` / `linux-arm64` succeeded.
- S3 key:
  `async-transaction-request-handler/6501839bd2356138534e9b3b38b7d27df2f2c8e6/async-transaction-request-handler.zip`.
- ZIP SHA-256:
  `d91d1617138316aea2fc4fc2aa3cfefc18735017ca1b0f4a109c2dc8cba36a72`.
- Lambda Base64 checksum:
  `2R0WFxODFq6i/E/Cqjz+/BhzUBfKGw9KEJwtyMujanI=`.
- S3 upload used conditional creation (`If-None-Match: *`), AES256 encryption
  and SHA-256 checksum validation; S3 returned the matching checksum.
- `terraform fmt -check` and `terraform validate` passed.
- Saved core plan: **0 to add, 1 to change, 0 to destroy**.

The plan updates only the existing Request Handler Lambda, replacing its package
and enabling native JSON logging at application/system `INFO` level in its existing
log group. IAM, API endpoints, queues, timeouts and other functions are unchanged.

Named `ILambdaLogger` parameters become searchable top-level JSON fields when
the runtime JSON logging format is enabled. See the
[AWS .NET logging documentation](https://docs.aws.amazon.com/lambda/latest/dg/csharp-logging.html).

Application validation passed with zero build warnings/errors and 13 tests.
Tests cover correlated accepted/rejected outcomes, per-message failures, malformed
JSON, batch continuation and exclusion of payload data from logs.

## Pending deployment and manual validation

The owner approved the saved plan. Apply completed successfully: **0 added,
1 changed, 0 destroyed**. The Request Handler is `Active`, its last update is
`Successful`, its code checksum matches the artifact above, and its existing log
group is configured for JSON with application/system `INFO` levels. A subsequent
Terraform plan exited with code 0 and reported no changes.

Runtime/manual validation remains pending:

1. Deployment status and checksum/logging configuration: confirmed as described above.
2. Ask the owner to create a transaction using the Transaction API in Bruno or
   Swagger with a new idempotency key and correlation ID.
3. Query `/aws/lambda/async-transaction-processing-dev-request-handler` using the
   returned transaction ID. Confirm `RequestHandled`, `SubmissionAccepted`,
   `MessageId`, `EventId`, `TransactionId` and `CorrelationId` in the JSON record.
4. Confirm the final transaction state through `GET /transactions/{transactionId}`.
5. If exercising a controlled timeout, inspect `RequestProcessingFailed`, its
   identifiers and exception types across attempts; do not redrive old DLQ
   messages or delete evidence as part of this check.
6. Run a post-apply Terraform plan to check for drift.

Other Stage 12 items, including alarm coverage, other services' logs, permissions,
configuration review, security scans and DLQ recovery documentation, remain open.

## Manual success validation — Request Handler logs

The owner created transaction `81b9e490-98a2-4d08-8f69-a1309806a207` through the
Transaction API at `2026-10-29T01:01:59.4235652Z`, with correlation ID
`12345678-1234-4234-8234-123456789012`. The API returned `202` / `PENDING`.

CloudWatch recorded a native JSON application event at `2026-10-29T01:02:06.615Z`:

```json
{
  "EventName": "RequestHandled",
  "MessageId": "2b854531-540e-4616-b2e4-997261593f42",
  "EventId": "81b9e490-98a2-4d08-8f69-a1309806a207",
  "TransactionId": "81b9e490-98a2-4d08-8f69-a1309806a207",
  "CorrelationId": "12345678-1234-4234-8234-123456789012",
  "Outcome": "SubmissionAccepted"
}
```

These properties were present as top-level JSON fields, alongside the runtime
timestamp, level, invocation request ID and trace ID. This log did not contain
the amount, destination account or external reference.

A subsequent GET returned HTTP `200`, `SUCCEEDED` / `APPROVED`, with processor ID
`5e1ae8ca-b528-47ad-a1fa-ef1edcb3d083`. Completion occurred at
`01:02:09.8034766Z`; the final table update occurred at `01:02:11.8156571Z`.
This validates the success path and correlation in the deployed Request Handler.
The new failure-log format has local test coverage but has not yet been exercised
by a new controlled AWS timeout after this deployment.
