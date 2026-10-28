# Stage 8 — External processor simulator

Date: `2026-10-28`  
Region: `us-east-1`  
Environment: `dev`

## Deployment preparation

- Application commit: `fc91ad7202d2eae7f12df5e060fc0a56b2cfeefe`.
- Infrastructure baseline: `8aa340b377ac536e2d1251b97980d5e022991775`.
- Release publish completed for `net10.0`, `linux-arm64`, framework-dependent.
- S3 key: `external-transaction-processor-simulator/fc91ad7202d2eae7f12df5e060fc0a56b2cfeefe/external-transaction-processor-simulator.zip`.
- ZIP SHA-256: `62c343b03381ec9a5639f674167e0c21bf50ac18bd78b574151dd738d84f500e`.
- Lambda source hash / S3 SHA-256 checksum: `YsNDsDOB7JpWOfZ0Fn4MIb9QrBi9eLV0FR3XONhPUA4=`.
- Upload used a conditional write to avoid overwriting an existing commit key. S3 returned the matching checksum, AES256 encryption and a version ID.
- Backend initialized with the separate key `async-transaction-processing/dev/external-simulator.tfstate` and S3 locking.
- Local backend and deployment variable files are excluded from Git.

## Reviewed plan scope

The real AWS plan completed successfully: **17 to add, 0 to change, 0 to destroy**. It is saved locally as `stacks/external-simulator/external-simulator.tfplan` and excluded from Git.

| Resource group | Count |
| --- | --- |
| DynamoDB operations table | 1 |
| Callback failure SQS queue | 1 |
| Lambda / API Gateway log groups | 3 |
| IAM roles and inline policies | 4 |
| API and worker Lambda functions | 2 |
| DynamoDB Stream event-source mapping | 1 |
| HTTP API, integration, route and stage | 4 |
| API Gateway Lambda permission | 1 |

Both functions reference the same published commit and checksum, with managed `dotnet10`, `arm64`, 512 MB and 30-second timeouts. The table uses on-demand capacity, encryption, a `NEW_IMAGE` Stream and TTL. The worker receives one accepted operation per batch, with two function-error retries, a one-hour maximum record age and an SQS metadata failure destination.

## Deployment and initial checks

The approved saved plan was applied: **17 added, 0 changed, 0 destroyed**.

- API URL: `https://q1no4iz708.execute-api.us-east-1.amazonaws.com`.
- Swagger UI: `https://q1no4iz708.execute-api.us-east-1.amazonaws.com/swagger/index.html`.
- Operations table: `async-transaction-processing-dev-external-simulator-operations`.
- Worker event-source mapping: `08c405c7-632a-4e2b-84d5-f6d0ab206f54`.
- Health check returned HTTP `200` with `{"status":"healthy"}`.
- Stream mapping is `Enabled`, with two retries and maximum record age of 3600 seconds. No records had been processed at inspection time.
- Post-deployment Terraform plan returned no changes (exit code 0).

## Pending validation

Manual POST acceptance/idempotency tests, real DynamoDB persistence and worker delivery/retry tests are pending. Core endpoint configuration and the deployed Request Handler artifact remain unchanged. The final callback pipeline is not yet available. A reserved `.invalid` callback can demonstrate bounded delivery failure; it cannot demonstrate successful callback reception.

## First manual POST — diagnosed failure

The owner's Bruno test returned HTTP 500. CloudWatch recorded `NullReferenceException` in `DynamoDbProcessorOperationRepository.ReadAsync`, line 58, during requests `2da33d69-6174-437f-8d54-0cbc0894d089` and `5cbf6568-b660-4cf0-a41c-2f211eda80e8`. The missing-item response contained a null `Item`; accessing `.Count` caused failure before the conditional insert.

After joint analysis and approval, the local simulator code was changed to treat null and empty items as absent. Two AWS-client-stub regression cases now cover absence, creation, original-operation replay and request-hash conflict. Build passed with zero warnings/errors; all 18 tests passed. This correction is pending owner commit/push and deployment; the currently deployed artifact remains `fc91ad7`.

## Correction package and update plan

- Owner push confirmed: `27ab4f664685ae1830c79760f15719811528a151`.
- S3 key: `external-transaction-processor-simulator/27ab4f664685ae1830c79760f15719811528a151/external-transaction-processor-simulator.zip`.
- ZIP SHA-256: `1f7db0c40ceaf008c7087029b09a8c4aecb27d0b3e834dd1665374d386459f22`.
- Lambda/S3 checksum: `H32wxAzq8AjHCHApsJqMSuyyfQs+g03RZlN004ZFnyI=`.
- Conditional S3 upload succeeded with matching SHA-256 and AES256 encryption.
- Saved local plan: `stacks/external-simulator/simulator-fix.tfplan`.
- Plan: **0 to add, 2 to change, 0 to destroy**. Only the two Lambda S3 keys and code hashes change; both share the simulator artifact.
- Approved plan applied successfully: **0 added, 2 changed, 0 destroyed**. Both Lambdas report `Active`, `LastUpdateStatus: Successful` and the expected corrected package checksum. Repeated manual POST remains pending.

## Manual POST after correction

The owner received an accepted operation at `2026-10-28T23:15:27.0032693+00:00`:

- Transaction ID: `11111111-2222-4333-8444-555555555555`.
- Processor transaction ID: `13b9626d-e7c0-440e-8701-cddd75391b01`.
- Idempotency key: `simulator-manual-0001`.
- Callback event ID: `b6d9d63a-7621-459e-946d-3aabced6cd28`.

A strongly consistent DynamoDB read confirmed the same identifiers, accepted timestamp, `ACCEPTED` status, `SUCCEEDED` simulated outcome, correlation ID and 24-hour TTL. The worker logs show three attempts at `23:15:31`, `23:15:34` and `23:15:36 UTC`, failing against the deliberately reserved `callback.invalid` destination. The failure queue reported approximately one visible message and zero in flight after retry exhaustion.

The owner then repeated the same POST in Bruno and supplied a screenshot confirming HTTP `202`, the same processor ID `13b9626d-e7c0-440e-8701-cddd75391b01` and the original accepted timestamp `2026-10-28T23:15:27.0032693+00:00`. Manual idempotent replay is validated.

The owner also changed the amount while keeping the same idempotency key and supplied the response body with code `IDEMPOTENCY_CONFLICT` and message `The idempotency key was already used with a different request.` This confirms manual conflict handling; the HTTP status was not included in the supplied response.

This validates persistence, Stream invocation, bounded callback failure, the idempotent replay response and conflicting-request handling. Successful callback reception remains pending.

## Core connection — prepared plan

- Corrected Request Handler commit: `eb2e1059726bbc22dc0535b319c513435cba080b`.
- S3 key: `async-transaction-request-handler/eb2e1059726bbc22dc0535b319c513435cba080b/async-transaction-request-handler.zip`.
- ZIP SHA-256: `e4ed6043dfee17b8de86cd35d077c7b70ea11b9de66e884d19d9b117e8cc62c9`.
- Lambda/S3 checksum: `5O1gQ9/uF7jehs010HfHtw6hG53mbohNGdmxF+jMYsk=`; conditional S3 upload confirmed it.
- Saved local core plan: `stacks/core/connect-simulator.tfplan`.
- Plan: **0 to add, 1 to change, 0 to destroy**. Only the Request Handler package/hash and `ExternalProcessor__BaseUrl` change.
- Target processor URL: `https://q1no4iz708.execute-api.us-east-1.amazonaws.com/`.
- Callback stays `https://callback.invalid/v1/callbacks/transactions` until its pipeline exists.

The approved core plan was applied: **0 added, 1 changed, 0 destroyed**. Request Handler is `Active`, with update `Successful`, the expected code checksum and the deployed simulator URL. The manual test through the main Transaction API is pending. The expected main transaction state after simulator acceptance is `PROCESSING`; final-state update remains dependent on the later callback pipeline.

## Integrated manual test through Transaction API

The owner created transaction `d24aca00-4d70-4248-b2d5-a4f8c0874a4b` through the main API. A public GET returned HTTP 200 with:

- Status: `PROCESSING`.
- Processor ID: `236b6a83-28e9-4132-977c-68976ceabebc`.
- Correlation ID: `bbbbbbbb-cccc-4ddd-8eee-ffffffffffff`.
- Created: `2026-10-28T23:24:45.9630609+00:00`.
- Updated: `2026-10-28T23:24:49.7611307+00:00`.

A consistent read from the independent simulator table confirmed that transaction, processor ID and correlation ID under key `transaction:d24aca00-4d70-4248-b2d5-a4f8c0874a4b:submit:v1`, accepted at `2026-10-28T23:24:49.5485657+00:00`. The stored simulated outcome is `SUCCEEDED` and callback event ID is `77fec5ee-534c-49ef-b3d2-18a17fa9acc9`.

Worker logs contain three callback delivery attempts for that transaction at `23:24:52`, `23:24:54` and `23:24:57 UTC`. The callback destination remains `.invalid`, so successful result delivery and terminal state transitions are not claimed. The main transaction remaining `PROCESSING` is expected at this stage.

Searching Request Handler logs for the transaction ID returned no entries. The successful integration is evidenced by matching records in both services and worker logs; improving successful-request correlation logging remains part of the observability stage.
