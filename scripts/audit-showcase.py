#!/usr/bin/env python3
"""Small deterministic audit for the public learning page."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
page = (root / "docs" / "index.html").read_text(encoding="utf-8")
required = ["SwiftConcurrencyLab", 'data-labs="9"', "GCD", "OperationQueue", "Swift Concurrency", "Main Thread Checker"]
missing = [item for item in required if item not in page]
if missing:
    raise SystemExit(f"showcase missing: {', '.join(missing)}")
print("showcase audit passed")
