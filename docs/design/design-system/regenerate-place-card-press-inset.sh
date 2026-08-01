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
screenshot_wait_outcome=""
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

host_self_test_requested=0
if [ "${1:-}" = "--self-test" ]; then
  [ "$#" = "1" ] || die "--self-test takes no other arguments"
  host_self_test_requested=1
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
  if wait "$pid"; then
    wait_status=0
  else
    wait_status=$?
  fi
  return "$wait_status"
}

wait_for_screenshot() {
  local pid="$1"
  local deadline=$(( $(date +%s) + screenshot_timeout_seconds ))
  local now
  local wait_status=0

  screenshot_wait_outcome=""

  while kill -0 "$pid" 2>/dev/null; do
    now="$(date +%s)"
    if [ "$now" -ge "$deadline" ]; then
      terminate_and_reap "$pid" 2>/dev/null || true
      screenshot_wait_outcome="timeout"
      return 124
    fi
    sleep 1
  done
  if wait "$pid"; then
    wait_status=0
    screenshot_wait_outcome="success"
  else
    wait_status=$?
    screenshot_wait_outcome="child-exit"
  fi
  return "$wait_status"
}

wait_for_screenshot_with_context() {
  local pid="$1"
  local frame_name="$2"
  local wait_status=0
  local failure_kind=""

  if wait_for_screenshot "$pid"; then
    return 0
  else
    wait_status=$?
  fi
  failure_kind="$screenshot_wait_outcome"
  case "$failure_kind" in
    timeout|child-exit) ;;
    *) die "screenshot wait failed without a classified outcome" ;;
  esac
  echo "regenerate-place-card-press-inset: screenshot $frame_name failed status=$wait_status kind=$failure_kind" >&2
  return "$wait_status"
}

capture_failure_message() {
  local label="$1"
  local capture_status="$2"

  echo "screenshot capture failed during focused $label test status=$capture_status"
}

stop_capture() {
  local wait_status=0
  [ -n "$capture_pid" ] || return 0
  if terminate_and_reap "$capture_pid"; then
    wait_status=0
  else
    wait_status=$?
  fi
  capture_pid=""
  return "$wait_status"
}

run_timeout_self_test() (
  local saved_timeout="$screenshot_timeout_seconds"
  local saved_grace="$termination_grace_seconds"
  local saved_errexit=disabled
  local selftest_dir=""
  local spawned_pid=""
  local status=0

  case "$-" in *e*) saved_errexit=enabled ;; esac
  selftest_dir="$(mktemp -d /private/tmp/making-tracks-press-self-test.XXXXXX)"
  case "$selftest_dir" in
    /private/tmp/making-tracks-press-self-test.*) ;;
    *) die "host self-test refused unsafe temporary directory" ;;
  esac

  # shellcheck disable=SC2329 # Invoked by the EXIT/INT/TERM trap below.
  cleanup_timeout_self_test() {
    if [ -n "$spawned_pid" ]; then
      terminate_and_reap "$spawned_pid" >/dev/null 2>&1 || true
    fi
    [ -d "$selftest_dir" ] && rm -rf "$selftest_dir"
  }
  trap cleanup_timeout_self_test EXIT INT TERM

  assert_errexit_state() {
    local expected="$1"
    local actual=disabled
    case "$-" in *e*) actual=enabled ;; esac
    [ "$actual" = "$expected" ] ||
      die "host self-test expected errexit $expected, found $actual"
  }

  wait_for_ready() {
    local ready_file="$1"
    local deadline=$(( $(date +%s) + 5 ))
    local now

    while [ ! -e "$ready_file" ]; do
      now="$(date +%s)"
      [ "$now" -lt "$deadline" ] ||
        die "host self-test timed out waiting for TERM-ignore readiness"
      sleep 1
    done
  }

  spawn_term_ignoring_child() {
    local ready_file="$1"

    (trap '' TERM; : > "$ready_file"; while :; do :; done) &
    spawned_pid=$!
    wait_for_ready "$ready_file"
  }

  assert_errexit_state "$saved_errexit"
  spawn_term_ignoring_child "$selftest_dir/enabled-direct.ready"
  termination_grace_seconds=0
  if terminate_and_reap "$spawned_pid" 2>/dev/null; then
    die "host self-test accepted a TERM-ignoring child during direct termination"
  else
    status=$?
  fi
  [ "$status" = "137" ] ||
    die "host self-test expected KILL termination status 137, found $status"
  ! kill -0 "$spawned_pid" 2>/dev/null ||
    die "host self-test left direct-termination child alive"
  spawned_pid=""
  assert_errexit_state "$saved_errexit"

  set +e
  assert_errexit_state disabled
  (exit 0) &
  spawned_pid=$!
  if wait_for_screenshot "$spawned_pid"; then
    :
  else
    die "host self-test could not reap a successful screenshot child"
  fi
  ! kill -0 "$spawned_pid" 2>/dev/null ||
    die "host self-test left successful screenshot child alive"
  spawned_pid=""
  assert_errexit_state disabled

  screenshot_timeout_seconds=0
  spawn_term_ignoring_child "$selftest_dir/disabled-timeout.ready"
  if wait_for_screenshot "$spawned_pid"; then
    die "host self-test accepted a TERM-ignoring screenshot child"
  else
    status=$?
  fi
  [ "$status" = "124" ] ||
    die "host self-test expected screenshot timeout status 124, found $status"
  ! kill -0 "$spawned_pid" 2>/dev/null ||
    die "host self-test left timeout screenshot child alive"
  spawned_pid=""
  assert_errexit_state disabled

  screenshot_timeout_seconds=5
  diagnostic_file="$selftest_dir/child-exit-diagnostic.txt"
  (exit 42) &
  spawned_pid=$!
  if wait_for_screenshot_with_context "$spawned_pid" "frame-17.png" 2> "$diagnostic_file"; then
    die "host self-test accepted a failed screenshot child"
  else
    status=$?
  fi
  [ "$status" = "42" ] ||
    die "host self-test expected screenshot child status 42, found $status"
  [ "$(cat "$diagnostic_file")" = "regenerate-place-card-press-inset: screenshot frame-17.png failed status=42 kind=child-exit" ] ||
    die "host self-test did not receive the contextual child-exit diagnostic"
  spawned_pid=""

  diagnostic_file="$selftest_dir/child-exit-124-diagnostic.txt"
  (exit 124) &
  spawned_pid=$!
  if wait_for_screenshot_with_context "$spawned_pid" "frame-124.png" 2> "$diagnostic_file"; then
    die "host self-test accepted a screenshot child that exited 124"
  else
    status=$?
  fi
  [ "$status" = "124" ] ||
    die "host self-test expected screenshot child exit 124, found $status"
  [ "$(cat "$diagnostic_file")" = "regenerate-place-card-press-inset: screenshot frame-124.png failed status=124 kind=child-exit" ] ||
    die "host self-test confused child exit 124 with a watchdog timeout"
  spawned_pid=""

  screenshot_timeout_seconds=0
  diagnostic_file="$selftest_dir/timeout-diagnostic.txt"
  spawn_term_ignoring_child "$selftest_dir/context-timeout.ready"
  if wait_for_screenshot_with_context "$spawned_pid" "frame-18.png" 2> "$diagnostic_file"; then
    die "host self-test accepted a timed-out screenshot child"
  else
    status=$?
  fi
  [ "$status" = "124" ] ||
    die "host self-test expected contextual timeout status 124, found $status"
  [ "$(cat "$diagnostic_file")" = "regenerate-place-card-press-inset: screenshot frame-18.png failed status=124 kind=timeout" ] ||
    die "host self-test did not receive the contextual timeout diagnostic"
  spawned_pid=""
  assert_errexit_state disabled

  termination_grace_seconds=5
  (trap 'exit 73' TERM; : > "$selftest_dir/capture-worker.ready"; while :; do sleep 1; done) &
  capture_pid=$!
  spawned_pid=$capture_pid
  wait_for_ready "$selftest_dir/capture-worker.ready"
  if stop_capture; then
    die "host self-test accepted a failed capture worker"
  else
    status=$?
  fi
  [ "$status" = "73" ] ||
    die "host self-test expected capture worker status 73, found $status"
  final_diagnostic="regenerate-place-card-press-inset: $(capture_failure_message default "$status")"
  [ "$final_diagnostic" = "regenerate-place-card-press-inset: screenshot capture failed during focused default test status=73" ] ||
    die "host self-test did not receive the exact final capture-worker diagnostic"
  spawned_pid=""

  screenshot_timeout_seconds="$saved_timeout"
  termination_grace_seconds="$saved_grace"
  case "$saved_errexit" in
    enabled) set -e ;;
    disabled) set +e ;;
  esac
  assert_errexit_state "$saved_errexit"
  echo "PASS screenshot-timeout-reap"
)

if [ "$host_self_test_requested" = "1" ]; then
  run_host_self_test
  run_timeout_self_test
  exit 0
fi

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
  local screenshot_name=""
  local screenshot_pid=""
  local screenshot_status=0

  # shellcheck disable=SC2329 # Invoked asynchronously by the TERM/INT trap below.
  stop_current_screenshot() {
    if [ -n "$screenshot_pid" ]; then
      terminate_and_reap "$screenshot_pid" || true
    fi
    exit 0
  }
  trap stop_current_screenshot TERM INT
  while [ "$frame" -lt "$max_capture_frames" ]; do
    screenshot_name="frame-$frame.png"
    xcrun simctl io "$lock_udid" screenshot --type=png "$directory/$screenshot_name" &
    screenshot_pid=$!
    set +e
    wait_for_screenshot_with_context "$screenshot_pid" "$screenshot_name"
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
  if [ "$current_label" = "default" ]; then
    printf '%s\n' \
      MakingTracksTests/AppShellTests/testPlaceCardPressEvidenceStyleDelegatesToRuledProductionStyle \
      "$current_test" > "$only_testing_file"
  else
    printf '%s\n' "$current_test" > "$only_testing_file"
  fi

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
  [ "$capture_status" = "0" ] || die "$(capture_failure_message "$current_label" "$capture_status")"
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
