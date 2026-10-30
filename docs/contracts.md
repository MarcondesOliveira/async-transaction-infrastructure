# Transaction contracts and state transitions

[Project overview](../README.md) · [Reproduction](reproduce.md) ·
[Inspection and recovery](lab-operations.md)

This is the cross-repository reference for the implemented lab, not a proposed
production contract. Examples use synthetic data. The API, request consumer,
simulator and result consumer own separate DTOs; there is no shared runtime
contracts package. JSON uses camelCase, UUID identifiers and uppercase statuses.
System-produced timestamps use ISO 8601 UTC; monetary amounts are JSON strings.

## 1. Client → Transaction API

`POST /transactions` requires `Content-Type: application/json` and
`Idempotency-Key` (8–128 printable ASCII characters, excluding spaces).
`X-Correlation-Id` is an optional UUID; the API generates one when absent.

```json
{
  "transactionType": "TRANSFER",
  "amount": { "value": "250.75", "currency": "BRL" },
  "destination": { "accountId": "portfolio-account-001" },
  "externalReference": "demo-0001"
}
```

The API accepts only `TRANSFER` and `BRL`. Value must be positive, with 1–12
integer digits and exactly two decimal places. Account ID must not be blank and
has a 64-character maximum; optional `externalReference` has a 100-character
maximum. Unknown JSON properties are rejected.

The first successful call atomically creates a `PENDING` transaction and its
idempotency record, then returns `202` with `transactionId`, `correlationId`,
`status`, `createdAt`, `updatedAt` and `links.self`. `Location` points to that
relative transaction URL. Same key and normalized body return the same
transaction (including its current status and original correlation), not a new
submission. Changed content returns `409 IDEMPOTENCY_KEY_REUSED`.

`GET /transactions/{transactionId}` returns the current representation, including
original business fields and, when available, `processorTransactionId`,
`result.code`, `result.message` and `completedAt`. Invalid requests return
`400 VALIDATION_ERROR`; a missing transaction returns `404 TRANSACTION_NOT_FOUND`.
See the [API contract](https://github.com/MarcondesOliveira/async-transaction-api/blob/main/docs/api-contract.md)
and its Swagger/OpenAPI for HTTP details.

## 2. DynamoDB Stream → Pipes → request SQS

The [Pipe](../stacks/core/pipes.tf) selects only `INSERT` records whose new image
has `entityType = TRANSACTION` and `status = PENDING`. Updates, idempotency records
and callback receipts do not create new processing requests.

Its input transformation produces this version 1 `TransactionRequested` body:

```json
{
  "eventVersion": 1,
  "eventType": "TransactionRequested",
  "eventId": "11111111-2222-4333-8444-555555555555",
  "occurredAt": "2026-10-30T12:00:00Z",
  "transactionId": "11111111-2222-4333-8444-555555555555",
  "correlationId": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  "transactionType": "TRANSFER",
  "amount": { "value": "250.75", "currency": "BRL" },
  "destination": { "accountId": "portfolio-account-001" }
}
```

`eventId` is the transaction UUID, not a new UUID per delivery; `occurredAt` is
the transaction's `createdAt`. The SQS record body contains the event JSON.

**Current propagation limit:** the API stores `externalReference`, but the Pipe
template does not include it. The consumer DTO supports the optional field, but
the deployed main flow does not forward the client's reference to the simulator.
It remains available from the main API's GET. This is documented behavior, not an
end-to-end propagation guarantee.

The [request consumer](https://github.com/MarcondesOliveira/async-transaction-request-handler/blob/main/docs/contracts.md)
rejects unknown properties, unsupported event type/version and empty identifiers.
Its business validation is deliberately broader than the public API: nonblank
transaction type/account, positive decimal string and three-character currency.
It does not independently enforce the API's `TRANSFER`/`BRL`, exact decimal
format, length limits or a non-default UTC `occurredAt`. The Pipe produces the
main API's validated data; these checks are not equivalent validation layers.

## 3. Request Handler → external simulator

The handler makes an HTTPS `POST /v1/transactions` to its configured processor
base URL. It preserves the event's correlation ID and derives a stable submission
key independently of the original client key:

```http
Content-Type: application/json
Idempotency-Key: transaction:11111111-2222-4333-8444-555555555555:submit:v1
X-Correlation-Id: aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee
```

```json
{
  "transactionId": "11111111-2222-4333-8444-555555555555",
  "transactionType": "TRANSFER",
  "amount": { "value": "250.75", "currency": "BRL" },
  "destination": { "accountId": "portfolio-account-001" },
  "externalReference": null,
  "callbackUrl": "https://callbacks.example.invalid/dev/callbacks/transactions"
}
```

The URL above is a non-working placeholder. In deployment, `callbackUrl` comes
from the core configuration, not from the original client request.

The simulator requires a non-empty transaction/correlation UUID, the same key
character/length rules, nonblank type/account, positive decimal string,
three-character currency and an absolute HTTPS callback URL. It rejects unknown
JSON properties. It normalizes currency to uppercase. It does not impose all the
main API's business restrictions.

It persists an independent operation before returning:

```json
{
  "processorTransactionId": "66666666-7777-4888-8999-aaaaaaaaaaaa",
  "transactionId": "11111111-2222-4333-8444-555555555555",
  "status": "ACCEPTED",
  "acceptedAt": "2026-10-30T12:00:02Z"
}
```

Same key and request fingerprint replay the original acceptance/IDs; a different
request returns `409 IDEMPOTENCY_CONFLICT` (a different code from the main API).
The fingerprint covers transaction/type/amount/normalized currency/account,
callback URL and external reference, not the correlation header. Retry with the
original correlation ID; changing it does not replace the persisted operation's
correlation.

| Submission outcome | Request Handler behavior | SQS record |
| --- | --- | --- |
| `202` with a usable acceptance | Conditionally set `PENDING → PROCESSING` and processor ID | Acknowledge |
| `429`, `5xx`, network error or timeout | No status transition | Fail for retry |
| Any other HTTP status | Conditionally set `PENDING → FAILED`, result code `PROCESSOR_HTTP_<status>` | Acknowledge |
| Invalid event, malformed acceptance or infrastructure exception | No successful completion of the record | Fail for retry |

The current client checks that a `202` body is deserializable and has a non-empty
processor ID; it does not fully cross-check returned transaction/status/timestamp
against the submitted request. Both status updates require the stored status to
be `PENDING`. A failed condition is acknowledged as an already-resolved race,
without overwriting a terminal result. Retries may repeat the HTTP submission;
the provider key, not the SQS message ID, makes it idempotent.

### Deterministic simulation scenarios

The account prefix comparison is case-insensitive:

| `destination.accountId` | Behavior |
| --- | --- |
| `reject-...` | Accepted operation; later `REJECTED / DESTINATION_REJECTED` callback |
| `fail-...` | Accepted operation; later `FAILED / PROCESSING_ERROR` callback |
| `timeout-...` | Wait 12 seconds before any persistence, then return `503 SIMULATED_TIMEOUT` if the client is still waiting |
| Any other nonblank account | Accepted operation; later `SUCCEEDED / APPROVED` callback |

The Request Handler's HTTP timeout is 10 seconds. The timeout scenario creates no
operation, reservation, Stream record or callback. It tests pre-acceptance retry
exhaustion, not a provider accepting work and losing the acknowledgement.

## 4. Simulator worker → callback gateway → SNS → results SQS

Only simulator Stream `INSERT + PROCESSOR_OPERATION + ACCEPTED` records trigger
its worker. A separate invocation constructs a version 1 `TransactionProcessed`
event and sends an HTTPS POST to the configured callback URL with
`Content-Type: application/json` and `X-Correlation-Id`.

The core route is `POST /{environment}/callbacks/transactions`, not the
simulator's `/v1/transactions` or the main API's `/transactions`:

```json
{
  "eventVersion": 1,
  "eventType": "TransactionProcessed",
  "eventId": "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff",
  "occurredAt": "2026-10-30T12:00:04Z",
  "transactionId": "11111111-2222-4333-8444-555555555555",
  "correlationId": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  "processorTransactionId": "66666666-7777-4888-8999-aaaaaaaaaaaa",
  "status": "SUCCEEDED",
  "result": { "code": "APPROVED", "message": "Transaction processed successfully" }
}
```

The API persists the callback event ID with the operation; the worker reuses it
and regenerates `occurredAt` per attempt. It treats any successful HTTP status as
delivery acknowledgement. Network/timeout/non-success responses fail the worker
invocation for the Stream retry policy.

The [gateway model](../stacks/core/callback_api.tf) requires all shown fields,
version/type, terminal status, UUID-shaped strings, UTC-shaped timestamp and
nonempty result strings; extra properties are disallowed. The correlation header
is required, but this gateway presence check does not authenticate it or compare
it to the body's correlation ID. The consumer additionally checks non-empty
UUIDs, a parsed non-default UTC timestamp and non-whitespace result strings.
Passing gateway validation alone does not guarantee successful processing.

Gateway publishes directly to SNS, without an HTTP-handling Lambda. Successful
publish returns `202 {"accepted":true}`; an unmatched/failed SNS integration
response maps to `502` with `CALLBACK_PUBLISH_FAILED`. Invalid request body/header
is rejected before publication. SNS raw delivery puts the event JSON directly in
the results SQS body, not inside an SNS `Message` envelope.

**Callback HTTP `202` means accepted for messaging, not applied to DynamoDB.**
The caller must query the main transaction or inspect consumer logs to confirm
the result. A conflicting callback can receive `202` and later fail in SQS.
The lab uses HTTPS without HMAC or caller authentication. Do not expose this
as a trusted payment integration; use synthetic data and controlled callback URLs.

## 5. Callback application and main transaction states

| Stored state | Trigger/condition | Result |
| --- | --- | --- |
| No transaction | First valid main API POST | `PENDING` |
| `PENDING` | Processor accepts; conditional Request Handler update wins | `PROCESSING` |
| `PENDING` | Permanent submission rejection; conditional update wins | `FAILED` |
| `PENDING` or `PROCESSING` | Valid matching callback | `SUCCEEDED`, `REJECTED` or `FAILED` |
| Terminal | Duplicate/identical result | No business state/timestamp change |
| Terminal | Different status, processor or result | Conflict; existing result retained |

`ACCEPTED` belongs to the simulator operation, not to the main transaction's
state enum. Callback-before-acceptance is supported: the callback may finish
`PENDING` directly; the subsequent Request Handler conditional update cannot
regress it to `PROCESSING`. Exhausting request retries does **not** automatically
turn a transaction into `FAILED`; it can remain `PENDING` with a request in DLQ.

The [callback repository](https://github.com/MarcondesOliveira/async-transaction-callback-handler/blob/main/src/MarcondesOliveira.AsyncTransactions.CallbackHandler.Infrastructure/DynamoDbCallbackRepository.cs)
uses consistent reads and an atomic receipt-plus-conditional-transaction write:

- Transaction must exist and correlation must match; an existing processor ID
  must match too. Otherwise the record fails instead of creating a transaction.
- Same `eventId` and business fingerprint is a duplicate. Changed business data
  under that event ID conflicts. Fingerprint includes version/type, transaction,
  correlation, processor, terminal status and result, but excludes `occurredAt`.
- A new event ID with the same already-stored terminal result may add a receipt
  without changing business timestamps. A contradictory result is never applied.
- `completedAt` is the first applied callback's `occurredAt`; `updatedAt` is its
  persistence time. A permanent submission rejection uses handler time for both.
- Conditional races are re-read for up to three local attempts. Unresolved
  contention, validation, conflicts and infrastructure failures become partial
  SQS batch failures; successful records in that batch are not failed with them.

There is no automatic terminal-to-terminal correction, callback reconciliation or
automatic DLQ replay. Transport is at-least-once; these guards provide idempotent
application behavior, not exactly-once delivery.

## 6. Retention and recovery boundaries

| Record/transport | Implemented retention or retry configuration |
| --- | --- |
| Main transaction | No TTL; retained until explicitly removed/teardown |
| Main API idempotency item | `expiresAt = createdAt + 24 h` |
| Callback receipt | `expiresAt = processedAt + 24 h` |
| Simulator operation | Configurable TTL from acceptance; default 24 h |
| Request/result SQS | Retention 4 days; DLQs 14 days; `maxReceiveCount = 3` by default (requests configurable) |
| Request/result visibility | 90 seconds by default (requests configurable) |
| Simulator Stream worker | Batch size 1, 2 maximum retry attempts, maximum record age 3,600 seconds, SQS failure destination |

TTL is an asynchronous cleanup timestamp, not immediate deletion or a strict
logical key-expiry window. Existing expired deduplication records can still be
read/replayed until removed. After a receipt disappears, the retained terminal
transaction still protects against conflicting results. After a simulator
operation disappears, its submission key no longer preserves the previous
acceptance. Do not treat these temporary records as a durable audit history.

The simulator's Stream failure queue contains invocation failure metadata, not a
normal callback payload. Request/result DLQs and this failure destination have
different recovery procedures. Follow [inspection and recovery](lab-operations.md)
before replay; there is no automatic rollback or compensation.

These contracts describe the current lab. Production authentication, replay
protection, stricter independent consumer validation, end-to-end external-reference
propagation and durable reconciliation remain outside the demonstrated scope.
