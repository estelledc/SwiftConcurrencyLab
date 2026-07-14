#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if rg -n --hidden --glob '!.git/**' --glob '!.build/**' --glob '!.DerivedData/**' --glob '!scripts/public-scan.sh' '/Users/|lark|bytedance|api[_-]?token|password|secret' "$root"; then
  echo "public scan found a forbidden private marker" >&2
  exit 1
fi
echo "public scan passed"
