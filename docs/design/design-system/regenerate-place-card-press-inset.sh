#!/usr/bin/env bash
# Regenerate the deterministic, live-configuration press-inset evidence.
# Invoke only through: ./scripts/sim-lock.sh --seat codex4 ./docs/design/design-system/regenerate-place-card-press-inset.sh
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
destination="${MT_SIM_LOCK_DESTINATION:-}"
lock_udid="${MT_SIM_LOCK_UDID:-}"
derived_data="${MT_RELEASE_GATE_DERIVED_DATA:-$HOME/Library/Caches/making-tracks-gates/codex4}"
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
cleanup_ran=0
cleanup_count_file=""
signal_self_test_dir=""

die() {
  echo "regenerate-place-card-press-inset: $*" >&2
  exit 1
}

is_core_simulator_uuid() {
  [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

ledger_destination_for_seat() {
  local seat="$1"

  awk -F '|' -v seat="$seat" '$2 ~ ("`" seat "`") { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); gsub(/`/, "", $4); print $4; exit }' \
    "$repo_root/docs/ios-gate-ledger.md"
}

ledger_uuid_for_seat() {
  local seat="$1"
  local seat_after_id
  local seat_destination
  local seat_uuid

  seat_destination="$(ledger_destination_for_seat "$seat")"
  [ -n "$seat_destination" ] || die "could not read the $seat ledger destination"
  case ",$seat_destination," in
    *,id=*) seat_after_id="${seat_destination#*,id=}" ;;
    *) die "found no simulator id in the $seat ledger destination" ;;
  esac
  seat_uuid="${seat_after_id%%,*}"
  is_core_simulator_uuid "$seat_uuid" || die "rejected the valid $seat ledger UUID"
  printf '%s\n' "$seat_uuid"
}

run_host_self_test() {
  local alternate_destination
  local alternate_uuid
  local diagnostic_file
  local external_call_log
  local ledger_destination
  local ledger_after_id
  local ledger_uuid
  local mock_bin
  local provenance_status=0
  local provenance_test_dir

  ledger_destination="$(ledger_destination_for_seat codex4)"
  [ -n "$ledger_destination" ] || die "host self-test could not read the codex4 ledger destination"
  case ",$ledger_destination," in
    *,id=*) ledger_after_id="${ledger_destination#*,id=}" ;;
    *) die "host self-test found no simulator id in the codex4 ledger destination" ;;
  esac
  ledger_uuid="${ledger_after_id%%,*}"
  is_core_simulator_uuid "$ledger_uuid" || die "host self-test rejected the valid codex4 ledger UUID"
  ! is_core_simulator_uuid "00000000-0000-0000-0000-00000000000" ||
    die "host self-test accepted an 8-4-4-4-11 UUID"

  alternate_destination="$(ledger_destination_for_seat codex1)"
  alternate_uuid="${alternate_destination#*,id=}"
  alternate_uuid="${alternate_uuid%%,*}"
  is_core_simulator_uuid "$alternate_uuid" || die "host self-test could not read a valid alternate ledger UUID"
  provenance_test_dir="$(mktemp -d /private/tmp/making-tracks-press-provenance.XXXXXX)"
  mock_bin="$provenance_test_dir/bin"
  diagnostic_file="$provenance_test_dir/diagnostic.txt"
  external_call_log="$provenance_test_dir/external-calls.txt"
  mkdir -p "$mock_bin"
  # shellcheck disable=SC2016 # The generated shim expands this in its child process.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo xcrun >> "$MT_PRESS_EXTERNAL_CALL_LOG"' \
    'exit 97' > "$mock_bin/xcrun"
  chmod +x "$mock_bin/xcrun"
  if MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$alternate_uuid" \
    MT_SIM_LOCK_DESTINATION="$alternate_destination" \
    MT_RELEASE_GATE_DERIVED_DATA="$HOME/Library/Caches/making-tracks-gates/codex4" \
    MT_PRESS_EXTERNAL_CALL_LOG="$external_call_log" \
    PATH="$mock_bin:$PATH" \
      /bin/bash "$repo_root/docs/design/design-system/regenerate-place-card-press-inset.sh" \
        > /dev/null 2> "$diagnostic_file"; then
    die "host self-test accepted the valid non-codex4 seat"
  else
    provenance_status=$?
  fi
  [ "$provenance_status" = "1" ] || die "host self-test wrong-seat status was $provenance_status, expected 1"
  [ "$(cat "$diagnostic_file")" = "regenerate-place-card-press-inset: runtime seat must match codex4 ledger UUID $ledger_uuid" ] ||
    die "host self-test did not receive the codex4 provenance diagnostic"
  [ ! -e "$external_call_log" ] || die "host self-test made an external simulator call before rejecting the wrong seat"
  rm -rf "$provenance_test_dir"
  echo "PASS valid-ledger-uuid"
}

host_self_test_requested=0
if [ "${1:-}" = "--self-test" ]; then
  [ "$#" = "1" ] || die "--self-test takes no other arguments"
  host_self_test_requested=1
elif [ "${1:-}" = "--self-test-signal-child" ]; then
  [ "$#" = "2" ] || die "--self-test-signal-child requires one directory"
  signal_self_test_dir="$2"
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

focused_gate_failure_message() {
  local label="$1"
  local gate_status="$2"

  echo "focused $label test command failed gate_status=$gate_status"
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

  # shellcheck disable=SC2329 # Invoked by the EXIT trap below.
  cleanup_timeout_self_test() {
    if [ -n "$spawned_pid" ]; then
      terminate_and_reap "$spawned_pid" >/dev/null 2>&1 || true
    fi
    [ -d "$selftest_dir" ] && rm -rf "$selftest_dir"
  }
  trap cleanup_timeout_self_test EXIT

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

  final_diagnostic="regenerate-place-card-press-inset: $(focused_gate_failure_message default 65)"
  [ "$final_diagnostic" = "regenerate-place-card-press-inset: focused default test command failed gate_status=65" ] ||
    die "host self-test did not receive the focused gate status diagnostic"

  screenshot_timeout_seconds="$saved_timeout"
  termination_grace_seconds="$saved_grace"
  case "$saved_errexit" in
    enabled) set -e ;;
    disabled) set +e ;;
  esac
  assert_errexit_state "$saved_errexit"
  echo "PASS screenshot-timeout-reap"
)

run_signal_cleanup_self_test() (
  local asset
  local child_pid
  local child_status=0
  local deadline
  local now
  local selftest_dir
  local test_assets=(one.png two.png three.png four.png)

  selftest_dir="$(mktemp -d /private/tmp/making-tracks-press-signal.XXXXXX)"
  mkdir -p "$selftest_dir/expected" "$selftest_dir/output"
  for asset in "${test_assets[@]}"; do
    printf 'prior-%s\n' "$asset" > "$selftest_dir/expected/$asset"
    cp "$selftest_dir/expected/$asset" "$selftest_dir/output/$asset"
  done

  /bin/bash "$repo_root/docs/design/design-system/regenerate-place-card-press-inset.sh" \
    --self-test-signal-child "$selftest_dir" &
  child_pid=$!
  deadline=$(( $(date +%s) + 5 ))
  while [ ! -e "$selftest_dir/partial-install.ready" ]; do
    if ! kill -0 "$child_pid" 2>/dev/null; then
      wait "$child_pid" 2>/dev/null || true
      rm -rf "$selftest_dir"
      die "host self-test signal child exited before the partial install"
    fi
    now="$(date +%s)"
    if [ "$now" -ge "$deadline" ]; then
      kill -KILL "$child_pid" 2>/dev/null || true
      wait "$child_pid" 2>/dev/null || true
      rm -rf "$selftest_dir"
      die "host self-test timed out waiting for the partial install"
    fi
    sleep 1
  done
  kill -TERM "$child_pid"
  if wait "$child_pid"; then
    child_status=0
  else
    child_status=$?
  fi
  [ "$(awk 'END { print NR }' "$selftest_dir/cleanup-count.txt")" = "1" ] ||
    die "host self-test cleanup did not run exactly once"
  for asset in "${test_assets[@]}"; do
    cmp -s "$selftest_dir/expected/$asset" "$selftest_dir/output/$asset" ||
      die "host self-test did not restore $asset byte-identically"
  done
  [ "$child_status" = "143" ] || die "host self-test signal child status was $child_status, expected 143"
  rm -rf "$selftest_dir"
  echo "PASS signal-cleanup-rollback"
)

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

cleanup_once() {
  [ "$cleanup_ran" = "0" ] || return 0
  cleanup_ran=1
  trap - EXIT INT TERM
  if [ -n "$cleanup_count_file" ]; then
    printf 'cleanup\n' >> "$cleanup_count_file"
  fi
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
}

handle_exit() {
  local exit_status=$?
  cleanup_once
  exit "$exit_status"
}

handle_signal() {
  local signal_status="$1"
  cleanup_once
  exit "$signal_status"
}

install_cleanup_traps() {
  trap handle_exit EXIT
  trap 'handle_signal 130' INT
  trap 'handle_signal 143' TERM
}

if [ "$host_self_test_requested" = "1" ]; then
  run_host_self_test
  run_timeout_self_test
  run_signal_cleanup_self_test
  exit 0
fi

if [ -n "$signal_self_test_dir" ]; then
  case "$signal_self_test_dir" in
    /private/tmp/making-tracks-press-signal.*) ;;
    *) die "host self-test signal child refused an unsafe directory" ;;
  esac
  output_dir="$signal_self_test_dir/output"
  backup_dir="$signal_self_test_dir/backup"
  cleanup_count_file="$signal_self_test_dir/cleanup-count.txt"
  assets=(one.png two.png three.png four.png)
  mkdir -p "$backup_dir"
  for asset in "${assets[@]}"; do
    cp -p "$output_dir/$asset" "$backup_dir/$asset"
  done
  install_started=1
  install_completed=0
  install_cleanup_traps
  printf 'replacement-one\n' > "$output_dir/one.png"
  printf 'replacement-two\n' > "$output_dir/two.png"
  : > "$signal_self_test_dir/partial-install.ready"
  while :; do sleep 1; done
fi

install_cleanup_traps

[ "${MT_SIM_LOCK:-}" = "1" ] || die "must run inside scripts/sim-lock.sh --seat codex4"
[ -n "$destination" ] || die "MT_SIM_LOCK_DESTINATION is required"
[ -n "$lock_udid" ] || die "MT_SIM_LOCK_UDID is required"
[ "$derived_data" = "$HOME/Library/Caches/making-tracks-gates/codex4" ] || die "MT_RELEASE_GATE_DERIVED_DATA must be $HOME/Library/Caches/making-tracks-gates/codex4"
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
codex4_ledger_uuid="$(ledger_uuid_for_seat codex4)"
[ "$lock_udid" = "$codex4_ledger_uuid" ] ||
  die "runtime seat must match codex4 ledger UUID $codex4_ledger_uuid"

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
      MakingTracksTests/AppShellTests/testPlaceCardActionStyleMountsQuietTextInsetOnlyWhereRuled \
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
  [ "$gate_status" = "0" ] || die "$(focused_gate_failure_message "$current_label" "$gate_status")"
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
set +e
growth_validation="$(xcrun swift "$analyzer" --validate-growth \
  --default "$default_displacement" \
  --ax "$ax_displacement" 2>&1)"
growth_validation_status=$?
set -e
case "$growth_validation_status:$growth_validation" in
  "0:RESULT displacement-growth default=$default_displacement ax=$ax_displacement") ;;
  "1:measure-place-card-press: default displacement must be positive")
    die "default displacement must be positive"
    ;;
  "1:measure-place-card-press: AX displacement must exceed default")
    die "AX displacement must exceed default"
    ;;
  *) die "analyzer growth validation failed status=$growth_validation_status: $growth_validation" ;;
esac

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
