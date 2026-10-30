import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[2] / ".github/scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("infrastructure", SCRIPTS / "infrastructure.py")
infra = importlib.util.module_from_spec(spec)
spec.loader.exec_module(infra)


class InfrastructureTests(unittest.TestCase):
    def setUp(self):
        self.config = {"aws_region": "us-east-1", "project_name": "example", "environment": "dev"}
        self.settings = infra.load(SCRIPTS.parent / "config/core.json")
        self.state = {"values": {"root_module": {"resources": [
            {"address": address, "values": {"s3_key": prefix + "/current.zip",
             "source_code_hash": prefix + "-hash", "function_name": prefix + "-function"}}
            for prefix, address in infra.CORE.items()
        ]}}}

    def plan(self, resource_type="aws_cloudwatch_log_group", actions=None, before=None, after=None):
        return {"resource_changes": [{"address": resource_type + ".example", "type": resource_type,
                "mode": "managed", "change": {"actions": actions or ["update"],
                "before": before or {}, "after": after or {}, "after_unknown": {}}}]}

    def test_settings_override_snapshots_without_identity_changes(self):
        base = dict(self.config, log_retention_days=30)
        result = infra.configuration("core", base, self.settings)
        self.assertEqual(result["log_retention_days"], 7)
        self.assertEqual(result["project_name"], "example")

    def test_no_package_or_identifiers_in_tracked_settings(self):
        for key in ["lambda_artifact_key", "aws_region", "external_processor_base_url"]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                infra.configuration("core", self.config, dict(self.settings, **{key: "bad"}))

    def test_settings_types_and_missing_keys_rejected(self):
        bad = dict(self.settings, log_retention_days="7")
        with self.assertRaises(ValueError):
            infra.configuration("core", self.config, bad)
        bad = dict(self.settings)
        bad.pop("log_retention_days")
        with self.assertRaises(ValueError):
            infra.configuration("core", self.config, bad)

    def test_rejects_pinned_secret_packages(self):
        with self.assertRaises(ValueError):
            infra.configuration("core", dict(self.config, lambda_artifact_key="old"), self.settings)

    def test_preserves_all_core_packages_from_current_state(self):
        values, contexts = infra.prepare("core", self.state, self.config)
        for prefix in infra.CORE:
            self.assertEqual(values[prefix + "_artifact_key"], prefix + "/current.zip")
        self.assertEqual(len(contexts), 3)

    def test_missing_existing_function_rejected(self):
        self.state["values"]["root_module"]["resources"].pop()
        with self.assertRaises(ValueError):
            infra.prepare("core", self.state, self.config)

    def test_simulator_pair_preserved_and_mismatch_rejected(self):
        state = {"values": {"root_module": {"resources": [
            {"address": "aws_lambda_function." + name, "values": {
                "s3_key": "current.zip", "source_code_hash": "hash", "function_name": name}}
            for name in ["api", "worker"]]}}}
        values, contexts = infra.prepare("external-simulator", state, self.config)
        self.assertEqual(values["simulator_artifact_key"], "current.zip")
        self.assertEqual(contexts[0]["functions"], ["api", "worker"])
        state["values"]["root_module"]["resources"][1]["values"]["s3_key"] = "old.zip"
        with self.assertRaises(ValueError):
            infra.prepare("external-simulator", state, self.config)

    def test_config_update_and_supported_create_allowed(self):
        self.assertEqual(len(infra.check_plan(self.plan())), 1)
        self.assertEqual(len(infra.check_plan(self.plan("aws_sqs_queue", ["create"]))), 1)

    def test_deletes_and_replacements_blocked(self):
        for actions in [["delete"], ["delete", "create"], ["create", "delete"]]:
            with self.subTest(actions=actions), self.assertRaises(ValueError):
                infra.check_plan(self.plan(actions=actions))

    def test_iam_and_unsupported_changes_blocked(self):
        for resource_type in ["aws_iam_role", "aws_iam_role_policy", "aws_iam_policy", "aws_s3_bucket"]:
            with self.subTest(resource_type=resource_type), self.assertRaises(ValueError):
                infra.check_plan(self.plan(resource_type))

    def test_lambda_configuration_allowed_but_packages_blocked(self):
        before = {"s3_key": "current.zip", "source_code_hash": "hash", "timeout": 15}
        after = dict(before, timeout=16)
        self.assertEqual(len(infra.check_plan(self.plan("aws_lambda_function", before=before, after=after))), 1)
        for field in infra.PACKAGE_FIELDS:
            with self.subTest(field=field), self.assertRaises(ValueError):
                infra.check_plan(self.plan("aws_lambda_function", before=before, after=dict(after, **{field: "changed"})))
        with self.assertRaises(ValueError):
            infra.check_plan(self.plan("aws_lambda_function", ["create"]))

    def test_unknown_package_value_blocked(self):
        plan = self.plan("aws_lambda_function")
        plan["resource_changes"][0]["change"]["after_unknown"] = {"source_code_hash": True}
        with self.assertRaises(ValueError):
            infra.check_plan(plan)

    def test_noop_iam_and_data_reads_allowed(self):
        self.assertEqual(infra.check_plan(self.plan("aws_iam_role", ["no-op"])), [])
        plan = self.plan("aws_iam_policy_document", ["read"])
        plan["resource_changes"][0]["mode"] = "data"
        self.assertEqual(infra.check_plan(plan), [])


if __name__ == "__main__":
    unittest.main()
