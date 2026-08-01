#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
destination="${MT_SIM_LOCK_DESTINATION:-}"
simulator_udid="${MT_SIM_LOCK_UDID:-}"
derived_data="${MT_RELEASE_GATE_DERIVED_DATA:-/private/tmp/release-gate-$simulator_udid/DerivedData}"
artifact_root="/private/tmp/making-tracks-artifacts"
output_dir="$repo_root/docs/design/design-system"
expected_xcode_version=$'Xcode 26.6\nBuild version 17F113'

[ "${MT_SIM_LOCK:-}" = "1" ] || {
  echo "regenerate-explore-row-press-pulse: invoke through scripts/sim-lock.sh --seat <seat>" >&2
  exit 1
}
[ -n "$destination" ] && [ -n "$derived_data" ] && [ -n "$simulator_udid" ] || {
  echo "regenerate-explore-row-press-pulse: lock destination, derived data, and UUID are required" >&2
  exit 1
}
case ",$destination," in
  *,id="$simulator_udid",*) ;;
  *)
    echo "regenerate-explore-row-press-pulse: simulator lock does not match destination" >&2
    exit 1
    ;;
esac
case "$derived_data" in
  /private/tmp/release-gate-*/DerivedData | /private/tmp/dd-*) ;;
  *)
    echo "regenerate-explore-row-press-pulse: derived data must be task-scoped under /private/tmp" >&2
    exit 1
    ;;
esac

actual_xcode_version="$(xcodebuild -version)"
[ "$actual_xcode_version" = "$expected_xcode_version" ] || {
  echo "regenerate-explore-row-press-pulse: requires $expected_xcode_version; found $actual_xcode_version" >&2
  exit 1
}

task_root="$(mktemp -d /private/tmp/explore-row-press.XXXXXX)"
candidate_root="$task_root/candidates"
staging="$task_root/staging"
result_bundle="$(dirname "$derived_data")/MakingTracksTests.xcresult"
mkdir -p "$candidate_root" "$staging"

cleanup() {
  xcrun simctl status_bar "$simulator_udid" clear >/dev/null 2>&1 || true
  rm -rf "$result_bundle"
  rm -rf "$task_root"
}
trap cleanup EXIT INT TERM

xcrun simctl bootstatus "$simulator_udid" -b
xcrun simctl status_bar "$simulator_udid" override \
  --time 09:41 \
  --dataNetwork wifi \
  --wifiBars 3 \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100

cd "$repo_root"
swift docs/design/design-system/measure-explore-row-press.swift --self-test

build_log="$task_root/build.log"
MT_RELEASE_GATE_MODE=build ./scripts/release-gate.sh >"$build_log" 2>&1
grep -q '\*\* BUILD SUCCEEDED \*\*' "$build_log"
grep -q '\*\* TEST BUILD SUCCEEDED \*\*' "$build_log"

cases=(
  settings-default
  about-default
  settings-ax
  about-ax
)
tests=(
  testExploreRowPressSettingsDefaultEvidence
  testExploreRowPressAboutDefaultEvidence
  testExploreRowPressSettingsAXEvidence
  testExploreRowPressAboutAXEvidence
)

capture_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for index in "${!cases[@]}"; do
  case_name="${cases[$index]}"
  test_name="${tests[$index]}"
  case_dir="$candidate_root/$case_name"
  only_testing="$task_root/only-testing-$case_name.txt"
  test_log="$task_root/test-$case_name.log"
  measurement_source="$artifact_root/explore-row-press-$case_name.txt"
  mkdir -p "$case_dir"
  printf '%s\n' "MakingTracksUITests/MakingTracksCoreLoopUITests/$test_name" >"$only_testing"
  rm -f "$measurement_source"
  rm -rf "$result_bundle"

  MT_RELEASE_GATE_MODE=test \
  MT_RELEASE_GATE_ONLY_TESTING_FILE="$only_testing" \
    ./scripts/release-gate.sh >"$test_log" 2>&1 &
  test_pid=$!

  capture_index=0
  while kill -0 "$test_pid" 2>/dev/null && [ "$capture_index" -lt 80 ]; do
    printf -v capture_name 'candidate-%04d.png' "$capture_index"
    if xcrun simctl io "$simulator_udid" screenshot \
      --type=png "$case_dir/$capture_name" >/dev/null 2>&1; then
      capture_index=$((capture_index + 1))
    fi
  done

  set +e
  wait "$test_pid"
  test_status=$?
  set -e
  [ "$test_status" -eq 0 ] || {
    tail -n 120 "$test_log" >&2
    echo "regenerate-explore-row-press-pulse: $case_name test failed ($test_status)" >&2
    exit "$test_status"
  }
  grep -q 'Executed 1 test, with 0 failures' "$test_log" || {
    echo "regenerate-explore-row-press-pulse: $case_name did not execute exactly 1 passing test" >&2
    exit 1
  }
  [ "$capture_index" -ge 2 ] || {
    echo "regenerate-explore-row-press-pulse: $case_name produced fewer than 2 candidates" >&2
    exit 1
  }
  [ -s "$measurement_source" ] || {
    echo "regenerate-explore-row-press-pulse: missing $measurement_source" >&2
    exit 1
  }
  cp "$measurement_source" "$case_dir/measurement.txt"
  rm -rf "$result_bundle"
  echo "regenerate-explore-row-press-pulse: $case_name passed; captured $capture_index candidates"
done
capture_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

swift docs/design/design-system/measure-explore-row-press.swift \
  --input "$candidate_root" \
  --output "$staging"

metadata="$task_root/explore-row-press-pulse-captures.txt"
{
  echo "Making Tracks Explore destination-row press pulse"
  echo "evidence-class: live ButtonStyle.Configuration.isPressed marker; lossless simulator screenshots"
  echo "git: $(git rev-parse HEAD)"
  echo "destination: $destination"
  echo "capture-start: $capture_start"
  echo "capture-end: $capture_end"
  echo "focused-ui-tests: 4 passed, 0 failed"
  echo "interaction: 100 XCUIElement.tap() calls per case; press(forDuration:) excluded"
  printf '%s\n' "$actual_xcode_version" | sed 's/^/capture-tool: /'
  echo
  for file in "$staging"/*.png "$staging"/*.txt; do
    shasum -a 256 "$file"
    if [ "${file##*.}" = "png" ]; then
      sips -g pixelWidth -g pixelHeight "$file" | sed 's/^/  /'
    else
      sed 's/^/  /' "$file"
    fi
  done
} >"$metadata"
cp "$metadata" "$staging/explore-row-press-pulse-captures.txt"

for staged_file in "$staging"/*; do
  target="$output_dir/${staged_file##*/}"
  temporary_target="$target.tmp.$$"
  cp "$staged_file" "$temporary_target"
  mv "$temporary_target" "$target"
done

cat "$metadata"
