#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
destination="${MT_SIM_LOCK_DESTINATION:-}"
expected_xcode_version=$'Xcode 26.6\nBuild version 17F113'
output_dir="$repo_root/docs/design/design-system"
derived_data="${MT_RELEASE_GATE_DERIVED_DATA:-/private/tmp/dd-codex2}"

[ -n "$destination" ] || {
  echo "regenerate-snow-theme-lock: MT_SIM_LOCK_DESTINATION is required" >&2
  exit 1
}
[ "${MT_SIM_LOCK:-}" = "1" ] || {
  echo "regenerate-snow-theme-lock: invoke through scripts/sim-lock.sh --seat <seat>" >&2
  exit 1
}

destination_fields=",$destination,"
case "$destination_fields" in
  *,id=*) destination_after_id="${destination_fields#*,id=}" ;;
  *)
    echo "regenerate-snow-theme-lock: destination must include id=<simulator-udid>" >&2
    exit 1
    ;;
esac
simulator_udid="${destination_after_id%%,*}"
[ "${MT_SIM_LOCK_UDID:-}" = "$simulator_udid" ] || {
  echo "regenerate-snow-theme-lock: simulator lock does not match destination" >&2
  exit 1
}
artifact_dir="/private/tmp/making-tracks-artifacts.$simulator_udid"
rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"

actual_xcode_version="$(xcodebuild -version)"
[ "$actual_xcode_version" = "$expected_xcode_version" ] || {
  echo "regenerate-snow-theme-lock: requires $expected_xcode_version; found $actual_xcode_version" >&2
  exit 1
}

only_testing_file="$(mktemp /private/tmp/snow-theme-lock-only-testing.XXXXXX)"
summary_file="$(mktemp /private/tmp/snow-theme-lock-summary.XXXXXX)"
result_bundle="/private/tmp/snow-theme-lock-$simulator_udid-$$.xcresult"
result_extracted=0
cleanup() {
  xcrun simctl status_bar "$simulator_udid" clear >/dev/null 2>&1 || true
  rm -f "$only_testing_file" "$summary_file"
  rm -rf "$artifact_dir"
  if [ "$result_extracted" = "1" ]; then
    rm -rf "$result_bundle"
  fi
}
trap cleanup EXIT

printf '%s\n' \
  'MakingTracksUITests/MakingTracksCoreLoopUITests/testSnowSettingsAdaptiveInkIsLegibleAndInvariantAcrossSystemAppearances' \
  > "$only_testing_file"

xcrun simctl status_bar "$simulator_udid" override \
  --time 09:41 \
  --dataNetwork wifi \
  --wifiBars 3 \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100

cd "$repo_root"
MT_RELEASE_GATE_DERIVED_DATA="$derived_data" \
MT_RELEASE_GATE_ONLY_TESTING_FILE="$only_testing_file" \
MT_RELEASE_GATE_RESULT_BUNDLE="$result_bundle" \
  ./scripts/release-gate.sh

xcrun xcresulttool get test-results summary --path "$result_bundle" > "$summary_file"
passed_tests="$(plutil -extract passedTests raw -o - "$summary_file")"
failed_tests="$(plutil -extract failedTests raw -o - "$summary_file")"
result_extracted=1
[ "$passed_tests" = "1" ] && [ "$failed_tests" = "0" ] || {
  echo "regenerate-snow-theme-lock: expected 1 passed and 0 failed; found $passed_tests passed and $failed_tests failed" >&2
  exit 1
}

assets=(
  snow-theme-lock-appearance-light.png
  snow-theme-lock-appearance-dark.png
  snow-theme-lock-map-data-light.png
  snow-theme-lock-map-data-dark.png
  snow-theme-lock-location-light.png
  snow-theme-lock-location-dark.png
)

for asset in "${assets[@]}"; do
  source_path="$artifact_dir/$asset"
  [ -s "$source_path" ] || {
    echo "regenerate-snow-theme-lock: missing capture $source_path" >&2
    exit 1
  }

  pixel_width="$(sips -g pixelWidth "$source_path" | awk '/pixelWidth/ { print $2 }')"
  pixel_height="$(sips -g pixelHeight "$source_path" | awk '/pixelHeight/ { print $2 }')"
  [ "$pixel_width" = "1206" ] && [ "$pixel_height" = "2622" ] || {
    echo "regenerate-snow-theme-lock: $asset is ${pixel_width}x${pixel_height}, expected 1206x2622" >&2
    exit 1
  }
done

measurement_source="$artifact_dir/snow-theme-lock-measurements.txt"
measurement_output="$output_dir/snow-theme-lock-measurements.txt"
[ -s "$measurement_source" ] || {
  echo "regenerate-snow-theme-lock: missing measurements $measurement_source" >&2
  exit 1
}

for asset in "${assets[@]}"; do
  install -m 0644 "$artifact_dir/$asset" "$output_dir/$asset"
done
install -m 0644 "$measurement_source" "$measurement_output"

echo "$actual_xcode_version"
echo "Focused Release gate: $passed_tests passed, $failed_tests failed"
echo "XCTest XCUIScreen captures: 1206x2622 px (402x874 pt @3x), iPhone 17 iOS 26.5 simulator"
cat "$measurement_output"
shasum -a 256 "${assets[@]/#/$output_dir/}" "$measurement_output"
