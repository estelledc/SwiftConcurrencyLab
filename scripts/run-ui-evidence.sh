#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
simulator_name="${SIMULATOR_NAME:-iPhone 17 Pro}"
simulator_os="${SIMULATOR_OS:-$(xcrun --sdk iphonesimulator --show-sdk-version)}"
artifact_root="${ARTIFACT_ROOT:-$root/.artifacts/ui-evidence}"
mkdir -p "$artifact_root"
run_dir="$(mktemp -d "$artifact_root/run-XXXXXX")"
run_id="$(basename "$run_dir")"
derived_data="$run_dir/DerivedData"
result_bundle="$run_dir/SwiftConcurrencyLab.xcresult"
summary_json="$run_dir/xcresult-summary.json"
receipt_json="$run_dir/receipt.json"
device_id=""

cleanup_on_exit() {
  if [[ -n "$device_id" ]]; then
    xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$device_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_on_exit EXIT

device_spec="$({ xcrun simctl list --json; } | python3 -c '
import json
import sys

name, version = sys.argv[1:]
payload = json.load(sys.stdin)
device_type = next(
    (item for item in payload.get("devicetypes", []) if item.get("name") == name),
    None,
)
runtime = next(
    (
        item
        for item in payload.get("runtimes", [])
        if item.get("platform") == "iOS"
        and item.get("version") == version
        and item.get("isAvailable", False)
    ),
    None,
)
if device_type is None or runtime is None:
    raise SystemExit(f"missing device type {name} or iOS runtime {version}")
supported = {item.get("identifier") for item in runtime.get("supportedDeviceTypes", [])}
if supported and device_type["identifier"] not in supported:
    raise SystemExit(f"{name} is not supported by iOS {version}")
print(device_type["identifier"] + "\t" + runtime["identifier"])
' "$simulator_name" "$simulator_os")"

IFS=$'\t' read -r device_type runtime_id <<<"$device_spec"
device_name="SwiftConcurrencyLab-$run_id"
device_id="$(xcrun simctl create "$device_name" "$device_type" "$runtime_id")"

xcodebuild \
  -project "$root/SwiftConcurrencyLab.xcodeproj" \
  -scheme SwiftConcurrencyLab \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$result_bundle" \
  -only-testing:SwiftConcurrencyLabUITests \
  CODE_SIGNING_ALLOWED=NO \
  test 2>&1 | tee "$run_dir/xcodebuild.log"

xcrun xcresulttool get test-results summary \
  --path "$result_bundle" >"$summary_json"
python3 "$root/scripts/write-ui-receipt.py" \
  "$summary_json" "$receipt_json" "$simulator_name" "$simulator_os"

xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
xcrun simctl delete "$device_id"
device_id=""

relative_run_dir="${run_dir#"$root/"}"
printf 'UI evidence passed: %s\n' "$relative_run_dir"
