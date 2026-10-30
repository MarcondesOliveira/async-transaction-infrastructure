# Five-minute portfolio demonstration

[Project overview](../README.md) · [Reproduction](reproduce.md) ·
[Contracts and states](contracts.md)

Prerequisite: the lab is already provisioned and a recent delivery/smoke has
succeeded. This script exercises existing runtime; it does not deploy, change
IAM, receive/purge queue messages or destroy anything. POSTs do create synthetic
records and incur normal usage. Use only an owner-approved, controlled lab.

## 1. Introduce the flow

Open the [architecture](architecture/async-transaction-processing.drawio.png).
Explain: accept a transaction, persist it, dispatch through messaging, submit to
an independent processor, then apply its asynchronous callback. The client reads
the result through GET rather than waiting on the original connection.

The simulator implements a possible external service behind an HTTP boundary.
Its own storage/worker are demonstration internals, not something the main
application accesses or assumes a real external provider uses.

## 2. Submit through the main API

Obtain `transactions_api_url` from the core deployment output. Open
`<API_BASE_URL>/swagger/index.html` or configure Bruno with that base URL.
Choose **POST `/transactions`**, not simulator `/v1/transactions` or the callback.

Headers:

```http
Content-Type: application/json
Idempotency-Key: demo-your-unique-run-0001
```

Replace the example key with a new value for this independent demonstration;
keep it unchanged during the replay test below. `X-Correlation-Id` is optional;
omit it to let the API generate a UUID. In Swagger, fill the header parameter;
do not add it to the JSON body.

```json
{
  "transactionType": "TRANSFER",
  "amount": { "value": "1.00", "currency": "BRL" },
  "destination": { "accountId": "portfolio-demo" },
  "externalReference": "portfolio-demo-0001"
}
```

Expect `202` with `transactionId`, `correlationId` and `links.self`. Save those
IDs locally. A newly created transaction is `PENDING`; a replay can already
return its current terminal status. `202` is acceptance, not completed processing.

## 3. Read and explain the final result

Call **GET `/transactions/{transactionId}`** using the ID from the POST.
Repeat at a modest interval until terminal; there is no fixed completion-time
guarantee. A transition can occur between calls, so seeing `PROCESSING` is not
required. For this account, expect:

```json
{
  "status": "SUCCEEDED",
  "result": {
    "code": "APPROVED",
    "message": "Transaction processed successfully"
  }
}
```

This is an excerpt, not the entire response. The full GET also exposes transaction,
correlation and processor IDs, original fields and timestamps. Link the outcome
back to the request consumer, simulator worker and callback consumer. The
callback may finish a `PENDING` transaction before its acceptance update wins.

If it does not complete, inspect correlated Lambda logs and the pipeline result
using [operations](lab-operations.md). Do not keep creating POSTs, purge queues
or change IAM blindly to make the demonstration pass.

## 4. Demonstrate idempotency and one controlled conflict

1. Resend exactly the same POST/key/body. Expect `202` and the same transaction ID,
   not another transaction.
2. Keep that key, change `amount.value` to `2.00`, and submit. Expect
   `409 IDEMPOTENCY_KEY_REUSED`; the original transaction/result stays unchanged.
3. Restore the body if keeping the saved request. Use a **new key** for any new
   independent transaction.

Explain the two initial DynamoDB items: one transaction and one key/hash mapping,
created atomically. Callback application adds its own receipt. The transaction
has no TTL; deduplication items have +24 h expiry timestamps, not guaranteed
physical deletion at exactly 24 h. This is idempotent application behavior over
at-least-once delivery, not an exactly-once transport claim.

Optional, with a fresh key for each case:

| Destination account | Expected terminal result |
| --- | --- |
| `reject-demo` | `REJECTED / DESTINATION_REJECTED` |
| `fail-demo` | `FAILED / PROCESSING_ERROR` |

Missing/invalid `Idempotency-Key` produces `400 VALIDATION_ERROR`: an expected
validation response, not evidence that Swagger or Lambda is broken. The slower
`timeout-`/DLQ scenario is already documented and is not needed for this short
walkthrough. Do not inject a contradictory webhook into a completed transaction
just to demonstrate an error.

## 5. Show delivery evidence and close

Open a previously completed GitHub Actions delivery: show approved source commit,
CI tests/audit/package, OIDC publication, linked central Terraform run, selected
Lambda hash/status verification and final synthetic smoke. For simulator delivery,
two functions share the verified package; the other service deliveries target one.
Do not push or redeploy merely to give this presentation.

Close with the boundaries: synthetic data, no caller authentication/HMAC,
temporary retention and manual recovery, no real payment processing. Reproduction
starts at the [five-repository guide](reproduce.md); privileged first provisioning
is separate from automatic routine delivery. Repositories require access while
private. Hide account details, tokens, local configuration and sensitive logs
when recording or sharing screenshots.

Final removal is a **separate stage**, not part of this demonstration. Follow
[the teardown procedure](final-teardown.md) only after explicit approval; the
documented preparation and deletion previews do not prove actual destruction.
