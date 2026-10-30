import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "smoke", Path(__file__).resolve().parents[2] / ".github/scripts/smoke.py"
)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class SmokeTests(unittest.TestCase):
    def setUp(self):
        self.transaction = "11111111-2222-4333-8444-555555555555"
        self.env = {"SMOKE_API_URL": "https://example.invalid", "GITHUB_RUN_ID": "123",
                    "GITHUB_RUN_ATTEMPT": "1"}

    def test_success_uses_synthetic_transaction_and_final_get(self):
        responses = [(200, {"status": "healthy"}), (202, {"transactionId": self.transaction}),
                     (200, {"status": "SUCCEEDED", "result": {"code": "APPROVED"}})]
        with patch.dict(os.environ, self.env), patch.object(smoke, "request", side_effect=responses) as req:
            smoke.main()
        self.assertEqual(req.call_args_list[1].args[2]["destination"]["accountId"], "portfolio-ci-smoke")
        self.assertTrue(req.call_args_list[-1].args[0].endswith(self.transaction))

    def test_terminal_failure_is_not_success(self):
        responses = [(200, {"status": "healthy"}), (202, {"transactionId": self.transaction}),
                     (200, {"status": "FAILED", "result": {"code": "ERROR"}})]
        with patch.dict(os.environ, self.env), patch.object(smoke, "request", side_effect=responses):
            with self.assertRaises(ValueError):
                smoke.main()

    def test_each_infrastructure_stack_uses_a_new_idempotency_key(self):
        keys = []
        for stack in ["core", "external-simulator"]:
            responses = [(200, {"status": "healthy"}), (202, {"transactionId": self.transaction}),
                         (200, {"status": "SUCCEEDED", "result": {"code": "APPROVED"}})]
            with patch.dict(os.environ, dict(self.env, STACK=stack), clear=True), patch.object(
                    smoke, "request", side_effect=responses) as req:
                smoke.main()
            keys.append(req.call_args_list[1].args[3]["Idempotency-Key"])
        self.assertNotEqual(keys[0], keys[1])

    def test_pending_has_bounded_poll_count(self):
        responses = [(200, {"status": "healthy"}), (202, {"transactionId": self.transaction})]
        responses += [(200, {"status": "PENDING"})] * 60
        with patch.dict(os.environ, self.env), patch.object(smoke, "request", side_effect=responses), \
                patch.object(smoke.time, "sleep"):
            with self.assertRaises(TimeoutError):
                smoke.main()


if __name__ == "__main__":
    unittest.main()
