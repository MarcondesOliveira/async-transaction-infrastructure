"""Validate final-teardown intent and deletion-only plans; never execute AWS writes."""

import json
import re
import sys

from delivery import load, require
from infrastructure import ALLOWED_TYPES, SETTINGS

ROLE_SUFFIXES = {"transaction-api-lambda", "request-handler-lambda", "callback-handler-lambda",
                 "transaction-requests-pipe", "callback-gateway",
                 "external-simulator-api", "external-simulator-worker"}


def intent(operation, stack, config, confirmation, enabled):
    require(operation in {"plan", "destroy"} and stack in SETTINGS, "Invalid teardown operation/stack")
    project, environment = config.get("project_name", ""), config.get("environment", "")
    require(re.fullmatch(r"[a-z0-9-]+", project) and re.fullmatch(r"[a-z0-9-]+", environment),
            "Invalid teardown target")
    if operation == "destroy":
        require(enabled == "true", "Delivery freeze TEARDOWN_ENABLED=true is required")
        require(confirmation == f"DESTROY {project}-{environment}", "Exact teardown confirmation required")


def check_plan(plan, config):
    prefix = config["project_name"] + "-" + config["environment"] + "-"
    roles = {prefix + suffix for suffix in ROLE_SUFFIXES}
    deleted = []
    for item in plan.get("resource_changes", []):
        if item.get("mode") == "data" or item["change"]["actions"] == ["no-op"]:
            continue
        require(item["change"]["actions"] == ["delete"], f"Non-delete action blocked: {item['address']}")
        kind = item["type"]
        require(kind in ALLOWED_TYPES | {"aws_iam_role", "aws_iam_role_policy"},
                f"Unsupported teardown resource: {item['address']}")
        before = item["change"].get("before") or {}
        if kind == "aws_iam_role":
            require(before.get("name") in roles, "Only the seven existing runtime roles may be deleted")
        if kind == "aws_iam_role_policy":
            require(before.get("role") in roles, "Only runtime inline policies may be deleted")
        deleted.append(item["address"])
    return deleted


def main():
    command, *args = sys.argv[1:]
    if command == "intent":
        operation, stack, config, confirmation, enabled = args
        intent(operation, stack, load(config), confirmation, enabled)
    elif command == "plan":
        print(json.dumps({"resourcesToDelete": check_plan(load(args[0]), load(args[1]))}))
    elif command == "empty":
        def managed(module):
            return [r["address"] for r in module.get("resources", []) if r.get("mode") == "managed"] + [
                address for child in module.get("child_modules", []) for address in managed(child)]
        remaining = managed(load(args[0]).get("values", {}).get("root_module", {}))
        require(not remaining, "Managed resources remain in stack state after teardown")
        print("Stack state has no remaining managed resources; final AWS inventory is still required.")
    else:
        raise ValueError("Unknown teardown command")


if __name__ == "__main__":
    main()
