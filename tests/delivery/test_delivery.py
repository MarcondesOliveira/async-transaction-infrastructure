import base64
import copy
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "delivery", Path(__file__).resolve().parents[2] / ".github/scripts/delivery.py"
)
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.commit = "a" * 40
        self.digest = base64.b64encode(bytes(32)).decode()
        self.service = "async-transaction-api"
        self.config = {"aws_region": "us-east-1", "project_name": "example", "environment": "dev"}
        self.state = {"values": {"root_module": {"resources": [
            {"address": address, "values": {"s3_key": prefix + "/existing.zip",
             "source_code_hash": self.digest, "function_name": prefix + "-function"}}
            for prefix, address in delivery.CORE.items()
        ]}}}
        self.manifest = {"service": self.service, "commit": self.commit,
                         "package": self.service + ".zip",
                         "s3Key": f"{self.service}/{self.commit}/{self.service}.zip",
                         "runtime": "dotnet10", "architecture": "arm64",
                         "selfContained": False, "sourceCodeHash": self.digest, "sha256": "0" * 64}
        self.head = {"ChecksumSHA256": self.digest, "ServerSideEncryption": "AES256",
                     "Metadata": {"source-commit": self.commit, "service": self.service}}

    def prepare(self):
        return delivery.prepare(self.state, self.config, self.manifest,
                                self.head, self.service, self.commit)

    def plan(self, address="aws_lambda_function.transaction_api", actions=None, fields=None):
        before = {"s3_key": "old.zip", "source_code_hash": self.digest,
                  "timeout": 30, "last_modified": "old"}
        after = dict(before, s3_key="new.zip", last_modified=None)
        after.update(fields or {})
        return {"resource_changes": [{"address": address, "mode": "managed", "change": {
            "actions": actions or ["update"], "before": before, "after": after,
            "after_unknown": {"last_modified": True}}}]}

    def test_preserves_other_services_from_latest_state(self):
        values, context = self.prepare()
        self.assertEqual(values["lambda_artifact_key"], self.manifest["s3Key"])
        self.assertEqual(values["request_handler_artifact_key"], "request_handler/existing.zip")
        self.assertEqual(values["callback_handler_artifact_key"], "callback_handler/existing.zip")
        self.assertEqual(context["functions"], ["lambda-function"])

    def test_rejects_stale_config_artifact_overrides(self):
        self.config["request_handler_artifact_key"] = "stale.zip"
        with self.assertRaises(ValueError):
            self.prepare()

    def test_rejects_wrong_source_commit(self):
        self.manifest["commit"] = "b" * 40
        with self.assertRaises(ValueError):
            self.prepare()

    def test_rejects_wrong_target(self):
        self.manifest["architecture"] = "x86_64"
        with self.assertRaises(ValueError):
            self.prepare()

    def test_rejects_s3_checksum_mismatch(self):
        self.head["ChecksumSHA256"] = "wrong"
        with self.assertRaises(ValueError):
            self.prepare()

    def test_rejects_missing_existing_function(self):
        self.state["values"]["root_module"]["resources"].pop()
        with self.assertRaises(ValueError):
            self.prepare()

    def test_allows_only_code_and_computed_timestamp(self):
        self.assertEqual(delivery.check_plan(self.plan(), self.service),
                         ["aws_lambda_function.transaction_api"])

    def test_rejects_other_service_update(self):
        with self.assertRaises(ValueError):
            delivery.check_plan(self.plan("aws_lambda_function.request_handler"), self.service)

    def test_rejects_resource_deletion(self):
        with self.assertRaises(ValueError):
            delivery.check_plan(self.plan(actions=["delete"]), self.service)

    def test_rejects_replacement(self):
        with self.assertRaises(ValueError):
            delivery.check_plan(self.plan(actions=["delete", "create"]), self.service)

    def test_rejects_configuration_change(self):
        with self.assertRaises(ValueError):
            delivery.check_plan(self.plan(fields={"timeout": 900}), self.service)

    def test_noop_allowed(self):
        self.assertEqual(delivery.check_plan({"resource_changes": []}, self.service), [])

    def test_simulator_preserves_two_function_contract(self):
        self.service = "external-transaction-processor-simulator"
        self.manifest.update(service=self.service, package=self.service + ".zip",
                             s3Key=f"{self.service}/{self.commit}/{self.service}.zip")
        self.head["Metadata"]["service"] = self.service
        self.state["values"]["root_module"]["resources"] = [
            {"address": address, "values": {"s3_key": "existing.zip", "source_code_hash": self.digest,
             "function_name": name}}
            for address, name in [("aws_lambda_function.api", "api"),
                                  ("aws_lambda_function.worker", "worker")]
        ]
        _, context = self.prepare()
        self.assertEqual(context["functions"], ["api", "worker"])

    def test_rejects_mismatched_simulator_baseline(self):
        self.service = "external-transaction-processor-simulator"
        self.manifest.update(service=self.service, package=self.service + ".zip",
                             s3Key=f"{self.service}/{self.commit}/{self.service}.zip")
        self.head["Metadata"]["service"] = self.service
        self.state["values"]["root_module"]["resources"] = [
            {"address": address, "values": {"s3_key": key, "source_code_hash": self.digest,
             "function_name": "example"}}
            for address, key in [("aws_lambda_function.api", "api.zip"),
                                 ("aws_lambda_function.worker", "worker.zip")]
        ]
        with self.assertRaises(ValueError):
            self.prepare()

    def test_verifies_actual_deployed_hash(self):
        context = {"functions": ["example"], "sourceCodeHash": self.digest}
        actual = [{"FunctionName": "example", "State": "Active", "LastUpdateStatus": "Successful",
                   "CodeSha256": self.digest, "Runtime": "dotnet10", "Architectures": ["arm64"]}]
        delivery.verify(context, actual)
        wrong = copy.deepcopy(actual)
        wrong[0]["CodeSha256"] = "old"
        with self.assertRaises(ValueError):
            delivery.verify(context, wrong)


if __name__ == "__main__":
    unittest.main()
