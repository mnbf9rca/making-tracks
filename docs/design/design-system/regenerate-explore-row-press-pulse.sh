#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
destination="${MT_SIM_LOCK_DESTINATION:-}"
simulator_udid="${MT_SIM_LOCK_UDID:-}"
seat="${MT_SIM_LOCK_SEAT:-}"
expected_run_dir="/private/tmp/release-gate-$simulator_udid"
run_dir="${MT_RELEASE_GATE_RUN_DIR:-$expected_run_dir}"
derived_data="${MT_RELEASE_GATE_DERIVED_DATA:-}"
artifact_root="/private/tmp/making-tracks-artifacts.$simulator_udid"
output_dir="$repo_root/docs/design/design-system"
expected_xcode_version=$'Xcode 26.6\nBuild version 17F113'

[ "${MT_SIM_LOCK:-}" = "1" ] || {
  echo "regenerate-explore-row-press-pulse: invoke through scripts/sim-lock.sh --seat <seat>" >&2
  exit 1
}
[ -n "$destination" ] && [ -n "$derived_data" ] && [ -n "$simulator_udid" ] && [ -n "$seat" ] || {
  echo "regenerate-explore-row-press-pulse: lock destination, seat, derived data, and UUID are required" >&2
  exit 1
}
case ",$destination," in
  *,id="$simulator_udid",*) ;;
  *)
    echo "regenerate-explore-row-press-pulse: simulator lock does not match destination" >&2
    exit 1
    ;;
esac
[ "$run_dir" = "$expected_run_dir" ] || {
  echo "regenerate-explore-row-press-pulse: run directory must be the locked seat's exact default" >&2
  exit 1
}
expected_derived_data="$HOME/Library/Caches/making-tracks-gates/$seat"
[ "$derived_data" = "$expected_derived_data" ] || {
  echo "regenerate-explore-row-press-pulse: derived data must be the locked seat cache path: $expected_derived_data" >&2
  exit 1
}
result_bundle="$run_dir/MakingTracksTests.xcresult"
[ "${MT_RELEASE_GATE_RESULT_BUNDLE:-$result_bundle}" = "$result_bundle" ] || {
  echo "regenerate-explore-row-press-pulse: custom result bundle must stay in the validated run directory" >&2
  exit 1
}

[ -z "$(git status --porcelain --untracked-files=all)" ] || {
  echo "regenerate-explore-row-press-pulse: commit or remove every worktree change before capture" >&2
  exit 1
}
source_head="$(git rev-parse HEAD)"

actual_xcode_version="$(xcodebuild -version)"
[ "$actual_xcode_version" = "$expected_xcode_version" ] || {
  echo "regenerate-explore-row-press-pulse: requires $expected_xcode_version; found $actual_xcode_version" >&2
  exit 1
}

task_root="$(mktemp -d /private/tmp/explore-row-press.XXXXXX)"
candidate_root="$task_root/candidates"
staging="$task_root/staging"
mkdir -p "$candidate_root" "$staging"
test_pid=""
install_backup="$task_root/install-backup"
install_in_progress=0
cleanup_ran=0
packet_files=(
  explore-row-press-settings-default-rest.png
  explore-row-press-settings-default-pressed.png
  explore-row-press-settings-default.txt
  explore-row-press-about-default-rest.png
  explore-row-press-about-default-pressed.png
  explore-row-press-about-default.txt
  explore-row-press-settings-ax-rest.png
  explore-row-press-settings-ax-pressed.png
  explore-row-press-settings-ax.txt
  explore-row-press-about-ax-rest.png
  explore-row-press-about-ax-pressed.png
  explore-row-press-about-ax.txt
  explore-row-press-pulse-captures.txt
)

cleanup() {
  local cleanup_status=$?
  trap - EXIT
  set +e
  if [ "$cleanup_ran" -ne 0 ]; then
    exit "$cleanup_status"
  fi
  cleanup_ran=1
  if [ -n "$test_pid" ] && kill -0 "$test_pid" 2>/dev/null; then
    pkill -TERM -P "$test_pid" 2>/dev/null || true
    kill -TERM "$test_pid" 2>/dev/null || true
    wait "$test_pid" 2>/dev/null || true
  fi
  xcrun simctl status_bar "$simulator_udid" clear >/dev/null 2>&1 || true
  for cleanup_case in settings-default about-default settings-ax about-ax; do
    rm -f \
      "$artifact_root/explore-row-press-$cleanup_case-sampler-coordinate" \
      "$artifact_root/explore-row-press-$cleanup_case-sampler-ready"
  done
  if [ "$install_in_progress" -eq 1 ]; then
    for packet_file in "${packet_files[@]}"; do
      target="$output_dir/$packet_file"
      if [ -f "$install_backup/$packet_file" ]; then
        cp "$install_backup/$packet_file" "$target.rollback.$$"
        mv "$target.rollback.$$" "$target"
      else
        rm -f "$target"
      fi
    done
  fi
  for packet_file in "${packet_files[@]}"; do
    rm -f "$output_dir/$packet_file.tmp.$$" "$output_dir/$packet_file.rollback.$$"
  done
  rm -rf "$result_bundle"
  rm -rf "$task_root"
  exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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

run_logged_with_heartbeat() {
  local label="$1"
  local log_path="$2"
  local started_at
  local elapsed
  local status
  shift 2

  started_at="$(date +%s)"
  echo "regenerate-explore-row-press-pulse: START $label; log=$log_path"
  "$@" >"$log_path" 2>&1 &
  test_pid=$!
  while kill -0 "$test_pid" 2>/dev/null; do
    sleep 10
    if kill -0 "$test_pid" 2>/dev/null; then
      elapsed=$(($(date +%s) - started_at))
      echo "regenerate-explore-row-press-pulse: PROGRESS $label; elapsed=${elapsed}s; log=$log_path"
    fi
  done
  set +e
  wait "$test_pid"
  status=$?
  set -e
  test_pid=""
  elapsed=$(($(date +%s) - started_at))
  echo "regenerate-explore-row-press-pulse: DONE $label; status=$status; elapsed=${elapsed}s; log=$log_path"
  return "$status"
}

build_log="$task_root/build.log"
run_logged_with_heartbeat \
  "Release and Debug build-for-testing" \
  "$build_log" \
  env MT_RELEASE_GATE_MODE=build ./scripts/release-gate.sh
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
  coordination_request="$artifact_root/explore-row-press-$case_name-sampler-coordinate"
  sampler_ready="$artifact_root/explore-row-press-$case_name-sampler-ready"
  case_number=$((index + 1))
  case_started_at="$(date +%s)"
  next_heartbeat=$((case_started_at + 10))
  mkdir -p "$case_dir" "$artifact_root"
  printf '%s\n' "MakingTracksUITests/MakingTracksCoreLoopUITests/$test_name" >"$only_testing"
  rm -f "$measurement_source" "$coordination_request" "$sampler_ready"
  rm -rf "$result_bundle"
  touch "$coordination_request"

  echo "regenerate-explore-row-press-pulse: START case $case_number/${#cases[@]} $case_name; log=$test_log"

  MT_RELEASE_GATE_MODE=test \
  MT_RELEASE_GATE_ONLY_TESTING_FILE="$only_testing" \
    ./scripts/release-gate.sh >"$test_log" 2>&1 &
  test_pid=$!

  # The test pauses after exporting geometry. Capture a known resting frame,
  # then acknowledge it so real XCUIElement.tap() calls may produce the only
  # edge that can latch the evidence style's pressed rendering.
  while kill -0 "$test_pid" 2>/dev/null && [ ! -s "$measurement_source" ]; do
    now="$(date +%s)"
    if [ "$now" -ge "$next_heartbeat" ]; then
      echo "regenerate-explore-row-press-pulse: PROGRESS case $case_number/${#cases[@]} $case_name; waiting-for=rest-geometry; elapsed=$((now - case_started_at))s; log=$test_log"
      next_heartbeat=$((now + 10))
    fi
    sleep 0.05
  done
  [ -s "$measurement_source" ] || {
    tail -n 120 "$test_log" >&2
    echo "regenerate-explore-row-press-pulse: missing $measurement_source" >&2
    exit 1
  }
  xcrun simctl io "$simulator_udid" screenshot \
    --type=png "$case_dir/candidate-0000.png" >/dev/null 2>&1
  touch "$sampler_ready"

  capture_index=1
  while kill -0 "$test_pid" 2>/dev/null && [ "$capture_index" -lt 80 ]; do
    printf -v capture_name 'candidate-%04d.png' "$capture_index"
    if xcrun simctl io "$simulator_udid" screenshot \
      --type=png "$case_dir/$capture_name" >/dev/null 2>&1; then
      capture_index=$((capture_index + 1))
      if [ $((capture_index % 10)) -eq 0 ]; then
        now="$(date +%s)"
        elapsed=$((now - case_started_at))
        [ "$elapsed" -gt 0 ] || elapsed=1
        rate="$(awk -v count="$capture_index" -v seconds="$elapsed" 'BEGIN { printf "%.2f", count / seconds }')"
        eta="$(awk -v count="$capture_index" -v seconds="$elapsed" 'BEGIN { printf "%.0f", (80 - count) / (count / seconds) }')"
        echo "regenerate-explore-row-press-pulse: PROGRESS case $case_number/${#cases[@]} $case_name; candidates=$capture_index/80; elapsed=${elapsed}s; rate=${rate}/s; eta=${eta}s; log=$test_log"
        next_heartbeat=$((now + 10))
      fi
    fi
  done

  while kill -0 "$test_pid" 2>/dev/null; do
    now="$(date +%s)"
    if [ "$now" -ge "$next_heartbeat" ]; then
      echo "regenerate-explore-row-press-pulse: PROGRESS case $case_number/${#cases[@]} $case_name; candidates=$capture_index/80; waiting-for=100-live-taps; elapsed=$((now - case_started_at))s; log=$test_log"
      next_heartbeat=$((now + 10))
    fi
    sleep 0.1
  done

  set +e
  wait "$test_pid"
  test_status=$?
  set -e
  test_pid=""
  rm -f "$coordination_request" "$sampler_ready"
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
  cp "$measurement_source" "$case_dir/measurement.txt"
  rm -rf "$result_bundle"
  case_elapsed=$(($(date +%s) - case_started_at))
  echo "regenerate-explore-row-press-pulse: DONE case $case_number/${#cases[@]} $case_name; status=0; elapsed=${case_elapsed}s; candidates=$capture_index; log=$test_log"
done
capture_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

swift docs/design/design-system/measure-explore-row-press.swift \
  --input "$candidate_root" \
  --output "$staging"

[ "$(git rev-parse HEAD)" = "$source_head" ] || {
  echo "regenerate-explore-row-press-pulse: HEAD changed during capture" >&2
  exit 1
}
[ -z "$(git status --porcelain --untracked-files=all)" ] || {
  echo "regenerate-explore-row-press-pulse: worktree changed during capture" >&2
  exit 1
}

metadata="$task_root/explore-row-press-pulse-captures.txt"
{
  echo "Making Tracks Explore destination-row press pulse"
  echo "evidence-class: Nondeterministic content"
  echo "pressed-state provenance: latched from live press edge"
  echo "git: $source_head"
  echo "git-dirty: false"
  echo "destination: $destination"
  echo "capture-start: $capture_start"
  echo "capture-end: $capture_end"
  echo "focused-ui-tests: 4 passed, 0 failed"
  echo "interaction: 100 XCUIElement.tap() calls per case; press(forDuration:) excluded"
  printf '%s\n' "$actual_xcode_version" | sed 's/^/capture-tool: /'
  echo
  for file in "$staging"/*.png "$staging"/*.txt; do
    digest="$(shasum -a 256 "$file" | awk '{print $1}')"
    echo "$digest  ${file##*/}"
    if [ "${file##*.}" = "png" ]; then
      sips -g pixelWidth -g pixelHeight "$file" | sed 's/^/  /'
    else
      sed 's/^/  /' "$file"
    fi
  done
} >"$metadata"
cp "$metadata" "$staging/explore-row-press-pulse-captures.txt"

mkdir -p "$install_backup"
for packet_file in "${packet_files[@]}"; do
  [ -s "$staging/$packet_file" ] || {
    echo "regenerate-explore-row-press-pulse: staged packet is missing $packet_file" >&2
    exit 1
  }
  if [ -f "$output_dir/$packet_file" ]; then
    cp "$output_dir/$packet_file" "$install_backup/$packet_file"
  fi
done

# The capture manifest is the packet completeness marker and is installed last.
# Removing the old marker first makes an untrappable interruption fail closed
# instead of presenting a mixed packet as complete.
rm -f "$output_dir/explore-row-press-pulse-captures.txt"
install_in_progress=1
for packet_file in "${packet_files[@]}"; do
  staged_file="$staging/$packet_file"
  target="$output_dir/$packet_file"
  temporary_target="$target.tmp.$$"
  cp "$staged_file" "$temporary_target"
  mv "$temporary_target" "$target"
done
install_in_progress=0

cat "$metadata"
