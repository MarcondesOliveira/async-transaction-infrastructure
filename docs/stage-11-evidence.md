# Stage 11 — End-to-end validation

Environment: AWS `us-east-1`, `dev`. Infrastructure baseline: `b2edb8a`.

Validation is sequential: the owner submits manual HTTP tests through Bruno, then the resulting identifiers are checked against the public GET, DynamoDB records and Lambda logs. Previous evidence is reused explicitly rather than claimed as a new test.

## Scenario matrix

| Scenario | Evidence / status |
| --- | --- |
| Successful transaction | Validated in Stage 10: `26b3b2f1-e6ed-437a-96a1-4239a3bfb8a7`, `SUCCEEDED` / `APPROVED` |
| Duplicate callback | Validated in Stage 10: event `d0a07a80-f36a-4d78-98e4-cb4a93799e8b`, `Duplicate`, unchanged terminal timestamps |
| Conflicting callback, retries and Results DLQ | Validated in Stage 10: message `93efcc8e-8408-4ea2-a75f-87140d8e6e68`, three attempts, unchanged original result, message preserved in Failed Results |
| Transient processor unavailability and Requests DLQ | Validated in Stage 7 using the reserved `.invalid` processor domain; DNS/HTTP failure, not a measured HTTP timeout |
| Business rejection through the full deployed pipeline | Validated: `4ef03eb4-3f9a-4b1b-95a7-34a6bd501c10`, `REJECTED` / `DESTINATION_REJECTED`, matching callback log `Applied` |
| Final simulated technical failure through the full deployed pipeline | Validated: `df7666bf-bf80-4985-8beb-b6aa258f80d1`, `FAILED` / `PROCESSING_ERROR`, matching callback log `Applied` |
| HTTP timeout | Validated in AWS: `521185f2-9a27-4e57-a8d2-ca2627d576f7`, three explicit ten-second HTTP timeouts, original message confirmed in Failed Requests, no simulator operation and main state remains `PENDING` |
| Callback gateway rejects malformed/missing-field requests | Validated manually: `{}` returned HTTP 400 with `Invalid request body` |
| No request re-enqueue from final updates / callback receipts | Active Pipe filter confirmed; request queue empty and no Request Handler log entries observed between `00:24:22` and approximately `00:26:01 UTC` on 2026-10-29 |

See [Stage 7 evidence](stage-7-evidence.md) and [Stage 10 evidence](stage-10-evidence.md) for timestamps, identifiers, deployed artifacts and logs. A `.invalid` DNS failure must not be described as an HTTP timeout.

## Manual request entry point

All business scenarios begin at the **main Transaction API**, not at the simulator or callback endpoint:

```text
POST https://8st0dstrp8.execute-api.us-east-1.amazonaws.com/transactions
```

Use `Content-Type: application/json`, a new `Idempotency-Key` and a correlation UUID. Use the returned transaction ID for:

```text
GET https://8st0dstrp8.execute-api.us-east-1.amazonaws.com/transactions/{transactionId}
```

The POST returns `202` / `PENDING`; the GET eventually returns a terminal result. Use a new key for each independent scenario. Keep callback duplicate/conflict tests at the dedicated callback endpoint, as documented in Stage 10.

## First remaining manual scenario — business rejection

Prepared request:

```text
Idempotency-Key: e2e-rejected-0001
X-Correlation-Id: dddddddd-eeee-4fff-8aaa-bbbbbbbbbbbb
```

```json
{
  "transactionType": "TRANSFER",
  "amount": { "value": "125.90", "currency": "BRL" },
  "destination": { "accountId": "reject-portfolio-001" },
  "externalReference": "e2e-rejected-0001"
}
```

Expected final state: `REJECTED`, result code `DESTINATION_REJECTED`. This represents an accepted submission that later receives a negative business result, not an HTTP submission error.

### Observed result

The owner supplied the POST response with initial `PENDING` for transaction `4ef03eb4-3f9a-4b1b-95a7-34a6bd501c10`. A public GET returned HTTP 200 with `REJECTED`, code `DESTINATION_REJECTED` and message `Destination rejected by simulation rule`.

- Processor ID: `e056f979-46be-414f-8191-faaecb880bf9`.
- Correlation ID: `dddddddd-eeee-4fff-8aaa-bbbbbbbbbbbb`.
- Created at: `2026-10-29T00:20:30.6834176+00:00`.
- Completed at: `2026-10-29T00:20:40.3138251+00:00`.
- Updated at: `2026-10-29T00:20:41.8749809+00:00`.
- Callback event: `99607231-cc6e-4843-8a2b-b4bd5193da73`.
- Callback Handler log: `Applied` at `2026-10-29T00:20:43.112Z`, request `70bff006-9cbc-57da-be24-935a0f32b9e4`.

The rejected business result traversed the deployed callback pipeline and was applied successfully.

## Final simulated technical failure

The owner created a new main API transaction using destination `fail-portfolio-001`, amount `180.50 BRL`, idempotency key `e2e-failed-0001` and external reference `e2e-failed-0001`, then supplied transaction ID `df7666bf-bf80-4985-8beb-b6aa258f80d1`.

A public GET returned HTTP 200 with terminal status `FAILED`, result code `PROCESSING_ERROR` and message `Simulated final processing failure`.

- Correlation ID: `eeeeeeee-ffff-4aaa-8bbb-cccccccccccc`.
- Processor ID: `ce731350-c196-45af-b565-de50839ed22a`.
- Callback event ID: `a562e41b-6c6e-4dc5-915f-a38d93e0b089`.
- Created at: `2026-10-29T00:23:13.7950502+00:00`.
- Completed at: `2026-10-29T00:23:20.9509715+00:00`.
- Updated at: `2026-10-29T00:23:21.76851+00:00`.
- Callback Handler log: `Applied` at `2026-10-29T00:23:21.861Z`, request `769ca81b-5f55-5688-ab31-cb47cb6d3c75`.

This is a correctly processed terminal failure result from the simulator. It is not a Lambda execution error, HTTP timeout or DLQ scenario.

## Callback gateway validation

The owner posted `{}` to the deployed callback endpoint through Bruno using JSON content type and a correlation header. The supplied screenshot confirms HTTP `400 Bad Request` with `{"message":"Invalid request body"}`. This validates rejection by the configured request model before its SNS integration is invoked; SNS publication metrics were not separately measured for this request.

## Bounded observation for request cycles

After terminal rejection/failure updates and callback receipt writes, the deployed Pipe was read as `RUNNING` with the conjunction `eventName = INSERT`, `NewImage.entityType = TRANSACTION`, and `NewImage.status = PENDING`. That filter excludes MODIFY events and callback receipt inserts.

At approximately `2026-10-29T00:26:01Z`, Processing Requests reported zero visible and zero in-flight messages. Request Handler log search from `2026-10-29T00:24:22Z` returned no entries. No repeated request processing was observed in this bounded interval; this does not claim an unbounded exactly-once guarantee.

## Completion boundary

All scenarios in the matrix now have recorded evidence. The deterministic timeout extension was implemented, reviewed, committed and deployed as described below. No DLQ message was deleted or manually redriven during these checks. Final evidence review and owner commit/push remain pending; no Stage 12 work has started.

## Controlled timeout implementation — local validation

The owner authorized a deterministic pre-acceptance timeout scenario in the simulator. Valid destination accounts starting with `timeout-` wait twelve seconds before returning `503 SIMULATED_TIMEOUT`, with no repository call or accepted operation. The Request Handler's existing ten-second client limit should expire first. The scenario is selected after validation; cancellation also performs no persistence. No callback is generated.

The initial build found analyzer rules `CA1848` (logging delegates) and `CA1001` (test timer disposal). After joint approval these were corrected with source-generated `LoggerMessage` and a disposable controlled test clock. Build passed with zero warnings/errors; all 23 simulator tests passed (13 unit, 6 integration, 4 contract). The five added cases cover case-insensitive matching, the twelve-second pending delay, cancellation, validation-before-delay and the delayed HTTP 503 response without persistence. No new package dependency was added.

Owner review, simulator commit/push, artifact publication, reviewed deployment and runtime timeout evidence remain pending. The older AWS simulator deployment does not yet implement this reserved prefix; no manual AWS timeout request has been sent.

### Published timeout artifact and deployment plan

- Owner push confirmed: simulator commit `2b22f66454a0a720f8aa46c81fcbf4756c883f53`, local checkout clean and synchronized with `origin/main`.
- Framework-dependent Release package published for `linux-arm64`.
- S3 key: `external-transaction-processor-simulator/2b22f66454a0a720f8aa46c81fcbf4756c883f53/external-transaction-processor-simulator.zip`.
- ZIP SHA-256: `3753418c66804995d22bc0bdd54a3e36f9d0eb8c7a59c6d14958be788f5ed925`.
- Lambda/S3 checksum: `N1NBjGaASZXSK8C91Uo+NvnQ64x6WcbRSVi+eI9e2SU=`; conditional upload succeeded with matching checksum and AES256 encryption.
- Saved local plan: `stacks/external-simulator/simulator-timeout.tfplan`.
- Plan: **0 to add, 2 to change, 0 to destroy**, updating only the package keys/hashes of the simulator API and worker, which share one artifact.

The owner approved the plan and it was applied: **0 added, 2 changed, 0 destroyed**. Both simulator functions are `Active`, update status `Successful`, with the expected package checksum. The core stack was unchanged. Manual runtime timeout validation remains pending.

### Runtime timeout — validated

The owner submitted the documented `timeout-portfolio-001` transaction and supplied ID `521185f2-9a27-4e57-a8d2-ca2627d576f7`. The main GET returned `PENDING`, null processor ID/result/completion time and unchanged creation/update time `2026-10-29T00:39:44.8222662+00:00`.

SQS message `f4519207-0069-4665-8a04-e0693ecda2ed` first failed at `2026-10-29T00:39:58.101Z`, Lambda request `51570a33-a916-54f3-bb80-696f31197607`. The exception chain explicitly states `TaskCanceledException: The request was canceled due to the configured HttpClient.Timeout of 10 seconds elapsing`, wrapping `TimeoutException`, then classified as `ExternalProcessorTransientException`. The invocation report gives duration `10424.81 ms`.

A consistent read of the simulator idempotency/operation key returned no item. The first timeout is confirmed; subsequent retries and target-message DLQ inspection are still being observed.

The same SQS message subsequently failed at `2026-10-29T00:41:26.677Z` (request `21399a80-6419-5793-ae52-f9dcfc7d3567`) and `2026-10-29T00:42:56.706Z` (request `42c5ae69-7147-549f-88ba-cd35e9ff0b98`). All three exception chains explicitly reference `HttpClient.Timeout of 10 seconds`, unlike the earlier DNS failure. Failure timestamps are about 90 seconds apart, with first-invocation overhead accounting for the slightly shorter first interval.

The simulator's application logs confirmed the same transaction/correlation reached the deliberate delay and completed without acceptance. After retry exhaustion, a non-deleting diagnostic DLQ receive confirmed message `f4519207-0069-4665-8a04-e0693ecda2ed` and its original `TransactionRequested` body for the timeout destination. The zero-visibility diagnostic response repeated the same message ID; it is not evidence of distinct new requests or extra handler attempts. Handler attempt count is established from CloudWatch, not diagnostic receives or their counters.

A final consistent query returned `Item = null` for `IDEMPOTENCY#transaction:521185f2-9a27-4e57-a8d2-ca2627d576f7:submit:v1` in the simulator table. Processing Requests reported zero visible and zero in flight. Final public GET preserved `PENDING`, null processor ID/result/completed time, and unchanged `createdAt` / `updatedAt` at `2026-10-29T00:39:44.8222662+00:00`. No callback is generated for an operation that was never stored.

This completes deployed timeout classification, retries and Requests DLQ validation. The injected scenario intentionally represents a provider that has not accepted the operation; it does not model acceptance followed by a lost acknowledgement.
