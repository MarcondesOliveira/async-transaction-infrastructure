# Stage 12 — Observability, security and resilience

Status: in progress. The following evidence covers the Request Handler and Callback
Handler and Transaction API observability increments, not completion of the entire stage.

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

## Callback Handler package and deployment plan

- Owner-pushed application commit confirmed against GitHub `main`:
  `596b1e994f97bb1bdf431af0e3c2dbd9df0a960b`; local checkout is clean.
- Build passed with zero warnings/errors; all 34 tests passed (13 unit,
  18 integration, 3 contract). Formatting verification passed.
- Two initial new test assertions incorrectly expected rendered outcome text.
  After joint review and owner approval, they were corrected to check the
  template and separately recorded argument used by `TestLambdaLogger`.
  The correction did not modify application behavior.
- Framework-dependent Release publish for `net10.0` / `linux-arm64` succeeded.
- S3 key:
  `async-transaction-callback-handler/596b1e994f97bb1bdf431af0e3c2dbd9df0a960b/async-transaction-callback-handler.zip`.
- ZIP SHA-256:
  `294c451d7f7927906ff94694d5627062ee83904b32e96407c2ba7bfcf009c053`.
- Lambda Base64 checksum:
  `KUxFHX95J5Bv+UaU1WJwYu6DkEsy6WQHwrp7/PAJwFM=`.
- Conditional S3 creation, AES256 encryption and SHA-256 validation succeeded;
  the returned S3 checksum matches the package.
- `terraform fmt -check`, `terraform validate` and `git diff --check` passed.
- Saved plan: `stage12-callback-observability.tfplan`, **0 to add, 1 to change,
  0 to destroy**. Only the Callback Handler package/hash and logging format/levels
  change. JSON logging uses the existing log group with application/system `INFO`.

The owner approved the saved Callback Handler plan. Apply succeeded with
**0 added, 1 changed, 0 destroyed**. The Lambda is `Active`, with update status
`Successful` and the expected package checksum. JSON application/system `INFO`
logging was confirmed in `/aws/lambda/async-transaction-processing-dev-callback-handler`.
The post-apply Terraform plan exited with code 0 and reported no changes.
Endpoints, IAM, queues, timeouts and other Lambdas were unchanged.

Manual validation of the new callback logs remains pending: create a new
transaction through the main API and inspect `CallbackHandled` / `Applied` with
matching identifiers in the callback-handler log group, then verify final state
through GET. Duplicate/failure-log runtime tests are separate checks and must not
be claimed as covered by a success-only request.

## Manual success validation — Callback Handler logs

The owner submitted transaction `81658c74-e8ec-4e2e-8715-6cd0fbec01f6` through
the main API at `2026-10-29T01:18:34.6837336Z`, with correlation ID
`23456789-2345-4345-8345-234567890123`. The initial response was `PENDING`.

CloudWatch recorded a native JSON application event at `2026-10-29T01:18:46.920Z`:

```json
{
  "EventName": "CallbackHandled",
  "MessageId": "176c8d37-87cd-414d-8046-412ddccd755b",
  "EventId": "04718ef6-2d02-4ca1-809c-71038b9ae29f",
  "TransactionId": "81658c74-e8ec-4e2e-8715-6cd0fbec01f6",
  "CorrelationId": "23456789-2345-4345-8345-234567890123",
  "ProcessorTransactionId": "4e604996-0a84-4d3d-b868-1e9c99203560",
  "Outcome": "Applied"
}
```

All identifiers and the outcome were top-level JSON fields. The event did not
contain the raw payload, result message, destination account or amount.
A GET returned HTTP `200` with `SUCCEEDED` / `APPROVED`, matching the processor
ID above. Completion time was `01:18:44.1347969Z` and the final table update was
`01:18:45.6729837Z`. This validates the deployed applied-result logging path;
the new duplicate and failure log formats remain covered locally, not by this
manual AWS success test. Infrastructure owner review and commit/push are pending.

## Transaction API package and deployment plan

- Owner-pushed commit confirmed against GitHub `main`:
  `7d440ef121afbd040ebd05817e54a67f305e502b`; local checkout is clean.
- Application build passed with zero warnings/errors, all 25 tests passed
  (9 unit, 13 HTTP integration, 3 contract), and formatting verification passed.
- `CA1873` findings were resolved after owner review by checking log levels
  before preparing exception metadata. An additional test-only `CA1861` finding
  was resolved using a reusable expected-status array. No analyzer was disabled.
- Framework-dependent Release publish for `net10.0` / `linux-arm64` succeeded.
- S3 key:
  `async-transaction-api/7d440ef121afbd040ebd05817e54a67f305e502b/async-transaction-api.zip`.
- ZIP SHA-256:
  `4301e5bb5c6f0ef6516c88f83ac754c217b82bd941d8594d4f5d8606c3332101`.
- Lambda Base64 checksum:
  `QwHlu1xvDvZRbIj4OsdUwhe4K9lB2FlNT12GBsMzIQE=`.
- Conditional S3 creation, AES256 encryption and SHA-256 validation succeeded;
  S3 returned the matching checksum.
- `terraform fmt -check`, `terraform validate` and `git diff --check` passed.
- Saved plan: `stage12-api-observability.tfplan`, **0 to add, 1 to change,
  0 to destroy**, changing only the existing Transaction API package key/hash.

Terraform now explicitly declares the existing runtime `Text` log format and
existing API log group; these settings produce no runtime diff. ASP.NET itself
emits JSON with structured properties under `State`, unlike the native
`ILambdaLogger` top-level fields used by the SQS handlers. Keeping runtime `Text`
avoids double encoding the ASP.NET JSON. Endpoints, IAM, timeouts, queues and
other Lambdas are unchanged by the plan.

The owner approved the saved plan. Apply completed with **0 added, 1 changed,
0 destroyed**. The API Lambda is `Active`, with last update `Successful` and
the expected checksum `QwHlu1xvDvZRbIj4OsdUwhe4K9lB2FlNT12GBsMzIQE=`.
Runtime logging remains `Text` in the existing transaction-api log group, as
intended for ASP.NET-generated JSON. A post-apply Terraform plan exited with
code 0 and reported no changes.

Manual validation remains pending. Have the owner POST a new transaction through Bruno or Swagger and GET its ID;
inspect `TransactionApiHandled` with HTTP statuses 202/200 and matching identifiers
in the API log group. Replaying an identical POST with a different request
correlation is a separate check: stored `CorrelationId` must remain original,
while `RequestCorrelationId` follows the replay. Failure-log runtime tests must
not be claimed as covered by a successful transaction alone.

## Manual success validation — Transaction API logs

The owner created transaction `235092fe-563e-46a5-806f-01aaaea4a056` with
correlation ID `34567890-3456-4456-8456-345678901234`. CloudWatch confirmed
`TransactionApiHandled` with `Operation=Create`, `HttpStatus=202` and matching
transaction/request correlations. The persisted creation time was
`2026-10-29T01:32:05.6935952Z`.

GET returned HTTP `200`, `SUCCEEDED` / `APPROVED`, with processor ID
`aed340de-1f74-4b8f-bd43-42263d671756`, completion at `01:32:14.4998967Z`
and final table update at `01:32:15.9343598Z`.

The API log group contains a prior GET with request correlation
`ab897b71-7017-4d37-88b0-f037beb1ae52` while preserving the stored transaction
correlation. Our subsequent GET explicitly supplied the original correlation
header and produced another `TransactionApiHandled`, `Operation=Get`,
`HttpStatus=200`, with that value in both correlation fields.

The API emits parseable application JSON without a second runtime JSON wrapper.
Its structured identifiers and status are under `State`, as expected for the
ASP.NET formatter. The inspected application events contained no amount,
destination account, external reference or idempotency key. Success and GET
correlation separation are now validated in AWS; POST replay and failure events
still have local test coverage only for this increment. Owner review and
infrastructure commit/push remain pending.
