# Temporary lab operations — Stage 12 closeout

Reviewed 2026-10-29. This is a small, disposable demonstration, not a production
operations platform. No new AWS resources or runtime changes are introduced here.

## Configuration and secrets

- Lambdas obtain AWS credentials from execution roles, not source code or environment access keys.
- Reviewed Lambda environment keys hold table names, controlled HTTPS endpoints,
  processing delay/retention and ASP.NET environment; no application secret is
  required by the current HTTPS-only, unauthenticated demonstration contract.
- Real `terraform.tfvars`, `backend.hcl`, state and saved plans are ignored. Only
  illustrative examples are tracked. Keep credentials in the local AWS credential
  chain, never in those files. Git ignore does not encrypt local files.
- Remote state/artifacts use the existing private, encrypted S3 buckets. Treat
  state and plans as sensitive even when today's inputs contain no passwords.
- OIDC replaces permanent GitHub AWS keys; actual workflow authorization is tested
  in Stage 13. Bootstrap/IAM administration stays owner-operated.
- No Secrets Manager/SSM service is added without a secret to manage. If a future
  integration introduces credentials, choose protected storage and runtime access
  explicitly; do not put the secret in Terraform literals or commit examples.
- The source scan found no secrets within its documented scope, not proof that
  history, local files or deployed logs are universally clean. See
  [security review](security-review.md).

Public endpoints, no callback HMAC/authentication, caller-supplied simulator
callback URLs and missing callback REST access logging remain explicit lab
limitations. Use synthetic data and controlled destinations; do not represent
this as a secure public financial API. Custom alarms, CMKs, PITR, tracing and
production recovery features are outside the accepted temporary-lab scope.

## Timeouts, retries and retention

| Boundary | Reviewed setting | Interpretation |
|---|---|---|
| Main API / simulator API | Lambda and HTTP integration 30 s | Only accepts/persists; does not wait for the final result. |
| Request Handler | Lambda 15 s; outbound HTTP 10 s | HTTP failures return the record for retry. |
| Callback Handler | Lambda 15 s | Conditional terminal updates and idempotent receipts. |
| Request/result SQS | Visibility 90 s; batching window 0; batch 5; partial responses | Visibility is six times the function timeout; failed records can return independently when the invocation completes. |
| Request/result redrive | maxReceiveCount 3 | Deliberately short lab policy; not three retries plus the initial attempt. |
| Simulator worker | Lambda 30 s; HTTP 10 s; delay configurable 0–10 s | Stream batch 1; two function-error retries, maximum record age 1 h. |
| Main queues / all three failure queues | 4 days / 14 days | Inspection is manual; retention is not indefinite recovery. |
| DynamoDB Streams | 24 h | Failure metadata does not extend Stream retention. |
| CloudWatch logs | 7 days | Investigate before logs expire; no custom automatic alerts. |
| Core idempotency / callback receipts | TTL +24 h | Transaction itself has no TTL and remains until explicit cleanup/destroy. |
| Simulator operation | TTL +24 h | Entire operation includes its idempotency information. |

Lambda timeouts, environment key names and event-source mappings were checked
against AWS. Queue/retention settings above were reviewed in Terraform; this
closeout does not claim a fresh live check of every queue attribute. Existing
success, timeout, duplicate/conflict and DLQ evidence is retained in the stage
evidence documents; no failure injection or redrive was repeated for this review.

Accepted tradeoffs: AWS recommends at least five receives for Lambda/SQS; this
lab retains three to demonstrate exhaustion quickly. Batch five is processed
sequentially by the Request Handler: several slow HTTP calls can exceed the
15-second invocation budget, in which case the invocation may fail before returning
partial results. That is a known throughput/load limitation, not an exactly-once
or sustained-load guarantee. Streams-to-Pipes delivery before SQS is a separate
failure boundary, not protected by the processing queues' consumer DLQs.

TTL expiration is not a deletion deadline: DynamoDB removes eligible items
asynchronously, usually within days. Redelivery can outlive the 24-hour receipt
or simulator-operation window, so inspect persisted state before replaying older
messages. Do not assume deduplication forever or automatically recreate a missing
operation with a new key.

## Inspect and recover a failure — manual owner procedure

1. In AWS SQS, inspect approximate visible/in-flight counts for the project queue
   in the intended region. Counts are approximate. Do not purge or bulk-redrive.
2. Use **Send and receive messages** only when ready to inspect: polling is not
   read-only. Receive increments receive counters and temporarily hides messages;
   keep the visibility short and do not delete during diagnosis. Keep payloads
   local/private, outside Git and public screenshots.
3. Record transaction/event IDs, queue, receive timestamps and the matching log
   outcome. Compare the public transaction GET with the processor operation and
   callback receipt when relevant. Distinguish a retryable dependency failure
   from malformed input or a terminal-state/event-ID conflict.
4. Correct the cause first. A callback conflict is intentionally quarantined;
   do not mutate a succeeded transaction to failed or change event identity just
   to make replay pass. Terminal transactions must retain their accepted result.
5. Choose recovery by queue below. Any replay sends real work: review the target,
   payload, TTL/deduplication window and expected result with the owner first.
6. Verify logs, final GET and queue counts afterward. Successful HTTP acceptance
   alone is not completion. Delete/quarantine the original failure evidence only
   after verified recovery or an explicit decision to discard a synthetic test.

### `failed-requests` → `processing-requests`

Contains the original `TransactionRequested` event. For a valid transient failure,
use SQS **Start DLQ redrive**, explicit original destination and a low custom rate
(for example 1 message/s), only after checking every message that will move. This
is a queue-level task, not a transaction-ID filter. If mixed/poison messages exist,
do not bulk-redrive: send only one reviewed original body to the source queue,
preserving its application IDs, and retain the DLQ copy until verification.
Never send that body directly to the external API or create a new main-API POST
as a substitute for replaying the original transaction.

### `failed-results` → `processing-results`

Contains the raw callback event (SNS raw delivery is enabled). The same reviewed
redrive/one-message procedure applies. Preserve event ID, transaction ID, result
and processor ID. A previously applied identical callback should be a duplicate;
an altered payload under the same event ID must remain a conflict, not be forced
through. Inspect receipt TTL and terminal state for old events.

### `external-simulator-failed-callbacks` — not source-queue redrive

This is a DynamoDB Stream on-failure destination, not an SQS consumer DLQ.
Its body holds failure/Stream metadata, not the original worker event. Do not move
it to either processing queue or invoke the worker with the metadata body.

Within Stream retention, retrieve the original record identified by its shard and
sequence metadata. Alternatively, while the operation item still exists, reconstruct
a reviewed Stream-shaped worker test event from that operation: `Records` array,
`eventName: INSERT`, and `dynamodb.NewImage` in DynamoDB AttributeValue format.
Preserve the original callback event ID, processor ID, transaction ID, outcome,
accepted time and operation fields required by `WorkerFunction.FromStreamImage`.
After correcting a controlled callback destination/dependency, invoke only the
simulator worker through the Lambda console with the reviewed event. This direct
invocation does not test automatic Stream retry/redrive.

If both the original Stream record and operation are gone, automated recovery is
not available in this lab. Do not fabricate a financial result: record the lost
synthetic test and create a clearly separate new demonstration if needed. No
recovery execution or message deletion was performed in this closeout.

## References

- [Lambda/SQS visibility, retries and partial batches](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-configure.html)
- [SQS redrive scope and rate controls](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-dead-letter-queue-redrive.html)
- [DynamoDB Stream failure destinations](https://docs.aws.amazon.com/lambda/latest/dg/services-dynamodb-errors.html)
- [DynamoDB TTL deletion timing](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/TTL.html)
