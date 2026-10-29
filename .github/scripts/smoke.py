"""Synthetic end-to-end check against the portfolio simulator, not real payments."""

import json
import os
import time
import urllib.request
import uuid


def request(url, method="GET", body=None, headers=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    with urllib.request.urlopen(req, timeout=35) as response:
        return response.status, json.load(response)


def main():
    url = os.environ["SMOKE_API_URL"].rstrip("/")
    if not url.startswith("https://"):
        raise ValueError("Smoke endpoint must use HTTPS")
    status, health = request(url + "/health")
    if status != 200 or health.get("status") != "healthy":
        raise ValueError("Main API health check failed")
    correlation = str(uuid.uuid4())
    key = f"pipeline-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"
    body = {"transactionType": "TRANSFER", "amount": {"value": "1.00", "currency": "BRL"},
            "destination": {"accountId": "portfolio-ci-smoke"}, "externalReference": key}
    status, accepted = request(url + "/transactions", "POST", body,
                               {"Content-Type": "application/json", "Idempotency-Key": key,
                                "X-Correlation-Id": correlation})
    if status != 202:
        raise ValueError("Transaction acceptance failed")
    transaction = str(uuid.UUID(accepted["transactionId"]))
    for _ in range(60):
        status, result = request(url + "/transactions/" + transaction)
        if status == 200 and result.get("status") in {"SUCCEEDED", "REJECTED", "FAILED"}:
            if result["status"] != "SUCCEEDED" or result.get("result", {}).get("code") != "APPROVED":
                raise ValueError(f"Synthetic transaction ended unsuccessfully: {transaction}")
            print(f"End-to-end smoke passed: transactionId={transaction}, status=SUCCEEDED")
            return
        time.sleep(2)
    raise TimeoutError(f"Synthetic transaction did not complete: {transaction}")


if __name__ == "__main__":
    main()
