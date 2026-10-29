"""Validate deployment inputs and narrowly scope routine service plans."""

import base64
import json
import re
import sys
from pathlib import Path

SERVICES = {
    "async-transaction-api": ("core", "lambda", ["aws_lambda_function.transaction_api"]),
    "async-transaction-request-handler": (
        "core", "request_handler", ["aws_lambda_function.request_handler"]
    ),
    "async-transaction-callback-handler": (
        "core", "callback_handler", ["aws_lambda_function.callback_handler"]
    ),
    "external-transaction-processor-simulator": (
        "external-simulator", "simulator",
        ["aws_lambda_function.api", "aws_lambda_function.worker"],
    ),
}
CORE = {
    "lambda": "aws_lambda_function.transaction_api",
    "request_handler": "aws_lambda_function.request_handler",
    "callback_handler": "aws_lambda_function.callback_handler",
}
COMPUTED = {"last_modified", "version", "qualified_arn", "qualified_invoke_arn",
            "code_size", "signing_job_arn", "signing_profile_version_arn"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def resources(module):
    result = {item["address"]: item["values"] for item in module.get("resources", [])}
    for child in module.get("child_modules", []):
        result.update(resources(child))
    return result


def prepare(state, config, manifest, head, service, commit):
    require(service in SERVICES, "Service is not allowlisted")
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "Invalid source commit")
    stack, selected, targets = SERVICES[service]
    key = f"{service}/{commit}/{service}.zip"
    require(manifest.get("service") == service and manifest.get("commit") == commit,
            "Artifact identity mismatch")
    require(manifest.get("package") == f"{service}.zip" and manifest.get("s3Key") == key,
            "Artifact key mismatch")
    require(manifest.get("runtime") == "dotnet10" and manifest.get("architecture") == "arm64"
            and manifest.get("selfContained") is False, "Artifact target mismatch")
    digest = manifest.get("sourceCodeHash", "")
    require(re.fullmatch(r"[A-Za-z0-9+/]{43}=", digest), "Invalid artifact checksum")
    require(base64.b64decode(digest, validate=True).hex() == manifest.get("sha256"),
            "Manifest checksum representations disagree")
    require(head.get("ChecksumSHA256") == digest and
            head.get("ServerSideEncryption") == "AES256" and
            head.get("Metadata", {}).get("source-commit") == commit and
            head.get("Metadata", {}).get("service") == service,
            "Published S3 object does not match manifest")
    require(config.get("aws_region") and config.get("project_name") and
            config.get("environment"), "Missing base stack configuration")
    require(not any(k.endswith("_artifact_key") or k.endswith("_source_code_hash")
                    for k in config), "Base configuration must not pin old artifacts")
    current = resources(state.get("values", {}).get("root_module", {}))
    mapping = CORE if stack == "core" else {"simulator": "aws_lambda_function.api"}
    values = dict(config)
    for prefix, address in mapping.items():
        require(address in current, f"Existing managed function missing: {address}")
        deployed = current[address]
        require(deployed.get("s3_key") and deployed.get("source_code_hash"),
                f"Missing deployed artifact identity: {address}")
        values[prefix + "_artifact_key"] = deployed["s3_key"]
        values[prefix + "_source_code_hash"] = deployed["source_code_hash"]
    if stack == "external-simulator":
        worker = current.get("aws_lambda_function.worker", {})
        require(worker.get("s3_key") == values["simulator_artifact_key"] and
                worker.get("source_code_hash") == values["simulator_source_code_hash"],
                "Simulator API/worker artifact baseline differs; investigate first")
    values[selected + "_artifact_key"] = key
    values[selected + "_source_code_hash"] = digest
    context = {"service": service, "commit": commit, "sourceCodeHash": digest,
               "functions": [current[address]["function_name"] for address in targets]}
    return values, context


def check_plan(plan, service):
    require(service in SERVICES, "Service is not allowlisted")
    targets = set(SERVICES[service][2])
    changed = []
    for item in plan.get("resource_changes", []):
        if item.get("mode") == "data":
            continue
        change = item["change"]
        if change["actions"] == ["no-op"]:
            continue
        require(item["address"] in targets and change["actions"] == ["update"],
                f"Unexpected resource action: {item['address']}")
        before, after = change.get("before") or {}, change.get("after") or {}
        fields = {key for key in before.keys() | after.keys()
                  if before.get(key) != after.get(key)}
        require(fields <= {"s3_key", "source_code_hash"} | COMPUTED,
                f"Non-code Lambda changes blocked: {item['address']}")
        require(not (set(change.get("after_unknown", {})) - COMPUTED - set(before)),
                "Unexpected unknown fields")
        changed.append(item["address"])
    return changed


def verify(context, configurations):
    found = {item["FunctionName"]: item for item in configurations}
    require(set(found) == set(context["functions"]), "Function verification set mismatch")
    for item in found.values():
        require(item.get("State") == "Active" and item.get("LastUpdateStatus") == "Successful"
                and item.get("CodeSha256") == context["sourceCodeHash"] and
                item.get("Runtime") == "dotnet10" and item.get("Architectures") == ["arm64"],
                "Deployed function configuration/hash verification failed")


def load(path):
    return json.loads(Path(path).read_text())


def main():
    command, *args = sys.argv[1:]
    if command == "inputs":
        state, config, manifest, head, service, commit, output, context = args
        values, details = prepare(load(state), load(config), load(manifest), load(head), service, commit)
        Path(output).write_text(json.dumps(values))
        Path(context).write_text(json.dumps(details))
    elif command == "plan":
        changed = check_plan(load(args[0]), args[1])
        print(json.dumps({"changedFunctions": changed, "destructiveChanges": False}))
    elif command == "verify":
        verify(load(args[0]), load(args[1]))
        print("Deployed Lambda hashes and update status verified")
    else:
        raise ValueError("Unknown delivery command")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError) as error:
        print(f"Delivery validation failed: {error}", file=sys.stderr)
        sys.exit(1)
