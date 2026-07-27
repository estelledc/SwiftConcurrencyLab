#!/usr/bin/env python3
"""Reduce an xcresult summary to a portable, non-sensitive UI-test receipt."""

from datetime import datetime, timezone
import json
from pathlib import Path
import sys


if len(sys.argv) != 5:
    raise SystemExit(
        "usage: write-ui-receipt.py SUMMARY RECEIPT SIMULATOR_NAME SIMULATOR_OS"
    )

summary_path = Path(sys.argv[1])
receipt_path = Path(sys.argv[2])
simulator_name = sys.argv[3]
simulator_os = sys.argv[4]
summary = json.loads(summary_path.read_text(encoding="utf-8"))


def integer(*keys: str) -> int:
    for key in keys:
        value = summary.get(key)
        if isinstance(value, int):
            return value
    raise SystemExit(f"xcresult summary missing integer field: {', '.join(keys)}")


result = summary.get("result")
if not isinstance(result, str):
    raise SystemExit("xcresult summary missing result")

receipt = {
    "schemaVersion": 1,
    "suite": "SwiftConcurrencyLabUITests",
    "result": result,
    "tests": {
        "total": integer("totalTestCount", "totalTests"),
        "passed": integer("passedTests", "testsPassed"),
        "failed": integer("failedTests", "testsFailed"),
        "skipped": integer("skippedTests", "testsSkipped"),
    },
    "simulator": {"name": simulator_name, "os": simulator_os},
    "artifacts": {
        "resultBundle": "SwiftConcurrencyLab.xcresult",
        "summary": "xcresult-summary.json",
        "buildLog": "xcodebuild.log",
    },
    "generatedAtUTC": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
}

if result.lower() not in {"passed", "success", "succeeded"}:
    raise SystemExit(f"UI test result is not successful: {result}")
tests = receipt["tests"]
if tests["total"] <= 0:
    raise SystemExit("UI test receipt must contain at least one executed test")
if tests["failed"] != 0 or tests["skipped"] != 0 or tests["passed"] != tests["total"]:
    raise SystemExit("UI test receipt requires every selected test to pass without skips")

receipt_path.write_text(
    json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
