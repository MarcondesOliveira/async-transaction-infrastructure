# Stage 10 — Callback pipeline

Date: `2026-10-28`  
Region: `us-east-1`  
Environment: `dev`

## Prepared artifact

- Callback Handler commit: `40c796bbdc75a364c7d8ba997020c667490ce21c`.
- Framework-dependent Release publish for `net10.0` / `linux-arm64` completed successfully.
- S3 key: `async-transaction-callback-handler/40c796bbdc75a364c7d8ba997020c667490ce21c/async-transaction-callback-handler.zip`.
- ZIP SHA-256: `3c5db4c0b4c08bb6f2005d63df0f3279ae94dded93a866410b4b3b6ed8dfe69b`.
- Lambda/S3 checksum: `PF20wLTAi7byAF1j3w8yea6U3e2TqGZBC0s7btjf5ps=`.
- Conditional S3 upload succeeded, with matching checksum, AES256 encryption and a version ID.

## Terraform review

Configuration validation, formatting and whitespace checks passed. The real AWS plan saved in ignored `stacks/core/callback-pipeline.tfplan` contains **27 to add, 1 to change, 0 to destroy**:

| Group | New resources |
| --- | --- |
| Regional REST callback API, resources, model, validator, method, integration, responses, deployment, stage and settings | 14 |
| API Gateway and Callback Handler IAM roles/policies | 4 |
| SNS topic and raw SQS subscription | 2 |
| Processing Results, Failed Results, source restriction and SNS queue policy | 4 |
| Callback Handler Lambda, log group and SQS mapping | 3 |

The single existing-resource update changes the Request Handler's `Callback__Url` from the reserved `.invalid` endpoint to the generated callback URL. Its code, the Transaction API, existing transaction table, request queues and EventBridge Pipe are unchanged.

REST API is used for direct SNS publication and schema validation because SNS Publish is absent from HTTP API integration subtypes. The acknowledgement is simplified to `202 {"accepted":true}` and documented in the project contract. No extra application Lambda is introduced for HTTP ingestion.

The regional API Gateway account logging role was read and found unset. This configuration does not modify that shared account setting; Callback Handler logs and REST method metrics are included. Regional REST access/execution logging setup remains for the observability stage.

## Deployment and component checks

The owner approved the saved plan; apply completed with **27 added, 1 changed, 0 destroyed**.

- Callback endpoint: `https://bpdk2fl7h9.execute-api.us-east-1.amazonaws.com/dev/callbacks/transactions`.
- Callback Handler: `Active`, update `Successful`, expected package checksum confirmed.
- SQS mapping: `e9e0c889-94fb-4b31-b3ca-3527ba867194`, `Enabled`, batch size 5, `ReportBatchItemFailures`.
- SNS subscription: confirmed (`PendingConfirmation = false`), `RawMessageDelivery = true`.

## Post-apply plan finding

The subsequent read-only plan returned exit code 2 and proposed replacing only the API deployment snapshot and updating the stage (`1 add, 1 change, 1 destroy`). No follow-up apply was run. The deployment trigger hashes full resource objects, including optional/computed fields that the provider normalizes from null to empty collections when re-reading. This changed the trigger hash without a functional API configuration change. The existing REST API, queues and Lambdas are not scheduled for replacement.

After joint review and authorization, the trigger was changed to hash only explicit configuration fields and resource identities. The correction plan affected only the deployment snapshot and stage reference. Apply created snapshot `sjepf0`, pointed the existing stage to it, then removed snapshot `ncjiih`. No business data or runtime component was deleted. The subsequent full refreshed plan returned **no changes**, confirming stable deployment hashing.

## Manual validation scope

Successful reception, duplicate handling and controlled conflict/retry/redrive tests are recorded below. Broader scenario coverage and gateway validation-error tests remain for the subsequent end-to-end validation stage. Previous simulator operations continue to target their stored `.invalid` URL; end-to-end tests must create new transactions after deployment.

See [callback pipeline guide](callback-pipeline.md) for the manual sequence and infrastructure boundaries.

## First successful end-to-end manual test

The owner created transaction `26b3b2f1-e6ed-437a-96a1-4239a3bfb8a7` through the main API and supplied its initial `PENDING` response. A subsequent public GET returned HTTP 200 with terminal status `SUCCEEDED` and result `APPROVED` / `Transaction processed successfully`.

- Correlation ID: `cccccccc-dddd-4eee-8fff-aaaaaaaaaaaa`.
- Processor transaction ID: `e5aaa427-cb87-4eb0-b649-0909c2728af9`.
- Callback event ID: `d0a07a80-f36a-4d78-98e4-cb4a93799e8b`.
- Created at: `2026-10-28T23:59:01.0464304+00:00`.
- Callback occurred/completed at: `2026-10-28T23:59:12.0018009+00:00`.
- Applied/updated at: `2026-10-28T23:59:14.0539845+00:00`.
- Callback Handler log: `Applied` for the matching event, transaction and correlation IDs.

Consistent DynamoDB reads confirmed the matching `CALLBACK#d0a07a80-f36a-4d78-98e4-cb4a93799e8b` receipt, processed timestamp and TTL, and the simulator operation containing the deployed callback URL and the same processor/event IDs. This validates a successful result through the direct callback publication, SNS, raw SQS delivery and transactional handler in AWS. Duplicate/conflict and callback-queue retry/redrive tests remain pending.

## Manual duplicate callback

The owner reposted the original event `d0a07a80-f36a-4d78-98e4-cb4a93799e8b` through the callback endpoint in Bruno. The supplied screenshot confirms HTTP 202 with `{"accepted":true}`. The subsequent GET supplied by the owner preserved `SUCCEEDED`, `updatedAt = 2026-10-28T23:59:14.0539845+00:00` and `completedAt = 2026-10-28T23:59:12.0018009+00:00`.

CloudWatch confirms `Duplicate` at `2026-10-29T00:03:18.047Z` for the same event, transaction and correlation IDs (request `1a31c6e2-1a60-5ad8-b27b-a5be9514467a`). End-to-end duplicate handling is validated; conflict and callback retry/redrive remain pending.

## Controlled conflict — retry and redrive validated

The owner posted the same callback event ID with `FAILED` / `PROCESSING_ERROR` and message `Controlled conflict test`, receiving HTTP 202. The processing record is SQS message `93efcc8e-8408-4ea2-a75f-87140d8e6e68`.

CloudWatch recorded `CallbackConflictException: Event ID was reused with different callback data.` at `2026-10-29T00:06:40.205Z` and `2026-10-29T00:08:10.089Z`, approximately 90 seconds apart. The public GET still shows the original `SUCCEEDED` result and unchanged update/completion timestamps. At initial inspection, Processing Results had approximately one in-flight message and Failed Results had none. The remaining retry and redrive are being observed; they are not yet claimed as validated.

The third and last handler attempt was logged at `2026-10-29T00:09:40.119Z`, again about 90 seconds later. After visibility expired, Failed Results contained one visible message and Processing Results reported zero visible and zero in flight. A diagnostic receive with zero visibility confirmed the exact message ID `93efcc8e-8408-4ea2-a75f-87140d8e6e68`, original event/transaction IDs, changed `FAILED` status and `Controlled conflict test` body. No message was deleted or redriven. Diagnostic receives affect the SQS receive counter; the three application attempts are established by CloudWatch timestamps, not that counter.

A final public GET confirmed the original `SUCCEEDED` / `APPROVED` result and unchanged `updatedAt` / `completedAt`. The conflict was preserved for investigation in the DLQ without overwriting the business result. Stage 10 implementation and its delivery/retry/redrive acceptance checks are complete; owner review and infrastructure commit/push remain pending.
