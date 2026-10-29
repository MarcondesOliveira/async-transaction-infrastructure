# Callback pipeline — Stage 10

The main stack defines a regional API Gateway **REST API** with direct AWS service integration to SNS, a raw SNS-to-SQS subscription, Processing Results and Failed Results, and the Callback Handler Lambda.

## Why REST API for this endpoint

The HTTP API service integration subtype list does not include SNS Publish. A REST API supports direct SNS integration and request-body validation, preserving API Gateway → SNS → SQS → Lambda without another application Lambda. Transaction API and simulator API remain HTTP APIs.

- [AWS HTTP API integration subtypes](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-aws-services-reference.html)
- [REST and HTTP API features](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html)

The callback endpoint is `POST /{environment}/callbacks/transactions` at the API's regional hostname. Terraform exposes its full URL as `callback_endpoint_url`. Unless `callback_url` is explicitly overridden, the Request Handler automatically sends this endpoint to the simulator in **new submissions**. Existing simulator operations retain their originally submitted callback URL and are not migrated or replayed automatically.

## Request and acknowledgement

Send the raw `TransactionProcessed` JSON and headers `Content-Type: application/json` and `X-Correlation-Id`. The REST method requires the correlation header and validates the JSON model: known fields, required identifiers, event type/version, terminal status, UTC timestamp shape and result fields. The handler validates actual identifiers, timestamps and stored transaction identity before persistence. Header presence does not authenticate the caller or prove equality with the body.

The mapping URL-encodes the full JSON as the SNS `Message`; no SNS JSON message-structure mode is used. The subscription's `raw_message_delivery = true` keeps the original JSON as the SQS body.

A successful SNS publication is mapped to HTTP `202`:

```json
{"accepted":true}
```

This deliberately simplifies the earlier acknowledgement example by omitting the echoed `eventId`; the event ID remains in the request and all downstream records. Direct service integration does not add an application handler to construct that echo. An unmatched/non-success SNS response maps to `502` with `CALLBACK_PUBLISH_FAILED`, not to an accepted acknowledgement. Unsupported content types are rejected by `passthrough_behavior = NEVER`.

`202` confirms publication, not a completed transaction. Poll the main Transaction API to verify the eventual result.

## Permissions and retries

- API Gateway assumes a dedicated role allowed to publish only to Transaction Results.
- The SQS resource policy permits SNS sends only from that topic ARN.
- Callback Handler consumes only Processing Results, writes only its own logs, and accesses only the main transaction table.
- DynamoDB transaction permissions include the underlying `GetItem`, `PutItem`, `UpdateItem` and `ConditionCheckItem` actions. See [AWS transactional IAM guidance](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis-iam.html).
- Processing Results is SQS-managed encrypted, with four-day retention and 90-second visibility for a 15-second Lambda.
- Partial batch failures are enabled. After three failed receives, messages move to Failed Results, retained for 14 days.
- The DLQ redrive allow policy restricts its source to Processing Results. It is not consumed automatically.

The processing DLQ handles messages already delivered to SQS whose handler processing failed. SNS delivery failures before enqueuing are a different boundary; a separate SNS subscription delivery DLQ is not introduced here.

## Logging boundary

The regional API Gateway account currently has no `cloudWatchRoleArn`. REST access/execution logging requires this account-level setting. This stage does not change a regional shared setting implicitly; it provides Callback Handler CloudWatch logs with the project's retention and API method metrics. Enabling REST access/execution logs and deciding ownership of the regional logging role remain explicit observability-stage work. Existing HTTP API access logs are unchanged.

[AWS REST API logging prerequisite](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html)

## Artifact and review

Publish an immutable ARM64 ZIP from the approved Callback Handler commit. Supply `callback_handler_artifact_key` and `callback_handler_source_code_hash` in ignored `stacks/core/terraform.tfvars`. Both the request URL change and new callback resources must appear in the saved core plan for review before applying it.

The callback Lambda handler string is:

```text
AsyncCallback.Handler::MarcondesOliveira.AsyncTransactions.CallbackHandler.Host.CallbackFunction::FunctionHandler
```

## Manual validation after deployment

1. Create a **new** main API transaction using Bruno with a new idempotency key and correlation UUID. Wait for the final status through GET. The new operation should contain the deployed callback URL in the simulator table.
2. Confirm normal destination → `SUCCEEDED` / `APPROVED`, `reject-` prefix → `REJECTED` / `DESTINATION_REJECTED`, and `fail-` prefix → `FAILED` / `PROCESSING_ERROR`. Use independent transaction IDs and keys.
3. Confirm the main table has the terminal result and a `CALLBACK#{eventId}` receipt, with matching processor and correlation IDs. Read handler logs for `Applied`.
4. POST the same callback to `callback_endpoint_url` through Bruno. Expect HTTP 202, a downstream `Duplicate` log and unchanged completion/update timestamps. Preserve the event ID and business data.
5. For a controlled conflict test, submit an otherwise valid callback reusing an event ID with changed result data. Expect HTTP 202 at the gateway, downstream handler failures and no transaction changes. After retries, inspect Failed Results. An async acknowledgement does not mean the handler accepted a state transition.
6. Test malformed/missing-field JSON at the gateway: expect a client validation error without SNS publication. Invalid timestamp semantics or transaction identities that pass schema validation are handled asynchronously by the Lambda.

Inspect queue messages without deleting them during diagnosis. Manual Lambda console tests are documented in the application repository; direct invocation does not exercise SNS/SQS delivery, retries or DLQ redrive. No Swagger UI is hosted by this direct-service endpoint; use Bruno for its HTTP tests.

The initial deployment and deployment-trigger stability correction were approved and applied; component checks passed and the refreshed Terraform plan has no changes. Manual runtime tests confirmed successful completion, duplicate handling and three conflict-processing attempts followed by DLQ redrive, while preserving the original terminal result. See [Stage 10 evidence](stage-10-evidence.md). Stage 11 will consolidate broader end-to-end scenario evidence.
