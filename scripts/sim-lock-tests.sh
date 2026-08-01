#!/usr/bin/env bash
# Behavioral tests for simulator locking and release-gate seat isolation.
#
# The status tests prove either evidence signal is sufficient. The concurrency
# tests exercise real flock ordering across subprocesses, and the release-gate
# tests stub only external git/Xcode boundaries.
#
#   ./scripts/sim-lock-tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SIM_LOCK="$HERE/sim-lock.sh"
RELEASE_GATE="$HERE/release-gate.sh"
TMP="$(mktemp -d)"
LOCK_ROOT="$TMP/locks"
FAKE_UDID="11111111-1111-4111-8111-111111111111"
LOCK="$LOCK_ROOT/making-tracks-sim-$FAKE_UDID.lock"
FLOCK_BIN="/opt/homebrew/bin/flock"
RELEASE_FIXTURE_SEAT="sim-lock-test-$$"
RELEASE_LEGACY_RUN_DIR="/private/tmp/release-gate-$RELEASE_FIXTURE_SEAT"
RELEASE_PID_HEX="$(printf '%012X' "$$")"
RELEASE_UDID_A="AAAAAAAA-AAAA-4AAA-8AAA-$RELEASE_PID_HEX"
RELEASE_UDID_B="BBBBBBBB-BBBB-4BBB-8BBB-$RELEASE_PID_HEX"
RELEASE_RUN_DIR_A="/private/tmp/release-gate-$RELEASE_UDID_A"
RELEASE_RUN_DIR_B="/private/tmp/release-gate-$RELEASE_UDID_B"
RELEASE_MARKERS="$TMP/release-markers"
TEST_LEDGER="$TMP/ios-gate-ledger.md"

write_test_ledger() {
  local path="$1"
  local destination="$2"
  shift 2

  {
    printf '%s\n' \
      '# iOS Gate Ledger' \
      '' \
      '## Host Gate Seats' \
      '' \
      '| Seat | Simulator | Destination |' \
      '|---|---|---|' \
      "| \`codex1\` | \`mt-gate-codex1\` | \`$destination\` |"
    [ "$#" -eq 0 ] || printf '%s\n' "$@"
  } >"$path"
}

write_test_ledger "$TEST_LEDGER" "platform=iOS Simulator,id=$FAKE_UDID"

pass=0; fail=0
cleanup() {
  local child
  local started

  if [ -d "$TMP" ]; then
    if [ -f "$RELEASE_MARKERS" ]; then
      while IFS= read -r started; do
        [ -z "$started" ] || touch "$started"
      done <"$RELEASE_MARKERS"
    fi
  fi
  sleep 0.05
  for child in $(jobs -pr); do
    kill "$child" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  rm -rf \
    "$TMP" \
    "$RELEASE_LEGACY_RUN_DIR" \
    "$RELEASE_RUN_DIR_A" \
    "$RELEASE_RUN_DIR_B"
}
trap cleanup EXIT

run_status() {
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  "$SIM_LOCK" --seat codex1 --status 2>&1
}

run_locked() {
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  "$SIM_LOCK" --seat codex1 "$@" 2>&1
}

run_erase() {
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  "$SIM_LOCK" --seat codex1 --erase 2>&1
}

run_gate_for() {
  local udid="$1"
  shift

  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$udid" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  MT_GATE_MAX_CONCURRENT="${MT_GATE_MAX_CONCURRENT:-2}" \
  MT_SIM_LOCK_WAIT=5 \
  "$SIM_LOCK" --seat codex1 "$@"
}

wait_for_path() {
  local path="$1"
  local remaining=150

  while [ "$remaining" -gt 0 ]; do
    [ -e "$path" ] && return 0
    sleep 0.02
    remaining=$((remaining-1))
  done
  return 1
}

wait_for_pattern() {
  local path="$1"
  local pattern="$2"
  local remaining=150

  while [ "$remaining" -gt 0 ]; do
    if [ -f "$path" ] && grep -q -- "$pattern" "$path"; then
      return 0
    fi
    sleep 0.02
    remaining=$((remaining-1))
  done
  return 1
}

record_ok() {
  echo "  ok    $1"
  pass=$((pass+1))
}

record_fail() {
  echo "  FAIL  $1"
  [ -z "${2:-}" ] || echo "        $2"
  fail=$((fail+1))
}

register_release() {
  printf '%s\n' "$1.release" >>"$RELEASE_MARKERS"
}

start_holder() {
  local udid="$1"
  local marker="$2"

  # shellcheck disable=SC2016 # Expanded by the child sh, not this harness.
  run_gate_for "$udid" sh -c '
    touch "$1.started"
    while [ ! -e "$1.release" ]; do sleep 0.02; done
    touch "$1.finished"
  ' sh "$marker"
}

start_default_cap_holder() {
  local udid="$1"
  local marker="$2"

  # shellcheck disable=SC2016 # Expanded by the child sh, not this harness.
  env -u MT_GATE_MAX_CONCURRENT \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_UDID="$udid" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    MT_SIM_LOCK_WAIT=5 \
    "$SIM_LOCK" --seat codex1 sh -c '
      touch "$1.started"
      while [ ! -e "$1.release" ]; do sleep 0.02; done
      touch "$1.finished"
    ' sh "$marker"
}

check() {
  local actual
  local actual_rc
  local expected="$2"
  local expected_rc="$3"
  local name="$1"

  actual_rc=0
  actual="$(run_status)" || actual_rc=$?
  if echo "$actual" | head -1 | grep -qx -- "$expected" &&
     [ "$actual_rc" -eq "$expected_rc" ]; then
    echo "  ok    $name"
    pass=$((pass+1))
  else
    echo "  FAIL  $name"
    echo "        expected first line/status: $expected/$expected_rc"
    echo "        got: $(echo "$actual" | head -1)/$actual_rc"
    fail=$((fail+1))
  fi
}

mkdir -p "$LOCK_ROOT"

echo "sim-lock seat contract:"

set +e
legacy_destination_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
    "$SIM_LOCK" true 2>&1
)"
legacy_destination_rc=$?
set -e
if [ "$legacy_destination_rc" -ne 0 ] &&
   echo "$legacy_destination_out" | grep -q -- "--seat <seat> is required"; then
  record_ok "rejects the removed destination environment invocation"
else
  record_fail "rejects the removed destination environment invocation" \
    "status=$legacy_destination_rc output='$(echo "$legacy_destination_out" | head -1)'"
fi

echo
echo "live simulator consumer contract:"

consumer_scripts=(
  "$HERE/../docs/design/design-system/capture-t2.8-implementation.sh"
  "$HERE/../docs/design/design-system/regenerate-t2.3-door-glyph.sh"
  "$HERE/../docs/design/design-system/regenerate-t2.9-settings.sh"
  "$HERE/../docs/design/design-system/regenerate-t2.10-about.sh"
)

for consumer in "${consumer_scripts[@]}"; do
  consumer_name="$(basename "$consumer")"
  set +e
  consumer_out="$(
    env -u MT_SIM_LOCK_DESTINATION -u MT_SIM_LOCK -u MT_SIM_LOCK_UDID \
      MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
      "$consumer" 2>&1
  )"
  consumer_rc=$?
  set -e
  if [ "$consumer_rc" -ne 0 ] &&
     echo "$consumer_out" | grep -q "MT_SIM_LOCK_DESTINATION is required"; then
    record_ok "$consumer_name ignores the removed public destination"
  else
    record_fail "$consumer_name ignores the removed public destination" \
      "status=$consumer_rc output='$(echo "$consumer_out" | head -1)'"
  fi
done

for consumer in "${consumer_scripts[@]}"; do
  consumer_name="$(basename "$consumer")"
  set +e
  consumer_out="$(
    env -u MT_RELEASE_GATE_DESTINATION -u MT_SIM_LOCK -u MT_SIM_LOCK_UDID \
      MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
      MT_RELEASE_GATE_DERIVED_DATA=/private/tmp/dd-consumer-contract \
      "$consumer" 2>&1
  )"
  consumer_rc=$?
  set -e
  if [ "$consumer_rc" -ne 0 ] &&
     echo "$consumer_out" | grep -q \
       "invoke through scripts/sim-lock.sh --seat <seat>"; then
    record_ok "$consumer_name rejects an unowned simulator destination"
  else
    record_fail "$consumer_name rejects an unowned simulator destination" \
      "status=$consumer_rc output='$(echo "$consumer_out" | head -1)'"
  fi
done

CONSUMER_FAKE_BIN="$TMP/consumer-fake-bin"
CONSUMER_CALL_LOG="$TMP/consumer-calls.log"
mkdir -p "$CONSUMER_FAKE_BIN"
# shellcheck disable=SC2016 # Expanded when the fake xcrun program runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "xcrun:%s\n" "$*" >>"$MT_TEST_CONSUMER_CALL_LOG"' \
  'if [ "$*" = "simctl bootstatus $MT_SIM_LOCK_UDID -b" ]; then exit 0; fi' \
  'exit 97' \
  >"$CONSUMER_FAKE_BIN/xcrun"
# shellcheck disable=SC2016 # Expanded when the fake xcodebuild program runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "${1:-}" = "-version" ]; then' \
  '  printf "Xcode 26.6\nBuild version 17F113\n"' \
  '  exit 0' \
  'fi' \
  'printf "xcodebuild:%s\n" "$*" >>"$MT_TEST_CONSUMER_CALL_LOG"' \
  'exit 97' \
  >"$CONSUMER_FAKE_BIN/xcodebuild"
chmod +x "$CONSUMER_FAKE_BIN/xcrun" "$CONSUMER_FAKE_BIN/xcodebuild"

for consumer in "${consumer_scripts[@]}"; do
  consumer_name="$(basename "$consumer")"
  : >"$CONSUMER_CALL_LOG"
  set +e
  PATH="$CONSUMER_FAKE_BIN:$PATH" \
    MT_TEST_CONSUMER_CALL_LOG="$CONSUMER_CALL_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$FAKE_UDID" \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
    MT_RELEASE_GATE_DERIVED_DATA=/private/tmp/dd-consumer-contract \
    "$consumer" >/dev/null 2>&1
  consumer_rc=$?
  set -e
  first_simctl_call="$(grep '^xcrun:simctl ' "$CONSUMER_CALL_LOG" | head -1 || true)"
  if [ "$consumer_rc" -eq 97 ] &&
     [ "$first_simctl_call" = "xcrun:simctl bootstatus $FAKE_UDID -b" ]; then
    record_ok "$consumer_name boots its locked seat before simulator use"
  else
    record_fail "$consumer_name boots its locked seat before simulator use" \
      "status=$consumer_rc first_simctl='$first_simctl_call' calls='$(tr '\n' ';' <"$CONSUMER_CALL_LOG")'"
  fi
done

set +e
unknown_seat_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex5 true 2>&1
)"
unknown_seat_rc=$?
set -e
if [ "$unknown_seat_rc" -ne 0 ] &&
   echo "$unknown_seat_out" | grep -q "unknown seat: codex5"; then
  record_ok "rejects a seat outside the bounded fleet"
else
  record_fail "rejects a seat outside the bounded fleet" \
    "status=$unknown_seat_rc output='$(echo "$unknown_seat_out" | head -1)'"
fi

MISSING_SEAT_LEDGER="$TMP/missing-seat-ledger.md"
# shellcheck disable=SC2016 # Backticks are literal Markdown code spans.
printf '%s\n' \
  '# iOS Gate Ledger' \
  '' \
  '## Host Gate Seats' \
  '' \
  '| Seat | Simulator | Destination |' \
  '|---|---|---|' \
  '| `codex2` | `mt-gate-codex2` | `platform=iOS Simulator,id=OTHER-UDID` |' \
  >"$MISSING_SEAT_LEDGER"
set +e
missing_seat_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$MISSING_SEAT_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
missing_seat_rc=$?
set -e
if [ "$missing_seat_rc" -ne 0 ] &&
   echo "$missing_seat_out" | grep -q "seat codex1 must appear exactly once"; then
  record_ok "fails closed when the selected seat is missing from the ledger"
else
  record_fail "fails closed when the selected seat is missing from the ledger" \
    "status=$missing_seat_rc output='$(echo "$missing_seat_out" | head -1)'"
fi

DUPLICATE_SEAT_LEDGER="$TMP/duplicate-seat-ledger.md"
write_test_ledger "$DUPLICATE_SEAT_LEDGER" \
  "platform=iOS Simulator,id=$FAKE_UDID" \
  "| \`codex1\` | \`mt-gate-codex1-copy\` | \`platform=iOS Simulator,id=OTHER-UDID\` |"
set +e
duplicate_seat_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$DUPLICATE_SEAT_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
duplicate_seat_rc=$?
set -e
if [ "$duplicate_seat_rc" -ne 0 ] &&
   echo "$duplicate_seat_out" | grep -q "seat codex1 must appear exactly once"; then
  record_ok "fails closed when the selected seat is duplicated in the ledger"
else
  record_fail "fails closed when the selected seat is duplicated in the ledger" \
    "status=$duplicate_seat_rc output='$(echo "$duplicate_seat_out" | head -1)'"
fi

SCOPED_SEAT_LEDGER="$TMP/scoped-seat-ledger.md"
# shellcheck disable=SC2016 # Backticks are literal Markdown code spans.
write_test_ledger "$SCOPED_SEAT_LEDGER" \
  "platform=iOS Simulator,id=$FAKE_UDID" \
  '' \
  '## Classification Examples' \
  '' \
  '| Seat | Simulator | Destination |' \
  '|---|---|---|' \
  '| `codex1` | `decoy` | `platform=iOS Simulator,id=DECOY-UDID` |'
set +e
scoped_seat_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$SCOPED_SEAT_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
scoped_seat_rc=$?
set -e
if [ "$scoped_seat_rc" -eq 0 ]; then
  record_ok "ignores seat-shaped rows outside the Host Gate Seats table"
else
  record_fail "ignores seat-shaped rows outside the Host Gate Seats table" \
    "status=$scoped_seat_rc output='$(echo "$scoped_seat_out" | head -1)'"
fi

MALFORMED_ROW_LEDGER="$TMP/malformed-row-ledger.md"
# shellcheck disable=SC2016 # Backticks are literal Markdown code spans.
printf '%s\n' \
  '# iOS Gate Ledger' \
  '' \
  '## Host Gate Seats' \
  '' \
  '| Seat | Simulator | Destination |' \
  '|---|---|---|' \
  "| \`codex1\` | \`mt-gate-codex1\` | \`platform=iOS Simulator,id=$FAKE_UDID\` | unexpected |" \
  >"$MALFORMED_ROW_LEDGER"
set +e
malformed_row_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$MALFORMED_ROW_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
malformed_row_rc=$?
set -e
if [ "$malformed_row_rc" -ne 0 ] &&
   echo "$malformed_row_out" | grep -q "malformed Host Gate Seats table"; then
  record_ok "fails closed on malformed Host Gate Seats row geometry"
else
  record_fail "fails closed on malformed Host Gate Seats row geometry" \
    "status=$malformed_row_rc output='$(echo "$malformed_row_out" | head -1)'"
fi

DECOY_ONLY_LEDGER="$TMP/decoy-only-ledger.md"
# shellcheck disable=SC2016 # Backticks are literal Markdown code spans.
printf '%s\n' \
  '# iOS Gate Ledger' \
  '' \
  '## Classification Examples' \
  '' \
  '| Seat | Simulator | Destination |' \
  '|---|---|---|' \
  "| \`codex1\` | \`decoy\` | \`platform=iOS Simulator,id=$FAKE_UDID\` |" \
  >"$DECOY_ONLY_LEDGER"
set +e
decoy_only_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$DECOY_ONLY_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
decoy_only_rc=$?
set -e
if [ "$decoy_only_rc" -ne 0 ] &&
   echo "$decoy_only_out" | grep -q "malformed Host Gate Seats table"; then
  record_ok "rejects a ledger with no Host Gate Seats table"
else
  record_fail "rejects a ledger with no Host Gate Seats table" \
    "status=$decoy_only_rc output='$(echo "$decoy_only_out" | head -1)'"
fi

FLEET_SELECTOR_LEDGER="$TMP/fleet-selector-ledger.md"
write_test_ledger "$FLEET_SELECTOR_LEDGER" "platform=iOS Simulator,id=all"
set +e
fleet_selector_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$FLEET_SELECTOR_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
fleet_selector_rc=$?
set -e
if [ "$fleet_selector_rc" -ne 0 ] &&
   echo "$fleet_selector_out" | grep -q "valid CoreSimulator UUID"; then
  record_ok "rejects fleet-wide selectors in a seat destination"
else
  record_fail "rejects fleet-wide selectors in a seat destination" \
    "status=$fleet_selector_rc output='$(echo "$fleet_selector_out" | head -1)'"
fi

CLI_FAKE_BIN="$TMP/cli-fake-bin"
CLI_XCODEBUILD_LOG="$TMP/cli-xcodebuild.log"
CLI_SIMCTL_LOG="$TMP/cli-simctl.log"
mkdir -p "$CLI_FAKE_BIN"
# shellcheck disable=SC2016 # Expanded when the fake xcodebuild program runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >"$MT_TEST_XCODEBUILD_LOG"' \
  >"$CLI_FAKE_BIN/xcodebuild"
# shellcheck disable=SC2016 # Expanded when the fake xcrun program runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >"$MT_TEST_SIMCTL_LOG"' \
  >"$CLI_FAKE_BIN/xcrun"
chmod +x "$CLI_FAKE_BIN/xcodebuild" "$CLI_FAKE_BIN/xcrun"
set +e
injected_destination_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcodebuild test 2>&1
)"
injected_destination_rc=$?
set -e
if [ "$injected_destination_rc" -eq 0 ] &&
   [ "$(<"$CLI_XCODEBUILD_LOG")" = \
     "test -destination platform=iOS Simulator,id=$FAKE_UDID" ]; then
  record_ok "injects the selected seat destination into xcodebuild"
else
  record_fail "injects the selected seat destination into xcodebuild" \
    "status=$injected_destination_rc output='$injected_destination_out' args='$(head -1 "$CLI_XCODEBUILD_LOG" 2>/dev/null)'"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
matching_destination_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcodebuild test \
      -destination "platform=iOS Simulator,id=$FAKE_UDID" 2>&1
)"
matching_destination_rc=$?
set -e
if [ "$matching_destination_rc" -eq 0 ] &&
   [ "$(<"$CLI_XCODEBUILD_LOG")" = \
     "test -destination platform=iOS Simulator,id=$FAKE_UDID" ]; then
  record_ok "preserves an explicit matching xcodebuild destination"
else
  record_fail "preserves an explicit matching xcodebuild destination" \
    "status=$matching_destination_rc output='$matching_destination_out' args='$(head -1 "$CLI_XCODEBUILD_LOG" 2>/dev/null)'"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
same_udid_different_destination_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcodebuild test \
      -destination "platform=iOS Simulator,name=retired,id=$FAKE_UDID" 2>&1
)"
same_udid_different_destination_rc=$?
set -e
if [ "$same_udid_different_destination_rc" -ne 0 ] &&
   echo "$same_udid_different_destination_out" | grep -q \
     "does not exactly match seat codex1 destination" &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "rejects a same-UDID xcodebuild destination that differs from the seat"
else
  record_fail "rejects a same-UDID xcodebuild destination that differs from the seat" \
    "status=$same_udid_different_destination_rc output='$(echo "$same_udid_different_destination_out" | head -1)'"
fi

set +e
injected_simctl_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcrun simctl launch com.example.MakingTracks 2>&1
)"
injected_simctl_rc=$?
set -e
if [ "$injected_simctl_rc" -eq 0 ] &&
   [ "$(<"$CLI_SIMCTL_LOG")" = \
     "simctl launch $FAKE_UDID com.example.MakingTracks" ]; then
  record_ok "injects the selected seat UUID into target-taking simctl verbs"
else
  record_fail "injects the selected seat UUID into target-taking simctl verbs" \
    "status=$injected_simctl_rc output='$injected_simctl_out' args='$(head -1 "$CLI_SIMCTL_LOG" 2>/dev/null)'"
fi

rm -f "$CLI_SIMCTL_LOG"
set +e
injected_simctl_erase_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcrun simctl erase 2>&1
)"
injected_simctl_erase_rc=$?
set -e
if [ "$injected_simctl_erase_rc" -eq 0 ] &&
   [ "$(<"$CLI_SIMCTL_LOG")" = "simctl erase $FAKE_UDID" ]; then
  record_ok "injects the selected seat UUID into simctl erase"
else
  record_fail "injects the selected seat UUID into simctl erase" \
    "status=$injected_simctl_erase_rc output='$injected_simctl_erase_out' args='$(head -1 "$CLI_SIMCTL_LOG" 2>/dev/null)'"
fi

OTHER_SEAT_UDID="22222222-2222-4222-8222-222222222222"
rm -f "$CLI_SIMCTL_LOG"
set +e
explicit_simctl_target_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcrun simctl launch \
      "$OTHER_SEAT_UDID" com.example.MakingTracks 2>&1
)"
explicit_simctl_target_rc=$?
set -e
if [ "$explicit_simctl_target_rc" -ne 0 ] &&
   echo "$explicit_simctl_target_out" | grep -q \
     "omit the simulator target after simctl launch" &&
   [ ! -e "$CLI_SIMCTL_LOG" ]; then
  record_ok "rejects an explicit positional simctl simulator target"
else
  record_fail "rejects an explicit positional simctl simulator target" \
    "status=$explicit_simctl_target_rc output='$(echo "$explicit_simctl_target_out" | head -1)'"
fi

rm -f "$CLI_SIMCTL_LOG"
set +e
injected_simctl_boot_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcrun simctl boot 2>&1
)"
injected_simctl_boot_rc=$?
set -e
if [ "$injected_simctl_boot_rc" -eq 0 ] &&
   [ "$(<"$CLI_SIMCTL_LOG")" = "simctl boot $FAKE_UDID" ]; then
  record_ok "injects the selected seat UUID into simctl boot"
else
  record_fail "injects the selected seat UUID into simctl boot" \
    "status=$injected_simctl_boot_rc output='$injected_simctl_boot_out' args='$(head -1 "$CLI_SIMCTL_LOG" 2>/dev/null)'"
fi

rm -f "$CLI_SIMCTL_LOG"
set +e
explicit_simctl_boot_target_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcrun simctl boot "$OTHER_SEAT_UDID" 2>&1
)"
explicit_simctl_boot_target_rc=$?
set -e
if [ "$explicit_simctl_boot_target_rc" -ne 0 ] &&
   echo "$explicit_simctl_boot_target_out" | grep -q \
     "omit the simulator target after simctl boot" &&
   [ ! -e "$CLI_SIMCTL_LOG" ]; then
  record_ok "rejects an explicit positional simctl boot target"
else
  record_fail "rejects an explicit positional simctl boot target" \
    "status=$explicit_simctl_boot_target_rc output='$(echo "$explicit_simctl_boot_target_out" | head -1)'"
fi

rm -f "$CLI_SIMCTL_LOG"
set +e
explicit_simctl_erase_target_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcrun simctl erase "$OTHER_SEAT_UDID" 2>&1
)"
explicit_simctl_erase_target_rc=$?
set -e
if [ "$explicit_simctl_erase_target_rc" -ne 0 ] &&
   echo "$explicit_simctl_erase_target_out" | grep -q \
     "omit the simulator target after simctl erase" &&
   [ ! -e "$CLI_SIMCTL_LOG" ]; then
  record_ok "rejects an explicit positional simctl erase target"
else
  record_fail "rejects an explicit positional simctl erase target" \
    "status=$explicit_simctl_erase_target_rc output='$(echo "$explicit_simctl_erase_target_out" | head -1)'"
fi

rm -f "$CLI_SIMCTL_LOG"
set +e
injected_simctl_delete_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcrun simctl delete 2>&1
)"
injected_simctl_delete_rc=$?
set -e
if [ "$injected_simctl_delete_rc" -eq 0 ] &&
   [ "$(<"$CLI_SIMCTL_LOG")" = "simctl delete $FAKE_UDID" ]; then
  record_ok "injects the selected seat UUID into simctl delete"
else
  record_fail "injects the selected seat UUID into simctl delete" \
    "status=$injected_simctl_delete_rc output='$injected_simctl_delete_out' args='$(head -1 "$CLI_SIMCTL_LOG" 2>/dev/null)'"
fi

for explicit_delete_target in "$OTHER_SEAT_UDID" all; do
  rm -f "$CLI_SIMCTL_LOG"
  explicit_simctl_delete_target_rc=0
  explicit_simctl_delete_target_out="$(
    PATH="$CLI_FAKE_BIN:$PATH" \
      MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
      MT_SIM_LOCK_TEST_MODE=1 \
      MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
      MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
      "$SIM_LOCK" --seat codex1 xcrun simctl delete \
        "$explicit_delete_target" 2>&1
  )" || explicit_simctl_delete_target_rc=$?
  if [ "$explicit_simctl_delete_target_rc" -ne 0 ] &&
     echo "$explicit_simctl_delete_target_out" | grep -q \
       "omit the simulator target after simctl delete" &&
     [ ! -e "$CLI_SIMCTL_LOG" ]; then
    record_ok "rejects the positional simctl delete target $explicit_delete_target"
  else
    record_fail "rejects the positional simctl delete target $explicit_delete_target" \
      "status=$explicit_simctl_delete_target_rc output='$(echo "$explicit_simctl_delete_target_out" | head -1)'"
  fi
done

rm -f "$CLI_SIMCTL_LOG"
set +e
testing_set_delete_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcrun simctl --set testing delete all 2>&1
)"
testing_set_delete_rc=$?
set -e
if [ "$testing_set_delete_rc" -eq 0 ] &&
   [ "$(<"$CLI_SIMCTL_LOG")" = "simctl --set testing delete all" ]; then
  record_ok "leaves an explicit non-gate simulator set target unchanged"
else
  record_fail "leaves an explicit non-gate simulator set target unchanged" \
    "status=$testing_set_delete_rc output='$testing_set_delete_out' args='$(head -1 "$CLI_SIMCTL_LOG" 2>/dev/null)'"
fi

rm -f "$CLI_SIMCTL_LOG"
set +e
destructive_erase_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    MT_SIM_LOCK_FORCE_ERASE=1 \
    "$SIM_LOCK" --seat codex1 --erase 2>&1
)"
destructive_erase_rc=$?
set -e
if [ "$destructive_erase_rc" -eq 0 ] &&
   [ "$(<"$CLI_SIMCTL_LOG")" = "simctl erase $FAKE_UDID" ]; then
  record_ok "keeps --erase targeted to the selected seat"
else
  record_fail "keeps --erase targeted to the selected seat" \
    "status=$destructive_erase_rc output='$destructive_erase_out' args='$(head -1 "$CLI_SIMCTL_LOG" 2>/dev/null)'"
fi

for fleet_selector in all booted; do
  rm -f "$CLI_SIMCTL_LOG"
  fleet_simctl_target_rc=0
  fleet_simctl_target_out="$(
    PATH="$CLI_FAKE_BIN:$PATH" \
      MT_TEST_SIMCTL_LOG="$CLI_SIMCTL_LOG" \
      MT_SIM_LOCK_TEST_MODE=1 \
      MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
      MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
      "$SIM_LOCK" --seat codex1 xcrun simctl launch \
        "$fleet_selector" com.example.MakingTracks 2>&1
  )" || fleet_simctl_target_rc=$?
  if [ "$fleet_simctl_target_rc" -ne 0 ] &&
     echo "$fleet_simctl_target_out" | grep -q \
       "omit the simulator target after simctl launch" &&
     [ ! -e "$CLI_SIMCTL_LOG" ]; then
    record_ok "rejects the positional simctl $fleet_selector selector"
  else
    record_fail "rejects the positional simctl $fleet_selector selector" \
      "status=$fleet_simctl_target_rc output='$(echo "$fleet_simctl_target_out" | head -1)'"
  fi
done

# The harness intentionally starts without errexit; the focused rc assertions
# above toggle it only while capturing failures.
set +e
echo

echo "sim-lock --status:"

# 1. A seat that has never run has no lock path yet and is free.
check "free before the seat lock file has ever been created" "FREE" 0

# 2. Neither signal on an existing stable path — the only other case that may
#    report FREE.
touch "$LOCK"
check "free when nothing holds it and nothing uses the sim" "FREE" 0

# 3. Lock held, no process naming the UDID. This is the between-phases case:
#    a gate that has finished building and has not started testing.
"$FLOCK_BIN" -x "$LOCK" -c 'sleep 4' &
lock_pid=$!
sleep 0.5
check "held when the lock is taken but no process names the UDID" "HELD" 1
wait "$lock_pid" 2>/dev/null

# 4. Process using the simulator, lock NOT taken. This is the incident case:
#    a hand-check of the lock file reports FREE while work is in flight.
# Rename the process's argv so pgrep -f matches the UDID, the way a real
# xcodebuild destination argument would.
(exec -a "xcodebuild -destination platform=iOS Simulator,id=$FAKE_UDID" sleep 4) &
fake_pid=$!
sleep 0.5
check "held when the sim is in use WITHOUT the lock" "HELD" 1
kill "$fake_pid" 2>/dev/null
wait 2>/dev/null

# 5. CoreSimulator's idle launchd_sim process names the UDID but is not work.
#    Treating it as a holder wedges the shared simulator after every boot.
(exec -a "launchd_sim $FAKE_UDID" sleep 4) &
launchd_pid=$!
sleep 0.5
check "free when only idle launchd_sim names the UDID" "FREE" 0
kill "$launchd_pid" 2>/dev/null
wait 2>/dev/null

# 6. The warning fires on the dangerous case specifically.
(exec -a "xcodebuild -destination platform=iOS Simulator,id=$FAKE_UDID" sleep 3) &
warn_pid=$!
sleep 0.5
out="$(run_status)"
if echo "$out" | grep -q "WITHOUT the lock"; then
  echo "  ok    warns when in use without the lock"
  pass=$((pass+1))
else
  echo "  FAIL  warns when in use without the lock"
  fail=$((fail+1))
fi
kill "$warn_pid" 2>/dev/null
wait 2>/dev/null

# 7. Back to free once everything exits — proves the signals clear rather than
#    latching, so a stale HELD cannot wedge the fleet.
sleep 0.3
check "free again after holders exit" "FREE" 0

# 8. Process enumeration failure is not evidence that the simulator is idle.
#    If this branch returns FREE, destructive work can race an unknown holder.
PGREP_ERROR="$TMP/pgrep-error"
printf '%s\n' '#!/usr/bin/env bash' 'exit 2' >"$PGREP_ERROR"
chmod +x "$PGREP_ERROR"
set +e
pgrep_error_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  MT_SIM_LOCK_TEST_PGREP_BIN="$PGREP_ERROR" \
  "$SIM_LOCK" --seat codex1 --status 2>&1
)"
pgrep_error_rc=$?
set -e
if [ "$pgrep_error_rc" -ne 0 ] &&
   echo "$pgrep_error_out" | grep -q "cannot inspect simulator processes"; then
  record_ok "fails closed when simulator process enumeration fails"
else
  record_fail "fails closed when simulator process enumeration fails" \
    "status=$pgrep_error_rc output='$(echo "$pgrep_error_out" | head -1)'"
fi

PGREP_SUCCESS="$TMP/pgrep-success"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo 99999' \
  'exit 0' >"$PGREP_SUCCESS"
chmod +x "$PGREP_SUCCESS"
set +e
pgrep_success_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  MT_SIM_LOCK_TEST_PGREP_BIN="$PGREP_SUCCESS" \
  "$SIM_LOCK" --seat codex1 --status 2>&1
)"
pgrep_success_rc=$?
set -e
if [ "$pgrep_success_rc" -eq 1 ] &&
   echo "$pgrep_success_out" | grep -q "simulator in use by pid(s): 99999"; then
  record_ok "accepts silent successful process enumeration"
else
  record_fail "accepts silent successful process enumeration" \
    "status=$pgrep_success_rc output='$(echo "$pgrep_success_out" | head -2 | tr '\n' ' ')'"
fi

PGREP_WARNING="$TMP/pgrep-warning"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo 99999' \
  'echo "pgrep: warning: cannot read process table entry" >&2' \
  'exit 0' >"$PGREP_WARNING"
chmod +x "$PGREP_WARNING"
set +e
pgrep_warning_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  MT_SIM_LOCK_TEST_PGREP_BIN="$PGREP_WARNING" \
  "$SIM_LOCK" --seat codex1 --status 2>&1
)"
pgrep_warning_rc=$?
set -e
if [ "$pgrep_warning_rc" -ne 0 ] &&
   echo "$pgrep_warning_out" | grep -q "cannot inspect simulator processes.*pgrep: warning"; then
  record_ok "fails closed when successful process enumeration emits diagnostics"
else
  record_fail "fails closed when successful process enumeration emits diagnostics" \
    "status=$pgrep_warning_rc output='$(echo "$pgrep_warning_out" | head -2 | tr '\n' ' ')'"
fi

# Lock inspection errors are also unknown state, not evidence that the lock is
# free during the gap between xcodebuild phases.
PGREP_NONE="$TMP/pgrep-none"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$PGREP_NONE"
chmod +x "$PGREP_NONE"

LSOF_SUCCESS="$TMP/lsof-success"
printf '%s\n' '#!/usr/bin/env bash' 'echo 99999' 'exit 0' >"$LSOF_SUCCESS"
chmod +x "$LSOF_SUCCESS"
set +e
lsof_success_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  MT_SIM_LOCK_TEST_LSOF_BIN="$LSOF_SUCCESS" \
  MT_SIM_LOCK_TEST_PGREP_BIN="$PGREP_NONE" \
  "$SIM_LOCK" --seat codex1 --status 2>&1
)"
lsof_success_rc=$?
set -e
if [ "$lsof_success_rc" -eq 1 ] &&
   echo "$lsof_success_out" | grep -q "lock held by pid(s): 99999"; then
  record_ok "accepts silent successful lock inspection"
else
  record_fail "accepts silent successful lock inspection" \
    "status=$lsof_success_rc output='$(echo "$lsof_success_out" | head -2 | tr '\n' ' ')'"
fi

LSOF_SUCCESS_WARNING="$TMP/lsof-success-warning"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo 99999' \
  'echo "lsof: warning: partial file table" >&2' \
  'exit 0' >"$LSOF_SUCCESS_WARNING"
chmod +x "$LSOF_SUCCESS_WARNING"
set +e
lsof_success_warning_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  MT_SIM_LOCK_TEST_LSOF_BIN="$LSOF_SUCCESS_WARNING" \
  MT_SIM_LOCK_TEST_PGREP_BIN="$PGREP_NONE" \
  "$SIM_LOCK" --seat codex1 --status 2>&1
)"
lsof_success_warning_rc=$?
set -e
if [ "$lsof_success_warning_rc" -ne 0 ] &&
   echo "$lsof_success_warning_out" | grep -q "cannot inspect simulator lock.*lsof: warning"; then
  record_ok "fails closed when successful lock inspection emits diagnostics"
else
  record_fail "fails closed when successful lock inspection emits diagnostics" \
    "status=$lsof_success_warning_rc output='$(echo "$lsof_success_warning_out" | head -2 | tr '\n' ' ')'"
fi

LSOF_ERROR="$TMP/lsof-error"
printf '%s\n' '#!/usr/bin/env bash' 'exit 2' >"$LSOF_ERROR"
chmod +x "$LSOF_ERROR"
set +e
lsof_error_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  MT_SIM_LOCK_TEST_LSOF_BIN="$LSOF_ERROR" \
  "$SIM_LOCK" --seat codex1 --status 2>&1
)"
lsof_error_rc=$?
set -e
if [ "$lsof_error_rc" -ne 0 ] &&
   echo "$lsof_error_out" | grep -q "cannot inspect simulator lock"; then
  record_ok "fails closed when simulator lock inspection fails"
else
  record_fail "fails closed when simulator lock inspection fails" \
    "status=$lsof_error_rc output='$(echo "$lsof_error_out" | head -1)'"
fi

LSOF_RC1_ERROR="$TMP/lsof-rc1-error"
printf '%s\n' '#!/usr/bin/env bash' 'echo "lookup failed" >&2' 'exit 1' >"$LSOF_RC1_ERROR"
chmod +x "$LSOF_RC1_ERROR"
set +e
lsof_rc1_error_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  MT_SIM_LOCK_TEST_LSOF_BIN="$LSOF_RC1_ERROR" \
  "$SIM_LOCK" --seat codex1 --status 2>&1
)"
lsof_rc1_error_rc=$?
set -e
if [ "$lsof_rc1_error_rc" -ne 0 ] &&
   echo "$lsof_rc1_error_out" | grep -q "cannot inspect simulator lock"; then
  record_ok "fails closed when lsof returns status 1 with diagnostics"
else
  record_fail "fails closed when lsof returns status 1 with diagnostics" \
    "status=$lsof_rc1_error_rc output='$(echo "$lsof_rc1_error_out" | head -1)'"
fi

echo
echo "sim-lock --erase pre-flight:"

# 9. Erase refuses while the sim is in use without the lock — flock alone does
#    not protect against a lockless holder, which is the incident exactly.
(exec -a "xcodebuild -destination platform=iOS Simulator,id=$FAKE_UDID" sleep 3) &
erase_pid=$!
sleep 0.5
out="$(run_erase || true)"
if echo "$out" | grep -q "refusing to erase"; then
  echo "  ok    refuses to erase while the sim is in use"; pass=$((pass+1))
else
  echo "  FAIL  refuses to erase while the sim is in use"; fail=$((fail+1))
fi
kill "$erase_pid" 2>/dev/null; wait 2>/dev/null

echo
echo "sim-lock re-entrancy:"

# 10. A nested invocation must not re-flock, or it deadlocks on its own parent
#     with no output.
out="$(MT_SIM_LOCK_TEST_MODE=1 MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
       MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
       MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
       "$SIM_LOCK" --seat codex1 "$SIM_LOCK" --seat codex1 echo nested-ok 2>&1)" || true
if echo "$out" | grep -q "nested-ok"; then
  echo "  ok    nested invocation runs through instead of deadlocking"; pass=$((pass+1))
else
  echo "  FAIL  nested invocation runs through instead of deadlocking"
  echo "        got: $out"; fail=$((fail+1))
fi

# Re-entry is authority for one exact simulator, not a general bypass. Missing
# identity and a changed identity must both be rejected.
set +e
missing_reentry_out="$(
  env -u MT_SIM_LOCK_UDID \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_UDID="TEST-REENTRY-MISSING" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
missing_reentry_rc=$?
mismatched_reentry_out="$(
  MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="TEST-REENTRY-OUTER" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_UDID="TEST-REENTRY-INNER" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
mismatched_reentry_rc=$?
set -e
if [ "$missing_reentry_rc" -ne 0 ] &&
   echo "$missing_reentry_out" | grep -q "missing simulator identity"; then
  record_ok "rejects re-entry without the outer simulator identity"
else
  record_fail "rejects re-entry without the outer simulator identity" \
    "status=$missing_reentry_rc output='$missing_reentry_out'"
fi
if [ "$mismatched_reentry_rc" -ne 0 ] &&
   echo "$mismatched_reentry_out" | grep -q "changed simulator"; then
  record_ok "rejects re-entry for a different simulator"
else
  record_fail "rejects re-entry for a different simulator" \
    "status=$mismatched_reentry_rc output='$mismatched_reentry_out'"
fi

write_test_ledger "$TMP/malformed-ledger.md" \
  "platform=iOS Simulator,grid=NOT-AN-ID"
set +e
malformed_sim_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TMP/malformed-ledger.md" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
malformed_sim_rc=$?
set -e
if [ "$malformed_sim_rc" -ne 0 ] &&
   echo "$malformed_sim_out" | grep -q "must include id="; then
  record_ok "rejects a destination whose grid field merely ends in id"
else
  record_fail "rejects a destination whose grid field merely ends in id" \
    "status=$malformed_sim_rc output='$malformed_sim_out'"
fi

write_test_ledger "$TMP/duplicate-id-ledger.md" \
  "platform=iOS Simulator,id=FIRST,id=SECOND"
set +e
duplicate_id_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TMP/duplicate-id-ledger.md" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
duplicate_id_rc=$?
set -e
if [ "$duplicate_id_rc" -ne 0 ] &&
   echo "$duplicate_id_out" | grep -q "exactly one id="; then
  record_ok "rejects a destination containing multiple id fields"
else
  record_fail "rejects a destination containing multiple id fields" \
    "status=$duplicate_id_rc output='$duplicate_id_out'"
fi

set +e
mismatched_command_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_UDID="33333333-3333-4333-8333-333333333333" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcodebuild \
      -destination "platform=iOS Simulator,id=44444444-4444-4444-8444-444444444444" 2>&1
)"
mismatched_command_rc=$?
set -e
if [ "$mismatched_command_rc" -ne 0 ] &&
   echo "$mismatched_command_out" | grep -q "command targets simulator"; then
  record_ok "rejects a wrapped command targeting a different simulator"
else
  record_fail "rejects a wrapped command targeting a different simulator" \
    "status=$mismatched_command_rc output='$(echo "$mismatched_command_out" | head -1)'"
fi

set +e
bash32_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_UDID="TEST-BASH32" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    /bin/bash "$SIM_LOCK" --seat codex1 true 2>&1
)"
bash32_rc=$?
set -e
if [ "$bash32_rc" -eq 0 ]; then
  record_ok "runs with the macOS system Bash"
else
  record_fail "runs with the macOS system Bash" \
    "status=$bash32_rc output='$(echo "$bash32_out" | head -1)'"
fi

FLOCK_ERROR="$TMP/flock-error"
printf '%s\n' '#!/usr/bin/env bash' 'exit 2' >"$FLOCK_ERROR"
chmod +x "$FLOCK_ERROR"
set +e
flock_error_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_UDID="TEST-FLOCK-ERROR" \
    MT_SIM_LOCK_TEST_FLOCK_BIN="$FLOCK_ERROR" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
flock_error_rc=$?
set -e
if [ "$flock_error_rc" -ne 0 ] &&
   echo "$flock_error_out" | grep -q "flock status 2"; then
  record_ok "reports flock operational errors instead of calling them contention"
else
  record_fail "reports flock operational errors instead of calling them contention" \
    "status=$flock_error_rc output='$(echo "$flock_error_out" | head -1)'"
fi

FLOCK_SLOT_ERROR="$TMP/flock-slot-error"
FLOCK_SLOT_ERROR_COUNT="$TMP/flock-slot-error-count"
# shellcheck disable=SC2016 # Expanded when the fake flock program runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'count=0' \
  '[ ! -f "$MT_TEST_FLOCK_COUNT" ] || count="$(cat "$MT_TEST_FLOCK_COUNT")"' \
  'count=$((count + 1))' \
  'printf "%s\n" "$count" >"$MT_TEST_FLOCK_COUNT"' \
  '[ "$count" -le 2 ] && exit 0' \
  'exit 2' >"$FLOCK_SLOT_ERROR"
chmod +x "$FLOCK_SLOT_ERROR"
set +e
flock_slot_error_out="$(
  MT_TEST_FLOCK_COUNT="$FLOCK_SLOT_ERROR_COUNT" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_UDID="TEST-FLOCK-SLOT-ERROR" \
    MT_SIM_LOCK_TEST_FLOCK_BIN="$FLOCK_SLOT_ERROR" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 true 2>&1
)"
flock_slot_error_rc=$?
set -e
if [ "$flock_slot_error_rc" -ne 0 ] &&
   echo "$flock_slot_error_out" | grep -q "global gate slot.*flock status 2"; then
  record_ok "reports slot-level flock errors instead of polling them as contention"
else
  record_fail "reports slot-level flock errors instead of polling them as contention" \
    "status=$flock_slot_error_rc output='$(echo "$flock_slot_error_out" | head -1)'"
fi

echo
echo "sim-lock per-simulator concurrency:"

SAME_A="$TMP/same-a"
SAME_B="$TMP/same-b"
register_release "$SAME_A"
start_holder "TEST-SAME-SIM" "$SAME_A" >"$SAME_A.log" 2>&1 &
same_a_pid=$!
if wait_for_path "$SAME_A.started"; then
  run_gate_for "TEST-SAME-SIM" touch "$SAME_B.started" >"$SAME_B.log" 2>&1 &
  same_b_pid=$!
  if wait_for_pattern "$SAME_B.log" "waiting for" && [ ! -e "$SAME_B.started" ]; then
    record_ok "serializes two commands targeting the same simulator"
  else
    record_fail "serializes two commands targeting the same simulator" \
      "second command did not reach a blocked lock state"
  fi
  touch "$SAME_A.release"
  wait "$same_a_pid" 2>/dev/null
  if wait_for_path "$SAME_B.started"; then
    record_ok "runs the queued same-simulator command after release"
  else
    record_fail "runs the queued same-simulator command after release" \
      "second command was rejected or stayed queued after the first released"
  fi
  wait "$same_b_pid" 2>/dev/null
else
  record_fail "serializes two commands targeting the same simulator" \
    "first holder did not start"
  touch "$SAME_A.release"
  wait "$same_a_pid" 2>/dev/null
fi

# The lsof lookup on a contended simulator is only decoration for the waiting
# message. A normal no-match status with a benign diagnostic must not abort the
# queued command.
DIAGNOSTIC_UDID="TEST-DIAGNOSTIC-SIM"
DIAGNOSTIC_HOLDER="$TMP/diagnostic-holder"
DIAGNOSTIC_WAITER="$TMP/diagnostic-waiter"
LSOF_NO_MATCH_WARNING="$TMP/lsof-no-match-warning"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo "lsof: WARNING: cannot stat() nfs file system" >&2' \
  'exit 1' >"$LSOF_NO_MATCH_WARNING"
chmod +x "$LSOF_NO_MATCH_WARNING"
register_release "$DIAGNOSTIC_HOLDER"
start_holder "$DIAGNOSTIC_UDID" "$DIAGNOSTIC_HOLDER" >"$DIAGNOSTIC_HOLDER.log" 2>&1 &
diagnostic_holder_pid=$!
if wait_for_path "$DIAGNOSTIC_HOLDER.started"; then
  # shellcheck disable=SC2016 # Expanded by the child sh, not this harness.
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$DIAGNOSTIC_UDID" \
  MT_SIM_LOCK_TEST_LSOF_BIN="$LSOF_NO_MATCH_WARNING" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  MT_SIM_LOCK_WAIT=5 \
    "$SIM_LOCK" --seat codex1 sh -c 'touch "$1.started"' sh "$DIAGNOSTIC_WAITER" \
    >"$DIAGNOSTIC_WAITER.log" 2>&1 &
  diagnostic_waiter_pid=$!
  wait_for_pattern "$DIAGNOSTIC_WAITER.log" "waiting for simulator $DIAGNOSTIC_UDID lock" || true
  touch "$DIAGNOSTIC_HOLDER.release"
  wait "$diagnostic_holder_pid" 2>/dev/null || true
  diagnostic_waiter_rc=0
  wait "$diagnostic_waiter_pid" 2>/dev/null || diagnostic_waiter_rc=$?
  if [ "$diagnostic_waiter_rc" -eq 0 ] &&
     [ -f "$DIAGNOSTIC_WAITER.started" ]; then
    record_ok "queued gate ignores non-fatal lsof diagnostics"
  else
    record_fail "queued gate ignores non-fatal lsof diagnostics" \
      "status=$diagnostic_waiter_rc output='$(head -1 "$DIAGNOSTIC_WAITER.log" 2>/dev/null)'"
  fi
else
  record_fail "queued gate ignores non-fatal lsof diagnostics" \
    "holder did not start"
fi

CROSS_A="$TMP/cross-a"
CROSS_B="$TMP/cross-b"
register_release "$CROSS_A"
register_release "$CROSS_B"
start_holder "TEST-CROSS-SIM-A" "$CROSS_A" >"$CROSS_A.log" 2>&1 &
cross_a_pid=$!
if wait_for_path "$CROSS_A.started"; then
  start_holder "TEST-CROSS-SIM-B" "$CROSS_B" >"$CROSS_B.log" 2>&1 &
  cross_b_pid=$!
  if wait_for_path "$CROSS_B.started" && [ ! -e "$CROSS_A.finished" ]; then
    record_ok "allows commands for different simulators to overlap"
  else
    record_fail "allows commands for different simulators to overlap" \
      "second simulator did not start while the first was held"
  fi
  touch "$CROSS_A.release" "$CROSS_B.release"
  wait "$cross_a_pid" 2>/dev/null
  wait "$cross_b_pid" 2>/dev/null
else
  record_fail "allows commands for different simulators to overlap" \
    "first holder did not start"
  touch "$CROSS_A.release"
  wait "$cross_a_pid" 2>/dev/null
fi

echo
echo "sim-lock global gate cap:"

CAP_A="$TMP/cap-a"
CAP_B="$TMP/cap-b"
CAP_C="$TMP/cap-c"
register_release "$CAP_A"
register_release "$CAP_B"
register_release "$CAP_C"
start_default_cap_holder "TEST-CAP-SIM-A" "$CAP_A" >"$CAP_A.log" 2>&1 &
cap_a_pid=$!
start_default_cap_holder "TEST-CAP-SIM-B" "$CAP_B" >"$CAP_B.log" 2>&1 &
cap_b_pid=$!
cap_setup_ok=1
wait_for_path "$CAP_A.started" || cap_setup_ok=0
wait_for_path "$CAP_B.started" || cap_setup_ok=0
if [ "$cap_setup_ok" -eq 1 ]; then
  start_default_cap_holder "TEST-CAP-SIM-C" "$CAP_C" >"$CAP_C.log" 2>&1 &
  cap_c_pid=$!
  if wait_for_pattern "$CAP_C.log" "waiting for one of 2 global gate slots" &&
     [ ! -e "$CAP_C.started" ]; then
    touch "$CAP_A.release"
    if wait_for_path "$CAP_C.started"; then
      record_ok "queues a third gate until one of two global slots opens"
    else
      record_fail "queues a third gate until one of two global slots opens" \
        "third gate stayed queued after a slot opened"
    fi
  else
    record_fail "queues a third gate until one of two global slots opens" \
      "third gate started while two slots were occupied"
    touch "$CAP_A.release"
  fi
  touch "$CAP_B.release" "$CAP_C.release"
  wait "$cap_a_pid" 2>/dev/null
  wait "$cap_b_pid" 2>/dev/null
  wait "$cap_c_pid" 2>/dev/null
else
  record_fail "queues a third gate until one of two global slots opens" \
    "two different simulators could not occupy the two available slots"
  touch "$CAP_A.release" "$CAP_B.release"
  wait "$cap_a_pid" 2>/dev/null
  wait "$cap_b_pid" 2>/dev/null
fi

set +e
oversized_cap_out="$(
  MT_GATE_MAX_CONCURRENT=3 \
    run_gate_for "TEST-CAP-OVERSIZED" true 2>&1
)"
oversized_cap_rc=$?
set -e
if [ "$oversized_cap_rc" -ne 0 ] &&
   echo "$oversized_cap_out" | grep -q "cannot exceed the host ceiling of 2"; then
  record_ok "rejects a caller that tries to enlarge the host-wide cap"
else
  record_fail "rejects a caller that tries to enlarge the host-wide cap" \
    "status=$oversized_cap_rc output='$oversized_cap_out'"
fi

set +e
noncanonical_cap_out="$(
  MT_GATE_MAX_CONCURRENT=08 \
    run_gate_for "TEST-CAP-NONCANONICAL" true 2>&1
)"
noncanonical_cap_rc=$?
set -e
if [ "$noncanonical_cap_rc" -ne 0 ] &&
   echo "$noncanonical_cap_out" | grep -q "must be 1 or 2"; then
  record_ok "rejects leading-zero cap values before arithmetic"
else
  record_fail "rejects leading-zero cap values before arithmetic" \
    "status=$noncanonical_cap_rc output='$noncanonical_cap_out'"
fi

# A cap-1 invocation is a fleet-exclusive maintenance admission, not merely a
# caller that ignores slot 2. It waits for both ordinary holders, then blocks
# new ordinary gates until it exits.
EXCLUSIVE_A="$TMP/exclusive-a"
EXCLUSIVE_B="$TMP/exclusive-b"
EXCLUSIVE_C="$TMP/exclusive-c"
EXCLUSIVE_D="$TMP/exclusive-d"
register_release "$EXCLUSIVE_A"
register_release "$EXCLUSIVE_B"
register_release "$EXCLUSIVE_C"
register_release "$EXCLUSIVE_D"
start_default_cap_holder "TEST-EXCLUSIVE-A" "$EXCLUSIVE_A" >"$EXCLUSIVE_A.log" 2>&1 &
exclusive_a_pid=$!
start_default_cap_holder "TEST-EXCLUSIVE-B" "$EXCLUSIVE_B" >"$EXCLUSIVE_B.log" 2>&1 &
exclusive_b_pid=$!
exclusive_setup_ok=1
wait_for_path "$EXCLUSIVE_A.started" || exclusive_setup_ok=0
wait_for_path "$EXCLUSIVE_B.started" || exclusive_setup_ok=0
if [ "$exclusive_setup_ok" -eq 1 ]; then
  MT_GATE_MAX_CONCURRENT=1 start_holder "TEST-EXCLUSIVE-C" "$EXCLUSIVE_C" >"$EXCLUSIVE_C.log" 2>&1 &
  exclusive_c_pid=$!
  exclusive_c_waiting=0
  wait_for_pattern "$EXCLUSIVE_C.log" "waiting for fleet-exclusive gate admission" ||
    exclusive_c_waiting=1
  touch "$EXCLUSIVE_A.release"
  wait "$exclusive_a_pid" 2>/dev/null
  sleep 0.3
  cap_one_waited_for_both=0
  [ ! -e "$EXCLUSIVE_C.started" ] || cap_one_waited_for_both=1
  touch "$EXCLUSIVE_B.release"
  wait "$exclusive_b_pid" 2>/dev/null
  cap_one_started=0
  wait_for_path "$EXCLUSIVE_C.started" || cap_one_started=1

  start_default_cap_holder "TEST-EXCLUSIVE-D" "$EXCLUSIVE_D" >"$EXCLUSIVE_D.log" 2>&1 &
  exclusive_d_pid=$!
  exclusive_d_waiting=0
  wait_for_pattern "$EXCLUSIVE_D.log" "waiting for shared gate admission" ||
    exclusive_d_waiting=1
  default_waited_for_exclusive=0
  [ ! -e "$EXCLUSIVE_D.started" ] || default_waited_for_exclusive=1
  touch "$EXCLUSIVE_C.release"
  wait "$exclusive_c_pid" 2>/dev/null
  default_started=0
  wait_for_path "$EXCLUSIVE_D.started" || default_started=1
  touch "$EXCLUSIVE_D.release"
  wait "$exclusive_d_pid" 2>/dev/null

  if [ "$exclusive_c_waiting" -eq 0 ] &&
     [ "$exclusive_d_waiting" -eq 0 ] &&
     [ "$cap_one_waited_for_both" -eq 0 ] &&
     [ "$cap_one_started" -eq 0 ] &&
     [ "$default_waited_for_exclusive" -eq 0 ] &&
     [ "$default_started" -eq 0 ]; then
    record_ok "makes a cap-1 invocation fleet-exclusive against default gates"
  else
    record_fail "makes a cap-1 invocation fleet-exclusive against default gates" \
      "cap1_waiting=$exclusive_c_waiting default_waiting=$exclusive_d_waiting waited_for_both=$cap_one_waited_for_both cap1_started=$cap_one_started default_waited=$default_waited_for_exclusive default_started=$default_started"
  fi
else
  record_fail "makes a cap-1 invocation fleet-exclusive against default gates" \
    "two ordinary gates did not start"
  touch "$EXCLUSIVE_A.release" "$EXCLUSIVE_B.release"
  wait "$exclusive_a_pid" 2>/dev/null
  wait "$exclusive_b_pid" 2>/dev/null
fi

echo
echo "sim-lock stable lock inode:"

INODE_UDID="TEST-INODE-SIM"
INODE_LOCK="$LOCK_ROOT/making-tracks-sim-$INODE_UDID.lock"
INODE_HOLDER_A="$TMP/inode-holder-a"
INODE_HOLDER_B="$TMP/inode-holder-b"
register_release "$INODE_HOLDER_A"
register_release "$INODE_HOLDER_B"
mkdir -p "$LOCK_ROOT"
touch "$INODE_LOCK"
inode_before="$(stat -f %i "$INODE_LOCK")"
start_holder "$INODE_UDID" "$INODE_HOLDER_A" >"$INODE_HOLDER_A.log" 2>&1 &
inode_a_pid=$!
if wait_for_path "$INODE_HOLDER_A.started" && [ -f "$INODE_LOCK" ]; then
  start_holder "$INODE_UDID" "$INODE_HOLDER_B" >"$INODE_HOLDER_B.log" 2>&1 &
  inode_b_pid=$!
  waiter_ready=0
  wait_for_pattern "$INODE_HOLDER_B.log" "waiting for" || waiter_ready=1
  inode_during="$(stat -f %i "$INODE_LOCK")"
  expected_inode_locked=0
  exec 6>>"$INODE_LOCK"
  "$FLOCK_BIN" -n 6 && expected_inode_locked=1
  exec 6>&-
  contender_queued=0
  [ ! -e "$INODE_HOLDER_B.started" ] || contender_queued=1
  touch "$INODE_HOLDER_A.release"
  wait "$inode_a_pid" 2>/dev/null
  contender_started=0
  wait_for_path "$INODE_HOLDER_B.started" || contender_started=1
  touch "$INODE_HOLDER_B.release"
  wait "$inode_b_pid" 2>/dev/null
  inode_after="$(stat -f %i "$INODE_LOCK")"
  if [ "$waiter_ready" -eq 0 ] &&
     [ "$expected_inode_locked" -eq 0 ] &&
     [ "$contender_queued" -eq 0 ] &&
     [ "$contender_started" -eq 0 ] &&
     [ "$inode_before" = "$inode_during" ] &&
     [ "$inode_before" = "$inode_after" ]; then
    record_ok "serializes contenders through one stable lock inode"
  else
    record_fail "serializes contenders through one stable lock inode" \
      "waiter_ready=$waiter_ready expected_inode_locked=$expected_inode_locked queued=$contender_queued started_after_release=$contender_started inode before=$inode_before during=$inode_during after=$inode_after"
  fi
else
  record_fail "serializes contenders through one stable lock inode" \
    "holder did not use the expected per-simulator lock path"
  touch "$INODE_HOLDER_A.release"
  wait "$inode_a_pid" 2>/dev/null
fi

echo
echo "release-gate destination contract:"

FAKE_BIN="$TMP/fake-bin"
XCODEBUILD_LOG="$TMP/xcodebuild.log"
mkdir -p "$FAKE_BIN"
# shellcheck disable=SC2016 # These lines are the literal fake-git program.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-} ${2:-}" in' \
  '  "rev-parse --show-toplevel") printf "%s\n" "$MT_TEST_REPO_ROOT" ;;' \
  '  "fetch --quiet") exit 0 ;;' \
  '  "merge-base --is-ancestor") exit 0 ;;' \
  '  *) exit 0 ;;' \
  'esac' >"$FAKE_BIN/git"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'exit 0' >"$FAKE_BIN/xcrun"
# shellcheck disable=SC2016 # Expanded when the fake xcodebuild runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >>"$MT_TEST_XCODEBUILD_LOG"' >"$FAKE_BIN/xcodebuild"
chmod +x "$FAKE_BIN/git" "$FAKE_BIN/xcrun" "$FAKE_BIN/xcodebuild"

rm -f "$XCODEBUILD_LOG"
set +e
mismatched_gate_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_B" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
mismatched_gate_rc=$?
set -e
if [ "$mismatched_gate_rc" -ne 0 ] &&
   echo "$mismatched_gate_out" | grep -q "lock is for simulator" &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "rejects a release gate targeting a different simulator than its lock"
else
  record_fail "rejects a release gate targeting a different simulator than its lock" \
    "status=$mismatched_gate_rc output='$(echo "$mismatched_gate_out" | head -1)'"
fi

rm -f "$XCODEBUILD_LOG"
set +e
missing_destination_out="$(
  env -u MT_SIM_LOCK_DESTINATION \
    PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_MODE=build \
    AM_ME="$RELEASE_FIXTURE_SEAT" \
    "$RELEASE_GATE" 2>&1
)"
missing_destination_rc=$?
set -e
if [ "$missing_destination_rc" -ne 0 ] &&
   echo "$missing_destination_out" | grep -q "MT_SIM_LOCK_DESTINATION is missing" &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "ignores the removed public destination at the release-gate boundary"
else
  record_fail "ignores the removed public destination at the release-gate boundary" \
    "status=$missing_destination_rc got: $(echo "$missing_destination_out" | head -1)"
fi

rm -f "$XCODEBUILD_LOG"
set +e
malformed_gate_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="NOT-AN-ID" \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,grid=NOT-AN-ID" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
malformed_gate_rc=$?
set -e
if [ "$malformed_gate_rc" -ne 0 ] &&
   echo "$malformed_gate_out" | grep -q "must include id=" &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "release gate rejects a destination without an exact id field"
else
  record_fail "release gate rejects a destination without an exact id field" \
    "status=$malformed_gate_rc output='$(echo "$malformed_gate_out" | head -1)'"
fi

rm -f "$XCODEBUILD_LOG"
set +e
duplicate_gate_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="FIRST" \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=FIRST,id=SECOND" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
duplicate_gate_rc=$?
set -e
if [ "$duplicate_gate_rc" -ne 0 ] &&
   echo "$duplicate_gate_out" | grep -q "exactly one id=" &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "release gate rejects multiple destination id fields"
else
  record_fail "release gate rejects multiple destination id fields" \
    "status=$duplicate_gate_rc output='$(echo "$duplicate_gate_out" | head -1)'"
fi

run_release_fixture() {
  local udid="$1"
  : >"$XCODEBUILD_LOG"
  PATH="$FAKE_BIN:$PATH" \
  MT_TEST_REPO_ROOT="$HERE/.." \
  MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
  MT_SIM_LOCK=1 \
  MT_SIM_LOCK_UDID="$udid" \
  MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$udid" \
  MT_RELEASE_GATE_MODE=build \
  AM_ME="$RELEASE_FIXTURE_SEAT" \
  "$RELEASE_GATE" >/dev/null 2>&1
  grep -o -- '-derivedDataPath [^ ]*' "$XCODEBUILD_LOG" | head -1
}

derived_a="$(run_release_fixture "$RELEASE_UDID_A")"
derived_b="$(run_release_fixture "$RELEASE_UDID_B")"
expected_a="-derivedDataPath /private/tmp/release-gate-$RELEASE_UDID_A/DerivedData"
expected_b="-derivedDataPath /private/tmp/release-gate-$RELEASE_UDID_B/DerivedData"
if [ "$derived_a" = "$expected_a" ] && [ "$derived_b" = "$expected_b" ]; then
  record_ok "derives the exact default DerivedData path for each destination UDID"
else
  record_fail "derives the exact default DerivedData path for each destination UDID" \
    "first='$derived_a' expected='$expected_a' second='$derived_b' expected='$expected_b'"
fi

echo
echo "sim-lock: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
