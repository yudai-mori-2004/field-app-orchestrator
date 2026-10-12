#!/bin/bash

set -uo pipefail

usage() {
  echo "Usage: FAO_DEVELOPMENT_TEAM=<team-id> $0 <device-id> [<device-id> ...]" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 64
fi

if [[ -z "${FAO_DEVELOPMENT_TEAM:-}" ]]; then
  echo "FAO_DEVELOPMENT_TEAM is required and is used only for this invocation." >&2
  usage
  exit 64
fi

if ! command -v xcodebuild >/dev/null 2>&1 || ! command -v xcrun >/dev/null 2>&1; then
  echo "Xcode command-line tools are required." >&2
  exit 69
fi

devices=("$@")
for ((left = 0; left < ${#devices[@]}; left++)); do
  if [[ -z "${devices[$left]}" ]]; then
    echo "Device identifiers must not be empty." >&2
    exit 64
  fi

  for ((right = left + 1; right < ${#devices[@]}; right++)); do
    if [[ "${devices[$left]}" == "${devices[$right]}" ]]; then
      echo "Each device identifier must be unique." >&2
      exit 64
    fi
  done
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
mock_project="$repo_root/ios/mock-app/MockTaskApp.xcodeproj"
runner_project="$repo_root/ios/runner/FieldAppOrchestratorUITests.xcodeproj"
test_name="FieldAppOrchestratorUITests/MockTaskAppUITests/testMockRecordingCanPauseAndResumeThroughKnownControls"

run_device() {
  local index="$1"
  local device_id="$2"
  local work_dir="$3"

  xcodebuild -quiet \
    -project "$mock_project" \
    -scheme MockTaskApp \
    -configuration Debug \
    -destination "platform=iOS,id=$device_id" \
    -derivedDataPath "$work_dir/mock" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$FAO_DEVELOPMENT_TEAM" \
    build

  xcrun devicectl device install app \
    --device "$device_id" \
    "$work_dir/mock/Build/Products/Debug-iphoneos/MockTaskApp.app"

  xcodebuild -quiet \
    -project "$runner_project" \
    -scheme FieldAppOrchestratorUITests \
    -destination "platform=iOS,id=$device_id" \
    -derivedDataPath "$work_dir/runner" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$FAO_DEVELOPMENT_TEAM" \
    -parallel-testing-enabled NO \
    test \
    -only-testing:"$test_name"

  echo "Device $index passed."
}

pids=()
work_dirs=()

for ((index = 0; index < ${#devices[@]}; index++)); do
  display_index=$((index + 1))
  work_dir="$(mktemp -d "/private/tmp/field-mock-device-${display_index}.XXXXXX")"
  work_dirs+=("$work_dir")

  (
    set -euo pipefail
    run_device "$display_index" "${devices[$index]}" "$work_dir"
  ) >"$work_dir/xcodebuild.log" 2>&1 &
  pids+=("$!")
  echo "Device $display_index started; local output: $work_dir/xcodebuild.log"
done

stop_children() {
  local pid
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap stop_children INT TERM

failed=0
for ((index = 0; index < ${#pids[@]}; index++)); do
  display_index=$((index + 1))
  if wait "${pids[$index]}"; then
    echo "Device $display_index: PASS"
  else
    echo "Device $display_index: FAIL" >&2
    tail -n 80 "${work_dirs[$index]}/xcodebuild.log" >&2
    failed=1
  fi
done

if [[ $failed -eq 0 ]]; then
  echo "All ${#devices[@]} devices passed independently."
fi

exit "$failed"
