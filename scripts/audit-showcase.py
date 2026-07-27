#!/usr/bin/env python3
"""Small deterministic audit for the public learning page."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
page = (root / "docs" / "index.html").read_text(encoding="utf-8")
required = [
    "SwiftConcurrencyLab", 'data-labs="9"', "GCD", "OperationQueue", "Swift Concurrency", "Main Thread Checker",
    'rel="canonical"', 'property="og:title"', 'property="og:description"', 'property="og:url"',
    "estelledc.github.io/SwiftConcurrencyLab/", "Jason DS 2.2.0", "evidence-playbook.md",
]
missing = [item for item in required if item not in page]
if missing:
    raise SystemExit(f"showcase missing: {', '.join(missing)}")


def source_test_count(source: str) -> int:
    return len(re.findall(r"^\s*func test[A-Za-z0-9_]+\s*\(", source, re.MULTILINE))


def published_count(kind: str) -> int:
    body_match = re.search(rf'data-{kind}-tests="(\d+)"', page)
    proof_match = re.search(rf'data-proof="{kind}-tests">(\d+)<', page)
    if not body_match or not proof_match:
        raise SystemExit(f"showcase missing machine-readable {kind} test count")
    if body_match.group(1) != proof_match.group(1):
        raise SystemExit(f"showcase {kind} count disagrees between body and proof rail")
    return int(body_match.group(1))


expected_counts = {
    "core": sum(
        source_test_count(path.read_text(encoding="utf-8"))
        for path in sorted((root / "Tests/SwiftConcurrencyCoreTests").glob("*.swift"))
    ),
    "ui": sum(
        source_test_count(path.read_text(encoding="utf-8"))
        for path in sorted((root / "SwiftConcurrencyLabUITests").glob("*.swift"))
    ),
}
for kind, source_count in expected_counts.items():
    if published_count(kind) != source_count:
        raise SystemExit(
            f"showcase {kind} test count drifted: "
            f"published={published_count(kind)}, source={source_count}"
        )
print("showcase audit passed")
