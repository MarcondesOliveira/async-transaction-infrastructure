# Final lab teardown — prepare in stage 13, execute only in stage 15

No resource should be deleted during CI/CD preparation or documentation. This
workflow is manual-only. Its default `plan` operation previews deletions using
the existing deploy role and never applies. `destroy` uses a separate, optional
role which has not been provisioned by preparing these files.

## Protection boundaries

- Supply the full reviewed current main SHA. Preflight requires that SHA and a
  successful Infrastructure CI for it. No push, PR, schedule or service can
  automatically start this workflow.
- `destroy` requires infrastructure variable `TEARDOWN_ENABLED=true` and exact
  confirmation `DESTROY <project>-<environment>`, derived from the existing config.
  Delivery workflows fail visibly before AWS authentication while frozen.
- Simulator must succeed before core starts, via explicit job dependencies.
  Both use the same per-stack concurrency groups as deploy plus backend locks.
- Generate a fresh `plan -destroy`, reject anything except deletions of known
  runtime types and the seven exact existing runtime roles/inline policies, then
  apply that exact saved plan. No direct unreviewed `terraform destroy` command.
- Check each stack state has no remaining managed resources. This does not
  replace the final AWS inventory/cost check. No smoke POST follows deletion.
- Raw state/plans stay in private runner temporary files, not downloadable
  artifacts. Resource addresses to be deleted appear in logs/summary.

The ordinary deploy role remains unable to remove IAM. `enable_destroy_role`
defaults to false in bootstrap. Enabling it owner-side creates a separate role
and three inline policies: project runtime read/delete actions, removal of only
the seven runtime roles, and state/lock access plus artifact read. It has no IAM
create/update/grant permissions, bucket teardown, bootstrap-role deletion or
account-wide administrator policy. Existing API IDs/mapping UUIDs still bound
its runtime scope. No new permissions are attached to the routine deploy role.

OIDC trust is the infrastructure repository's verified main subject and STS
audience, like the existing infrastructure role. Workflow confirmations are not
a second independent security boundary against someone allowed to rewrite main.
Provision the privileged teardown role only for the final window, then remove
it with bootstrap cleanup. No additional GitHub environment/reviewer feature is
assumed to exist in this private lab repository.

## Stage 15 owner procedure — not to run now

1. Finish portfolio evidence/documentation. Preserve any data needed before
   deleting tables, queues and logs; their deletion is destructive. Stop manual
   traffic and producers. Do not treat retained S3 state versions as data backups.
2. Disable automatic delivery workflows in the four service repositories and
   `Deliver infrastructure`; set infrastructure `TEARDOWN_ENABLED=true`.
   Wait for all running/queued deliveries to finish or be deliberately cancelled.
   The preflight checks recent active infrastructure delivery runs too, but that
   check is not a substitute for inspecting all queues and stopping producers.
   Never reset the freeze while teardown is incomplete.
3. As owner, set `enable_destroy_role=true` in ignored bootstrap tfvars, review a
   bootstrap plan, approve it and apply the saved plan. Configure infrastructure
   variable `AWS_DESTROY_ROLE_ARN` from its output; never put the ARN/account in
   tracked source. Persist the enabled value until final cleanup; a later
   bootstrap apply with the default false would remove this role.
4. Open **Final lab teardown**, select main, supply its reviewed full SHA and
   choose **plan** first. Inspect the resource-address list for both stacks.
   Preview uses the read permissions of the existing deploy role.
5. Only after explicit final owner approval, run it again with **destroy**,
   the reviewed current main SHA and the exact confirmation phrase. A new saved
   deletion plan is generated in that execution; it is not the previous preview's
   binary plan. Its deletion-only guard must pass before apply. Role runtime
   permissions and actual deletion behavior remain untested until this authorized
   final execution; don't claim otherwise from dry-run success.
6. Inspect both jobs and inventory AWS. A partial failure is not rolled back or
   silently retried. Keep the freeze, inspect errors/state and authorize recovery.
   Core does not start if simulator fails. Repeating teardown uses the remaining
   state; never switch back to deploy to "fix" a partially destroyed stack.
7. Bootstrap is a separate privileged owner step, LAST: preserve needed state
   evidence, review bucket objects/versions and bootstrap deletion plan, explicitly
   approve cleanup, remove project buckets, budget and GitHub roles including the
   optional destroy role. Do not delete the shared OIDC provider (it is a data
   source, not owned by this lab). This runtime workflow does not purge buckets.
   However, bootstrap declares `force_destroy=true` for both project buckets:
   an owner-approved bootstrap destroy can purge their objects/versions. Preserve
   required evidence first; versioning does not protect from that apply.
8. Remove temporary cross-repository token/secrets, revoke the token, inventory
   residual resources/costs and record actual results in the checklist. Leave
   automated delivery disabled after closing the lab so a push cannot recreate it.

## Validation status

Preparation validates tests, syntax and Terraform plans only. It does not prove
resource deletion or grant permission to execute stage 15. Provisioning the
optional role, configuring its GitHub variable and the destructive execution
require explicit owner approval at that final stage.
