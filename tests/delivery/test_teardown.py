import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[2] / ".github/scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("teardown", SCRIPTS / "teardown.py")
teardown = importlib.util.module_from_spec(spec)
spec.loader.exec_module(teardown)


class TeardownTests(unittest.TestCase):
    def setUp(self):
        self.config = {"project_name": "example", "environment": "dev"}

    def plan(self, kind="aws_sqs_queue", actions=None, before=None):
        return {"resource_changes": [{"mode": "managed", "type": kind,
                "address": kind + ".example", "change": {"actions": actions or ["delete"],
                "before": before or {}}}]}

    def test_plan_does_not_require_destroy_confirmation_or_freeze(self):
        teardown.intent("plan", "core", self.config, "", "false")

    def test_destroy_requires_exact_confirmation_and_freeze(self):
        teardown.intent("destroy", "core", self.config, "DESTROY example-dev", "true")
        for confirmation, enabled in [("DESTROY", "true"), ("DESTROY example-dev", "false"),
                                      ("DESTROY another-dev", "true")]:
            with self.subTest(confirmation=confirmation, enabled=enabled), self.assertRaises(ValueError):
                teardown.intent("destroy", "core", self.config, confirmation, enabled)

    def test_unknown_operations_stacks_and_invalid_targets_rejected(self):
        for operation, stack, config in [("apply", "core", self.config),
                                         ("destroy", "bootstrap", self.config),
                                         ("plan", "core", {"project_name": "*", "environment": "dev"})]:
            with self.subTest(stack=stack, operation=operation), self.assertRaises(ValueError):
                teardown.intent(operation, stack, config, "DESTROY example-dev", "true")

    def test_runtime_deletion_allowed(self):
        self.assertEqual(teardown.check_plan(self.plan(), self.config), ["aws_sqs_queue.example"])

    def test_create_update_replacement_and_forget_rejected(self):
        for actions in [["create"], ["update"], ["delete", "create"], ["forget"]]:
            with self.subTest(actions=actions), self.assertRaises(ValueError):
                teardown.check_plan(self.plan(actions=actions), self.config)

    def test_bootstrap_buckets_and_arbitrary_iam_rejected(self):
        for kind, before in [("aws_s3_bucket", {}), ("aws_iam_policy", {}),
                             ("aws_iam_role", {"name": "example-dev-github-terraform"}),
                             ("aws_iam_role", {"name": "other-dev-transaction-api-lambda"}),
                             ("aws_iam_role_policy", {"role": "example-dev-github-destroy"})]:
            with self.subTest(kind=kind, before=before), self.assertRaises(ValueError):
                teardown.check_plan(self.plan(kind, before=before), self.config)

    def test_only_runtime_roles_and_their_inline_policies_allowed(self):
        for suffix in teardown.ROLE_SUFFIXES:
            role = "example-dev-" + suffix
            teardown.check_plan(self.plan("aws_iam_role", before={"name": role}), self.config)
            teardown.check_plan(self.plan("aws_iam_role_policy", before={"role": role}), self.config)

    def test_noop_and_data_reads_are_not_deletions(self):
        self.assertEqual(teardown.check_plan(self.plan(actions=["no-op"]), self.config), [])
        plan = self.plan(actions=["read"])
        plan["resource_changes"][0]["mode"] = "data"
        self.assertEqual(teardown.check_plan(plan, self.config), [])

    def test_workflow_is_manual_default_plan_and_ordered(self):
        text = (SCRIPTS.parent / "workflows/destroy.yml").read_text()
        self.assertIn("on:\n  workflow_dispatch:", text)
        self.assertNotIn("workflow_run:", text)
        self.assertNotIn("  push:", text)
        self.assertIn("default: plan", text)
        self.assertIn("  core:\n    needs: simulator", text)

    def test_helper_reuses_stack_concurrency_and_separate_destroy_role(self):
        text = (SCRIPTS.parent / "workflows/destroy-stack.yml").read_text()
        self.assertIn("on:\n  workflow_call:", text)
        self.assertIn("group: terraform-${{ inputs.stack }}", text)
        self.assertIn("vars.AWS_DESTROY_ROLE_ARN", text)
        self.assertIn("github.event_name == 'workflow_dispatch'", text)

    def test_normal_deliveries_have_visible_teardown_freeze(self):
        for name in ["deploy.yml", "infrastructure.yml"]:
            text = (SCRIPTS.parent / "workflows" / name).read_text()
            self.assertIn('test "$TEARDOWN_ENABLED" != true', text)
            self.assertIn("exit 1", text)


if __name__ == "__main__":
    unittest.main()
