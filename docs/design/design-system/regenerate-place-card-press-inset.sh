#!/usr/bin/env bash
# Regenerate the deterministic, live-configuration press-inset evidence.
# Invoke only through: ./scripts/sim-lock.sh --seat codex4 ./docs/design/design-system/regenerate-place-card-press-inset.sh
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
destination="${MT_SIM_LOCK_DESTINATION:-}"
lock_udid="${MT_SIM_LOCK_UDID:-}"
derived_data="${MT_RELEASE_GATE_DERIVED_DATA:-/private/tmp/dd-codex4}"
output_dir="$repo_root/docs/design/design-system"
analyzer="$output_dir/measure-place-card-press.swift"
artifact_dir=""
run_dir=""
only_testing_file=""
summary_file=""
capture_pid=""
capture_dir=""
result_bundle=""
build_result_bundle=""
status_bar_set=0
max_capture_frames=120
screenshot_timeout_seconds=15
termination_grace_seconds=5
assets=()
backup_dir=""
install_started=0
install_completed=0

die() {
  echo "regenerate-place-card-press-inset: $*" >&2
  exit 1
}

is_core_simulator_uuid() {
  [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

run_host_self_test() {
  local ledger_destination
  local ledger_after_id
  local ledger_uuid

  ledger_destination="$(awk -F '|' '$2 ~ /`codex4`/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); gsub(/`/, "", $4); print $4; exit }' "$repo_root/docs/ios-gate-ledger.md")"
  [ -n "$ledger_destination" ] || die "host self-test could not read the codex4 ledger destination"
  case ",$ledger_destination," in
    *,id=*) ledger_after_id="${ledger_destination#*,id=}" ;;
    *) die "host self-test found no simulator id in the codex4 ledger destination" ;;
  esac
  ledger_uuid="${ledger_after_id%%,*}"
  is_core_simulator_uuid "$ledger_uuid" || die "host self-test rejected the valid codex4 ledger UUID"
  ! is_core_simulator_uuid "00000000-0000-0000-0000-00000000000" ||
    die "host self-test accepted an 8-4-4-4-11 UUID"
  echo "PASS valid-ledger-uuid"
}

if [ "${1:-}" = "--self-test" ]; then
  [ "$#" = "1" ] || die "--self-test takes no other arguments"
  run_host_self_test
  exit 0
fi

require_safe_directory() {
  case "$1" in
    /private/tmp/making-tracks-place-card-press."$lock_udid".*) ;;
    *) die "refusing an unsafe task directory: $1" ;;
  esac
}

require_safe_result_bundle() {
  case "$1" in
    /private/tmp/making-tracks-place-card-press."$lock_udid".*.xcresult) ;;
    *) die "refusing an unsafe result bundle: $1" ;;
  esac
}

require_safe_artifact_directory() {
  [ "$1" = "/private/tmp/making-tracks-artifacts.$lock_udid" ] || \
    die "refusing an unsafe artifact directory: $1"
}

remove_exact_result_bundle() {
  [ -n "$result_bundle" ] || return 0
  require_safe_result_bundle "$result_bundle"
  [ -e "$result_bundle" ] || return 0
  rm -rf "$result_bundle"
}

remove_exact_build_result_bundle() {
  [ -n "$build_result_bundle" ] || return 0
  require_safe_result_bundle "$build_result_bundle"
  [ -e "$build_result_bundle" ] || return 0
  rm -rf "$build_result_bundle"
}

terminate_and_reap() {
  local pid="$1"
  local deadline
  local now
  local wait_status=0

  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    deadline=$(( $(date +%s) + termination_grace_seconds ))
    while kill -0 "$pid" 2>/dev/null; do
      now="$(date +%s)"
      [ "$now" -lt "$deadline" ] || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  set +e
  wait "$pid"
  wait_status=$?
  set -e
  return "$wait_status"
}

wait_for_screenshot() {
  local pid="$1"
  local deadline=$(( $(date +%s) + screenshot_timeout_seconds ))
  local now
  local wait_status=0

  while kill -0 "$pid" 2>/dev/null; do
    now="$(date +%s)"
    if [ "$now" -ge "$deadline" ]; then
      terminate_and_reap "$pid" || true
      return 124
    fi
    sleep 1
  done
  set +e
  wait "$pid"
  wait_status=$?
  set -e
  return "$wait_status"
}

rollback_packet_install() {
  [ "$install_started" = "1" ] || return 0
  [ "$install_completed" = "0" ] || return 0
  for asset in "${assets[@]}"; do
    rm -f "$output_dir/.$asset.$$-new"
    if [ -n "$backup_dir" ] && [ -e "$backup_dir/$asset" ]; then
      mv -f "$backup_dir/$asset" "$output_dir/$asset"
    elif [ -e "$output_dir/$asset" ]; then
      rm -f "$output_dir/$asset"
    fi
  done
}

stop_capture() {
  local wait_status=0
  [ -n "$capture_pid" ] || return 0
  set +e
  terminate_and_reap "$capture_pid"
  wait_status=$?
  set -e
  capture_pid=""
  return "$wait_status"
}

cleanup() {
  local exit_status=$?
  stop_capture || true
  if [ "$status_bar_set" = "1" ]; then
    xcrun simctl status_bar "$lock_udid" clear >/dev/null 2>&1 || true
  fi
  [ -n "$only_testing_file" ] && rm -f "$only_testing_file"
  [ -n "$summary_file" ] && rm -f "$summary_file"
  remove_exact_result_bundle
  remove_exact_build_result_bundle
  rollback_packet_install
  if [ -n "$artifact_dir" ]; then
    require_safe_artifact_directory "$artifact_dir"
    rm -f \
      "$artifact_dir/place-card-press-inset-default-frame.txt" \
      "$artifact_dir/place-card-press-inset-ax-frame.txt"
  fi
  if [ -n "$capture_dir" ]; then
    require_safe_directory "$capture_dir"
    [ -d "$capture_dir" ] && rm -rf "$capture_dir"
  fi
  if [ -n "$run_dir" ]; then
    require_safe_directory "$run_dir"
    [ -d "$run_dir" ] && rm -rf "$run_dir"
  fi
  exit "$exit_status"
}
trap cleanup EXIT INT TERM

[ "${MT_SIM_LOCK:-}" = "1" ] || die "must run inside scripts/sim-lock.sh --seat codex4"
[ -n "$destination" ] || die "MT_SIM_LOCK_DESTINATION is required"
[ -n "$lock_udid" ] || die "MT_SIM_LOCK_UDID is required"
[ "$derived_data" = "/private/tmp/dd-codex4" ] || die "MT_RELEASE_GATE_DERIVED_DATA must be /private/tmp/dd-codex4"
[ -f "$analyzer" ] || die "missing analyzer: $analyzer"

destination_fields=",$destination,"
case "$destination_fields" in
  *,id=*) destination_after_id="${destination_fields#*,id=}" ;;
  *) die "MT_SIM_LOCK_DESTINATION must include id=<simulator-udid>" ;;
esac
simulator_udid="${destination_after_id%%,*}"
destination_remainder="${destination_after_id#"$simulator_udid"}"
case "$destination_remainder" in
  *,id=*) die "MT_SIM_LOCK_DESTINATION must contain exactly one id=<simulator-udid>" ;;
esac
case "$simulator_udid" in
  ""|*[!A-Za-z0-9-]*) die "MT_SIM_LOCK_DESTINATION has an invalid simulator UDID" ;;
esac
is_core_simulator_uuid "$simulator_udid" || die "MT_SIM_LOCK_DESTINATION must carry an 8-4-4-4-12 CoreSimulator UUID"
[ "$lock_udid" = "$simulator_udid" ] || die "MT_SIM_LOCK_UDID does not match MT_SIM_LOCK_DESTINATION"

artifact_dir="/private/tmp/making-tracks-artifacts.$lock_udid"
require_safe_artifact_directory "$artifact_dir"
[ -d "$artifact_dir" ] || mkdir -p "$artifact_dir"
run_dir="$(mktemp -d "/private/tmp/making-tracks-place-card-press.$lock_udid.XXXXXX")"
require_safe_directory "$run_dir"
only_testing_file="$run_dir/only-testing.txt"
summary_file="$run_dir/summary.plist"
build_run_dir="$run_dir/build-gate"
build_result_bundle="$build_run_dir/MakingTracksBuild.xcresult"
require_safe_directory "$build_run_dir"
require_safe_result_bundle "$build_result_bundle"
mkdir -p "$build_run_dir"

# A fixed status bar is part of the deterministic-fixture contract. This script
# already runs under the wrapper-owned simulator lock; it never owns a lock itself.
xcrun simctl bootstatus "$lock_udid" -b
xcrun simctl status_bar "$lock_udid" override \
  --time 09:41 \
  --dataNetwork wifi \
  --wifiBars 3 \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100
status_bar_set=1

for frame_record in \
  "$artifact_dir/place-card-press-inset-default-frame.txt" \
  "$artifact_dir/place-card-press-inset-ax-frame.txt"; do
  rm -f "$frame_record"
done

capture_loop() {
  local directory="$1"
  local frame=0
  local screenshot_pid=""
  local screenshot_status=0

  # shellcheck disable=SC2329 # Invoked asynchronously by the TERM/INT trap below.
  stop_current_screenshot() {
    if [ -n "$screenshot_pid" ]; then
      set +e
      terminate_and_reap "$screenshot_pid"
      set -e
    fi
    exit 0
  }
  trap stop_current_screenshot TERM INT
  while [ "$frame" -lt "$max_capture_frames" ]; do
    xcrun simctl io "$lock_udid" screenshot --type=png "$directory/frame-$frame.png" &
    screenshot_pid=$!
    set +e
    wait_for_screenshot "$screenshot_pid"
    screenshot_status=$?
    set -e
    screenshot_pid=""
    [ "$screenshot_status" = "0" ] || exit "$screenshot_status"
    frame=$((frame + 1))
  done
  echo "regenerate-place-card-press-inset: capture reached ${max_capture_frames}-frame safety cap" >&2
  exit 75
}

extract_counts() {
  xcrun xcresulttool get test-results summary --path "$result_bundle" > "$summary_file"
  passed_tests="$(plutil -extract passedTests raw -o - "$summary_file")"
  failed_tests="$(plutil -extract failedTests raw -o - "$summary_file")"
  case "$passed_tests:$failed_tests" in
    *[!0-9:]*|:) die "could not read focused test counts" ;;
  esac
  [ "$failed_tests" = "0" ] || die "focused $current_label test failed: $passed_tests passed, $failed_tests failed"
  current_counts="$passed_tests passed, $failed_tests failed"
  remove_exact_result_bundle
}

run_focused_capture() {
  current_label="$1"
  current_test="$2"
  capture_dir="$run_dir/$current_label-candidates"
  mkdir -p "$capture_dir"
  result_bundle="$run_dir/$current_label.xcresult"
  require_safe_result_bundle "$result_bundle"
  printf '%s\n' "$current_test" > "$only_testing_file"

  capture_loop "$capture_dir" &
  capture_pid=$!
  set +e
  MT_RELEASE_GATE_DERIVED_DATA="$derived_data" \
  MT_RELEASE_GATE_MODE=test \
  MT_RELEASE_GATE_ONLY_TESTING_FILE="$only_testing_file" \
  MT_RELEASE_GATE_RESULT_BUNDLE="$result_bundle" \
    "$repo_root/scripts/release-gate.sh"
  gate_status=$?
  set -e
  set +e
  stop_capture
  capture_status=$?
  set -e
  [ "$gate_status" = "0" ] || die "focused $current_label test command failed"
  [ "$capture_status" = "0" ] || die "screenshot capture failed during focused $current_label test"
  [ -s "$artifact_dir/place-card-press-inset-$current_label-frame.txt" ] || die "missing $current_label button frame record"
  extract_counts
  case "$current_label" in
    default) default_counts="$current_counts" ;;
    ax) ax_counts="$current_counts" ;;
  esac
  result_bundle=""
}

cd "$repo_root"
MT_RELEASE_GATE_DERIVED_DATA="$derived_data" \
MT_RELEASE_GATE_MODE=build \
MT_RELEASE_GATE_RUN_DIR="$build_run_dir" \
MT_RELEASE_GATE_RESULT_BUNDLE="$build_result_bundle" \
  "$repo_root/scripts/release-gate.sh"
remove_exact_build_result_bundle
build_result_bundle=""

run_focused_capture \
  default \
  MakingTracksUITests/MakingTracksCoreLoopUITests/testPlaceCardPressInsetEvidenceDefault
run_focused_capture \
  ax \
  MakingTracksUITests/MakingTracksCoreLoopUITests/testPlaceCardPressInsetEvidenceAX

stage_dir="$run_dir/staged"
mkdir -p "$stage_dir"
default_measurement="$(xcrun swift "$analyzer" --select \
  --candidates "$run_dir/default-candidates" \
  --frame "$artifact_dir/place-card-press-inset-default-frame.txt" \
  --rest-output "$stage_dir/place-card-press-inset-default-rest.png" \
  --pressed-output "$stage_dir/place-card-press-inset-default-pressed.png" \
  --label default)"
ax_measurement="$(xcrun swift "$analyzer" --select \
  --candidates "$run_dir/ax-candidates" \
  --frame "$artifact_dir/place-card-press-inset-ax-frame.txt" \
  --rest-output "$stage_dir/place-card-press-inset-ax-rest.png" \
  --pressed-output "$stage_dir/place-card-press-inset-ax-pressed.png" \
  --label ax)"

default_displacement="$(printf '%s\n' "$default_measurement" | awk -F 'top_displacement=' '/^RESULT label=default / { split($2, fields, " "); print fields[1] }')"
ax_displacement="$(printf '%s\n' "$ax_measurement" | awk -F 'top_displacement=' '/^RESULT label=ax / { split($2, fields, " "); print fields[1] }')"
case "$default_displacement:$ax_displacement" in
  *[!0-9:]*|:) die "analyzer did not emit both integer displacements" ;;
esac
[ "$default_displacement" -gt 0 ] || die "default displacement must be positive"
[ "$ax_displacement" -gt "$default_displacement" ] || die "AX displacement must exceed default"

assets=(
  place-card-press-inset-default-rest.png
  place-card-press-inset-default-pressed.png
  place-card-press-inset-ax-rest.png
  place-card-press-inset-ax-pressed.png
)
for asset in "${assets[@]}"; do
  staged_asset="$stage_dir/$asset"
  [ -s "$staged_asset" ] || die "missing staged evidence: $staged_asset"
  sips -g pixelWidth -g pixelHeight "$staged_asset" >/dev/null
done
backup_dir="$run_dir/previous-packet"
mkdir -p "$backup_dir"
for asset in "${assets[@]}"; do
  [ ! -e "$output_dir/$asset" ] || cp -p "$output_dir/$asset" "$backup_dir/$asset"
done
install_started=1
for asset in "${assets[@]}"; do
  install -m 0644 "$stage_dir/$asset" "$output_dir/.$asset.$$-new"
done
for asset in "${assets[@]}"; do
  mv -f "$output_dir/.$asset.$$-new" "$output_dir/$asset"
done
install_completed=1

echo "head: $(git rev-parse HEAD)"
echo "destination: $destination"
echo "default focused test: $default_counts"
echo "AX focused test: $ax_counts"
echo "$default_measurement"
echo "$ax_measurement"
echo "comparison: default=$default_displacement ax=$ax_displacement"
xcodebuild -version | sed 's/^/xcode: /'
xcrun swift --version | sed 's/^/swift: /'
shasum -a 256 "${assets[@]/#/$output_dir/}"
