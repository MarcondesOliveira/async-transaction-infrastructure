# External simulator stack

Independent hosting for the External Transaction Processor Simulator. It has a separate state from `stacks/core`, so the simulated dependency can be deployed or destroyed independently.

## Resources

- API Gateway HTTP API with access logs and throttling (5 requests/second, burst 10).
- API Lambda and callback-worker Lambda using `dotnet10`, `arm64`, 512 MB and a 30-second timeout.
- One immutable ZIP shared by both functions, with different entry points and IAM roles.
- DynamoDB on-demand table with `PK`/`SK`, encryption, `NEW_IMAGE` Stream and TTL on `expiresAt`.
- Stream event-source mapping filtered to `INSERT + PROCESSOR_OPERATION + ACCEPTED`, batch size 1.
- SQS failure destination for exhausted callback invocation metadata, encrypted and retained for 14 days.
- Three CloudWatch log groups with seven-day retention by default.

These are 17 managed resources. There is no VPC, NAT Gateway or always-running compute. The simulator runtime roles have no permissions on the core transaction table, queues or topic. It shares only the bootstrap artifact bucket and state bucket, using its own state key.

## Prepare and review

Copy `backend.hcl.example` to the ignored local `backend.hcl`. Set the bucket to the bootstrap `terraform_state_bucket` output, keeping the distinct `external-simulator.tfstate` key. Never reuse the core state key.

Publish the simulator ZIP from its committed source using this immutable key:

```text
external-transaction-processor-simulator/<git-sha>/external-transaction-processor-simulator.zip
```

Copy `terraform.tfvars.example` to the ignored `terraform.tfvars`, then supply the real object key and its Base64 SHA-256. Both functions must reference the same package. Placeholder defaults permit configuration review but cannot be deployed successfully.

From the infrastructure repository root:

```sh
terraform -chdir=stacks/external-simulator init -backend-config=backend.hcl
terraform -chdir=stacks/external-simulator fmt -check
terraform -chdir=stacks/external-simulator validate
terraform -chdir=stacks/external-simulator plan -out=external-simulator.tfplan
```

Review the saved plan before applying it. This stage initially leaves `stacks/core` unchanged. After simulator verification, a separately reviewed core plan will set `external_processor_base_url` and deploy the corrected Request Handler artifact from commit `eb2e105` or a later approved commit. The final callback URL remains pending the callback pipeline stage.

For configuration-only validation before backend setup, use `init -backend=false` and `validate`. These do not produce an AWS deployment plan or verify the artifact exists.

## Retry behavior

The worker waits two seconds by default, then calls the supplied HTTPS endpoint with a ten-second HTTP timeout. Processing delay is limited to ten seconds to leave room within the 30-second Lambda timeout.

The Stream mapping uses two retries after an invocation failure and a one-hour maximum record age. Failures before invocation, such as throttling, can retry until the age limit. `TRIM_HORIZON` processes available records when the mapping first starts; the filter excludes updates and TTL removals.

The failure queue contains invocation and Stream sequence metadata, **not the original callback body**. Inspect it together with the worker's logs and retrieve the original Stream record before Stream retention expires (24 hours). The queue's 14-day retention does not extend Stream retention. Reprocessing is manual; this stack does not consume this failure queue. See [AWS Stream error handling](https://docs.aws.amazon.com/lambda/latest/dg/services-dynamodb-errors.html).

`worker_trigger_enabled = false` can temporarily disable automatic callback delivery through a reviewed Terraform change. It does not pause the age or retention clocks. A later enable can resume available records, subject to those limits.

## Manual test after deployment

1. Open the `simulator_swagger_url` output to inspect the API and call `/health`.
2. In Bruno, submit the POST body and both required custom headers documented in the simulator repository's README. Use `simulator_api_url` as the base URL.
3. Confirm `202 Accepted` and a single operation in `operations_table_name`.
4. Repeat the exact request/key and confirm the original processor transaction ID is returned. Change the body while keeping the key and confirm `409`.
5. Use new transaction IDs and keys for normal, `reject-` and `fail-` destination accounts.
6. With a controlled reachable callback endpoint, inspect its received body and the worker logs for the expected terminal status. Until an endpoint exists, a reserved `.invalid` callback intentionally exercises errors, bounded retries and the failure destination; it does not validate successful delivery.

The deployed Stream mapping invokes the worker automatically; a second manual Lambda invocation would send another callback. Successful API acceptance alone is not proof of callback delivery.

## Cost, exposure and cleanup

TTL defaults to 24 hours for the entire simulator operation, including idempotency. Physical deletion is asynchronous. The HTTP endpoint currently has no caller authentication and accepts caller-supplied HTTPS callback URLs; use controlled demonstrations and destinations. Throttling limits traffic but is not authentication.

After demonstration, destroy this stack and core before destroying bootstrap storage. Review each destroy plan. The failure queue, operations table and log groups belong to this stack and are deleted with it:

```sh
terraform -chdir=stacks/external-simulator plan -destroy -out=external-simulator-destroy.tfplan
terraform -chdir=stacks/external-simulator apply external-simulator-destroy.tfplan
```

Application artifacts and remote state are held in bootstrap storage and have a separate cleanup lifecycle.
