"""Routine infrastructure delivery: preserve packages and reject destructive/IAM plans."""

import json
import sys
from pathlib import Path

from delivery import CORE, load, require, resources

SETTINGS = {
    "core": {"lambda_memory_mb", "lambda_timeout_seconds", "request_handler_memory_mb",
             "request_handler_timeout_seconds", "processing_requests_visibility_timeout_seconds",
             "processing_requests_max_receive_count", "log_retention_days"},
    "external-simulator": {"operation_retention_hours", "processing_delay_seconds",
                           "worker_trigger_enabled", "log_retention_days"},
}
ALLOWED_TYPES = {
    "aws_cloudwatch_log_group", "aws_dynamodb_table", "aws_sqs_queue",
    "aws_sqs_queue_policy", "aws_sqs_queue_redrive_allow_policy", "aws_sns_topic",
    "aws_sns_topic_subscription", "aws_pipes_pipe", "aws_lambda_function",
    "aws_lambda_permission", "aws_lambda_event_source_mapping",
    "aws_apigatewayv2_api", "aws_apigatewayv2_integration", "aws_apigatewayv2_route",
    "aws_apigatewayv2_stage", "aws_api_gateway_rest_api", "aws_api_gateway_resource",
    "aws_api_gateway_model", "aws_api_gateway_request_validator", "aws_api_gateway_method",
    "aws_api_gateway_integration", "aws_api_gateway_method_response",
    "aws_api_gateway_integration_response", "aws_api_gateway_deployment",
    "aws_api_gateway_stage", "aws_api_gateway_method_settings",
}
PACKAGE_FIELDS = {"s3_bucket", "s3_key", "source_code_hash", "s3_object_version",
                  "filename", "image_uri", "package_type"}


def configuration(stack, base, settings):
    require(stack in SETTINGS, "Stack is not allowlisted")
    require(set(settings) == SETTINGS[stack], "Tracked settings have missing or unexpected keys")
    for key, value in settings.items():
        require(type(value) is (bool if key == "worker_trigger_enabled" else int),
                f"Invalid tracked setting type: {key}")
    require(not any(k.endswith("_artifact_key") or k.endswith("_source_code_hash")
                    for k in base), "Base configuration must not pin packages")
    require(all(base.get(k) for k in ("aws_region", "project_name", "environment")),
            "Missing base stack configuration")
    return dict(base, **settings)


def prepare(stack, state, config):
    require(stack in SETTINGS, "Stack is not allowlisted")
    current = resources(state.get("values", {}).get("root_module", {}))
    mapping = CORE if stack == "core" else {"simulator": "aws_lambda_function.api"}
    values = dict(config)
    contexts = []
    for prefix, address in mapping.items():
        item = current.get(address, {})
        require(item.get("s3_key") and item.get("source_code_hash") and item.get("function_name"),
                f"Existing deployed package missing: {address}")
        values[prefix + "_artifact_key"] = item["s3_key"]
        values[prefix + "_source_code_hash"] = item["source_code_hash"]
        contexts.append({"functions": [item["function_name"]], "sourceCodeHash": item["source_code_hash"]})
    if stack == "external-simulator":
        worker = current.get("aws_lambda_function.worker", {})
        require(worker.get("s3_key") == values["simulator_artifact_key"] and
                worker.get("source_code_hash") == values["simulator_source_code_hash"] and
                worker.get("function_name"), "Simulator API/worker baseline mismatch")
        contexts[0]["functions"].append(worker["function_name"])
    return values, contexts


def check_plan(plan):
    changed = []
    for item in plan.get("resource_changes", []):
        if item.get("mode") == "data" or item["change"]["actions"] == ["no-op"]:
            continue
        address, change = item["address"], item["change"]
        require(change["actions"] in (["create"], ["update"]),
                f"Deletion/replacement blocked: {address}")
        require(item["type"] in ALLOWED_TYPES, f"IAM or unsupported resource blocked: {address}")
        if item["type"] == "aws_lambda_function":
            require(change["actions"] == ["update"], "New functions need an explicit service/package setup")
            before, after = change.get("before") or {}, change.get("after") or {}
            unknown = change.get("after_unknown", {})
            require(all(before.get(k) == after.get(k) and not unknown.get(k) for k in PACKAGE_FIELDS),
                    f"Application package change blocked: {address}")
        changed.append({"address": address, "actions": change["actions"]})
    return changed


def main():
    command, *args = sys.argv[1:]
    if command == "config":
        stack, base, settings, output = args
        Path(output).write_text(json.dumps(configuration(stack, load(base), load(settings))))
    elif command == "inputs":
        stack, state, config, output, contexts = args
        values, checks = prepare(stack, load(state), load(config))
        Path(output).write_text(json.dumps(values))
        Path(contexts).write_text(json.dumps(checks))
    elif command == "plan":
        print(json.dumps({"infrastructureChanges": check_plan(load(args[0])),
                          "destructiveChanges": False, "packageChanges": False}))
    elif command == "verify":
        from delivery import verify
        actual = load(args[1])
        for context in load(args[0]):
            verify(context, [item for item in actual if item["FunctionName"] in context["functions"]])
        print("Existing Lambda packages and update status verified")
    else:
        raise ValueError("Unknown infrastructure command")


if __name__ == "__main__":
    main()
