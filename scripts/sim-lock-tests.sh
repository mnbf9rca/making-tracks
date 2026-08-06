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
OTHER_SEAT_UDID="22222222-2222-4222-8222-222222222222"
LOCK="$LOCK_ROOT/making-tracks-sim-$FAKE_UDID.lock"
FLOCK_BIN="/opt/homebrew/bin/flock"
RELEASE_FIXTURE_SEAT="sim-lock-test-$$"
RELEASE_LEGACY_RUN_DIR="/private/tmp/release-gate-$RELEASE_FIXTURE_SEAT"
RELEASE_PID_HEX="$(printf '%012X' "$$")"
SAFE_TEST_ROOT="$HOME/Library/Caches/making-tracks-sim-lock-tests/$RELEASE_PID_HEX"
RELEASE_UDID_A="AAAAAAAA-AAAA-4AAA-8AAA-$RELEASE_PID_HEX"
RELEASE_UDID_B="BBBBBBBB-BBBB-4BBB-8BBB-$RELEASE_PID_HEX"
RELEASE_RUN_DIR_A="/private/tmp/release-gate-$RELEASE_UDID_A"
RELEASE_RUN_DIR_B="/private/tmp/release-gate-$RELEASE_UDID_B"
DANGLING_TMP_TARGET="/private/tmp/mt-612-dangling-$RELEASE_PID_HEX"
UNSAFE_EXISTING_DERIVED_DATA="/private/tmp/mt-612-existing-$RELEASE_PID_HEX"
UNSAFE_MISSING_DERIVED_DATA="/private/tmp/mt-612-missing-$RELEASE_PID_HEX"
UNSAFE_ALIAS_EQUAL="/private/tmp/mt-612-alias-equal-$RELEASE_PID_HEX"
UNSAFE_ALIAS_ANCESTOR="/private/tmp/mt-612-alias-ancestor-$RELEASE_PID_HEX"
UNSAFE_ALIAS_DESCENDANT="/private/tmp/mt-612-alias-descendant-$RELEASE_PID_HEX"
RELEASE_FIXTURE_HOME="$SAFE_TEST_ROOT/release-fixture-home"
RELEASE_MARKERS="$TMP/release-markers"
TEST_LEDGER="$TMP/ios-gate-ledger.md"

mkdir -p "$SAFE_TEST_ROOT"

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
    "$RELEASE_RUN_DIR_B" \
    "$DANGLING_TMP_TARGET" \
    "$UNSAFE_EXISTING_DERIVED_DATA" \
    "$UNSAFE_MISSING_DERIVED_DATA" \
    "$UNSAFE_ALIAS_EQUAL" \
    "$UNSAFE_ALIAS_ANCESTOR" \
    "$UNSAFE_ALIAS_DESCENDANT" \
    "$SAFE_TEST_ROOT"
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

# shellcheck disable=SC2016 # Assert the production source retains literal $HOME expansion.
if grep -Fq 'LOCK_ROOT="$HOME/Library/Application Support/making-tracks-gates/locks"' "$SIM_LOCK"; then
  record_ok "keeps live coordination locks outside automatic cleanup roots"
else
  record_fail "keeps live coordination locks outside automatic cleanup roots"
fi

DEFAULT_LOCK_HOME="$SAFE_TEST_ROOT/default-lock-home"
DEFAULT_LOCK_ROOT="$DEFAULT_LOCK_HOME/Library/Application Support/making-tracks-gates/locks"
set +e
HOME="$DEFAULT_LOCK_HOME" \
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
  "$SIM_LOCK" --seat codex1 true >/dev/null 2>&1
default_lock_root_rc=$?
set -e
if [ "$default_lock_root_rc" -eq 0 ] &&
   [ -f "$DEFAULT_LOCK_ROOT/making-tracks-sim-$FAKE_UDID.lock" ] &&
   [ -f "$DEFAULT_LOCK_ROOT/making-tracks-gate-policy.lock" ] &&
   [ -f "$DEFAULT_LOCK_ROOT/making-tracks-gate-slot-1.lock" ]; then
  record_ok "creates every default coordination inode in Application Support"
else
  record_fail "creates every default coordination inode in Application Support" \
    "status=$default_lock_root_rc root=$DEFAULT_LOCK_ROOT"
fi

FRESH_STATUS_HOME="$SAFE_TEST_ROOT/fresh-status-home"
set +e
fresh_default_status_out="$(
  HOME="$FRESH_STATUS_HOME" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 --status 2>&1
)"
fresh_default_status_rc=$?
set -e
if [ "$fresh_default_status_rc" -eq 0 ] &&
   [ "$fresh_default_status_out" = "FREE" ] &&
   [ -d "$FRESH_STATUS_HOME/Library/Application Support/making-tracks-gates/locks" ]; then
  record_ok "creates a fresh default lock root before status diagnostics"
else
  record_fail "creates a fresh default lock root before status diagnostics" \
    "status=$fresh_default_status_rc output='$fresh_default_status_out'"
fi

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

LIVE_LEDGER_HOME="$SAFE_TEST_ROOT/live-ledger-home"
mkdir -p "$LIVE_LEDGER_HOME"
set +e
# shellcheck disable=SC2016 # Expanded by the wrapped child shell.
live_ledger_out="$(
  HOME="$LIVE_LEDGER_HOME" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    "$SIM_LOCK" --seat codex1 sh -c 'printf "%s|%s\\n" "$MT_SIM_LOCK_SEAT" "$MT_RELEASE_GATE_DERIVED_DATA"' 2>&1
)"
live_ledger_rc=$?
set -e
if [ "$live_ledger_rc" -eq 0 ] &&
   [ "$live_ledger_out" = "codex1|$LIVE_LEDGER_HOME/Library/Caches/making-tracks-gates/codex1" ]; then
  record_ok "uses the checked-in Host Gate Seats table for the selected seat"
else
  record_fail "uses the checked-in Host Gate Seats table for the selected seat" \
    "status=$live_ledger_rc output='$live_ledger_out'"
fi

echo
echo "live simulator consumer contract:"

consumer_scripts=(
  "$HERE/../docs/design/design-system/capture-t2.8-implementation.sh"
  "$HERE/../docs/design/design-system/regenerate-t2.3-door-glyph.sh"
  "$HERE/../docs/design/design-system/regenerate-t2.9-settings.sh"
  "$HERE/../docs/design/design-system/regenerate-t2.10-about.sh"
)

CONSUMER_FAKE_BIN="$TMP/consumer-fake-bin"
CONSUMER_CALL_LOG="$TMP/consumer-calls.log"
CONSUMER_HOME="$SAFE_TEST_ROOT/consumer-home"
CONSUMER_DERIVED_DATA="$CONSUMER_HOME/Library/Caches/making-tracks-gates/codex1"
mkdir -p "$CONSUMER_FAKE_BIN"
# shellcheck disable=SC2016 # Expanded when the fake xcrun program runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '{ printf "xcrun:%s" "$#"; for arg in "$@"; do printf ":%s:%s" "${#arg}" "$arg"; done; printf "\n"; } >>"$MT_TEST_CONSUMER_CALL_LOG"' \
  'if [ "$#" -eq 4 ] && [ "$1" = simctl ] && [ "$2" = bootstatus ] &&' \
  '   [ "$3" = "$MT_SIM_LOCK_UDID" ] && [ "$4" = -b ]; then exit 0; fi' \
  'exit 97' \
  >"$CONSUMER_FAKE_BIN/xcrun"
# shellcheck disable=SC2016 # Expanded when the fake xcodebuild program runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "$#" -eq 1 ] && [ "$1" = -version ]; then' \
  '  printf "Xcode 26.6\nBuild version 17F113\n"' \
  '  exit 0' \
  'fi' \
  '{ printf "xcodebuild:"; printf "<%s>" "$@"; printf "\n"; } >>"$MT_TEST_CONSUMER_CALL_LOG"' \
  'exit 97' \
  >"$CONSUMER_FAKE_BIN/xcodebuild"
chmod +x "$CONSUMER_FAKE_BIN/xcrun" "$CONSUMER_FAKE_BIN/xcodebuild"

for consumer in "${consumer_scripts[@]}"; do
  consumer_name="$(basename "$consumer")"
  : >"$CONSUMER_CALL_LOG"
  set +e
  consumer_out="$(
    env -u MT_SIM_LOCK_DESTINATION -u MT_SIM_LOCK -u MT_SIM_LOCK_UDID \
      PATH="$CONSUMER_FAKE_BIN:$PATH" \
      MT_TEST_CONSUMER_CALL_LOG="$CONSUMER_CALL_LOG" \
      MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
      "$consumer" 2>&1
  )"
  consumer_rc=$?
  set -e
  if [ "$consumer_rc" -ne 0 ] &&
     echo "$consumer_out" | grep -q "MT_SIM_LOCK_DESTINATION is required" &&
     [ ! -s "$CONSUMER_CALL_LOG" ]; then
    record_ok "$consumer_name ignores the removed public destination"
  else
    record_fail "$consumer_name ignores the removed public destination" \
      "status=$consumer_rc output='$(echo "$consumer_out" | head -1)' calls='$(tr '\n' ';' <"$CONSUMER_CALL_LOG")'"
  fi
done

for consumer in "${consumer_scripts[@]}"; do
  consumer_name="$(basename "$consumer")"
  : >"$CONSUMER_CALL_LOG"
  set +e
  consumer_out="$(
    env -u MT_RELEASE_GATE_DESTINATION -u MT_SIM_LOCK -u MT_SIM_LOCK_UDID \
      PATH="$CONSUMER_FAKE_BIN:$PATH" \
      MT_TEST_CONSUMER_CALL_LOG="$CONSUMER_CALL_LOG" \
      MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
      MT_RELEASE_GATE_DERIVED_DATA=/private/tmp/dd-consumer-contract \
      "$consumer" 2>&1
  )"
  consumer_rc=$?
  set -e
  if [ "$consumer_rc" -ne 0 ] &&
     echo "$consumer_out" | grep -q \
       "invoke through scripts/sim-lock.sh --seat <seat>" &&
     [ ! -s "$CONSUMER_CALL_LOG" ]; then
    record_ok "$consumer_name rejects an unowned simulator destination"
  else
    record_fail "$consumer_name rejects an unowned simulator destination" \
      "status=$consumer_rc output='$(echo "$consumer_out" | head -1)' calls='$(tr '\n' ';' <"$CONSUMER_CALL_LOG")'"
  fi
done

for consumer in "${consumer_scripts[@]}"; do
  consumer_name="$(basename "$consumer")"
  : >"$CONSUMER_CALL_LOG"
  set +e
  PATH="$CONSUMER_FAKE_BIN:$PATH" \
    MT_TEST_CONSUMER_CALL_LOG="$CONSUMER_CALL_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$FAKE_UDID" \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
    MT_SIM_LOCK_SEAT=codex1 \
    HOME="$CONSUMER_HOME" \
    MT_RELEASE_GATE_DERIVED_DATA="$CONSUMER_DERIVED_DATA" \
    "$consumer" >/dev/null 2>&1
  consumer_rc=$?
  set -e
  first_simctl_call="$(grep '^xcrun:' "$CONSUMER_CALL_LOG" | head -1 || true)"
  if [ "$consumer_rc" -eq 97 ] &&
     [ "$first_simctl_call" = "xcrun:4:6:simctl:10:bootstatus:36:$FAKE_UDID:2:-b" ]; then
    record_ok "$consumer_name boots its locked seat before simulator use"
  else
    record_fail "$consumer_name boots its locked seat before simulator use" \
      "status=$consumer_rc first_simctl='$first_simctl_call' calls='$(tr '\n' ';' <"$CONSUMER_CALL_LOG")'"
  fi
done

for consumer in "${consumer_scripts[@]}"; do
  consumer_name="$(basename "$consumer")"
  : >"$CONSUMER_CALL_LOG"
  set +e
  consumer_out="$(
    PATH="$CONSUMER_FAKE_BIN:$PATH" \
      MT_TEST_CONSUMER_CALL_LOG="$CONSUMER_CALL_LOG" \
      MT_SIM_LOCK=1 \
      MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
      MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
      MT_SIM_LOCK_SEAT=codex1 \
      HOME="$CONSUMER_HOME" \
      MT_RELEASE_GATE_DERIVED_DATA="$CONSUMER_DERIVED_DATA" \
      "$consumer" 2>&1
  )"
  consumer_rc=$?
  set -e
  if [ "$consumer_rc" -ne 0 ] &&
     echo "$consumer_out" | grep -q "simulator lock does not match destination" &&
     [ ! -s "$CONSUMER_CALL_LOG" ]; then
    record_ok "$consumer_name rejects a mismatched lock before external calls"
  else
    record_fail "$consumer_name rejects a mismatched lock before external calls" \
      "status=$consumer_rc output='$(echo "$consumer_out" | head -1)' calls='$(tr '\n' ';' <"$CONSUMER_CALL_LOG")'"
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
CLI_CASE_ALIAS_BIN="$TMP/cli-case-alias-bin"
CLI_XCODEBUILD_LOG="$TMP/cli-xcodebuild.log"
CLI_SIMCTL_LOG="$TMP/cli-simctl.log"
DIRECT_XCODE_HOME="$SAFE_TEST_ROOT/direct-xcode-home"
mkdir -p "$CLI_FAKE_BIN"
mkdir -p "$CLI_CASE_ALIAS_BIN"
mkdir -p "$DIRECT_XCODE_HOME"
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
ln -s "$CLI_FAKE_BIN/xcodebuild" "$CLI_CASE_ALIAS_BIN/XCODEBUILD"
ln -s /usr/bin/env "$CLI_CASE_ALIAS_BIN/ENV"
set +e
injected_destination_out="$(
  HOME="$DIRECT_XCODE_HOME" \
    PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcodebuild test 2>&1
)"
injected_destination_rc=$?
set -e
default_derived_data_args="test -destination platform=iOS Simulator,id=$FAKE_UDID -derivedDataPath $DIRECT_XCODE_HOME/Library/Caches/making-tracks-gates/codex1"
if [ "$injected_destination_rc" -eq 0 ] &&
   [ "$(<"$CLI_XCODEBUILD_LOG")" = "$default_derived_data_args" ]; then
  record_ok "injects the selected seat destination and exact DerivedData default into xcodebuild"
else
  record_fail "injects the selected seat destination and exact DerivedData default into xcodebuild" \
    "status=$injected_destination_rc output='$injected_destination_out' args='$(head -1 "$CLI_XCODEBUILD_LOG" 2>/dev/null)' expected='$default_derived_data_args'"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
matching_destination_out="$(
  HOME="$DIRECT_XCODE_HOME" \
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
     "test -destination platform=iOS Simulator,id=$FAKE_UDID -derivedDataPath $DIRECT_XCODE_HOME/Library/Caches/making-tracks-gates/codex1" ]; then
  record_ok "preserves an explicit matching xcodebuild destination"
else
  record_fail "preserves an explicit matching xcodebuild destination" \
    "status=$matching_destination_rc output='$matching_destination_out' args='$(head -1 "$CLI_XCODEBUILD_LOG" 2>/dev/null)'"
fi

EXPLICIT_DIRECT_DERIVED_DATA="$DIRECT_XCODE_HOME/explicit-derived-data"
rm -f "$CLI_XCODEBUILD_LOG"
set +e
explicit_derived_data_out="$(
  HOME="$DIRECT_XCODE_HOME" \
    PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcodebuild test \
      -derivedDataPath "$EXPLICIT_DIRECT_DERIVED_DATA" 2>&1
)"
explicit_derived_data_rc=$?
set -e
if [ "$explicit_derived_data_rc" -eq 0 ] &&
   [ "$(grep -o -- '-derivedDataPath' "$CLI_XCODEBUILD_LOG" | wc -l | tr -d ' ')" = "1" ] &&
   grep -Fq -- "-derivedDataPath $EXPLICIT_DIRECT_DERIVED_DATA" "$CLI_XCODEBUILD_LOG"; then
  record_ok "preserves one explicit safe direct xcodebuild DerivedData path"
else
  record_fail "preserves one explicit safe direct xcodebuild DerivedData path" \
    "status=$explicit_derived_data_rc output='$explicit_derived_data_out' args='$(head -1 "$CLI_XCODEBUILD_LOG" 2>/dev/null)'"
fi

DERIVED_DATA_MARKER="$TMP/derived-data-marker"
rm -f "$DERIVED_DATA_MARKER"
set +e
# shellcheck disable=SC2016 # Expanded by the wrapped child shell.
temporary_override_out="$(
  MT_RELEASE_GATE_DERIVED_DATA=/private/tmp/mt-612-wrapper-override \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 sh -c 'touch "$1"' sh "$DERIVED_DATA_MARKER" 2>&1
)"
temporary_override_rc=$?
set -e
if [ "$temporary_override_rc" -ne 0 ] &&
   echo "$temporary_override_out" | grep -q '#612' &&
   [ ! -e "$DERIVED_DATA_MARKER" ]; then
  record_ok "refuses an inherited temporary DerivedData override before the command runs"
else
  record_fail "refuses an inherited temporary DerivedData override before the command runs" \
    "status=$temporary_override_rc output='$(echo "$temporary_override_out" | head -1)' marker=$(test -e "$DERIVED_DATA_MARKER" && echo present || echo absent)"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
temporary_xcode_path_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcodebuild test \
      -derivedDataPath /tmp/mt-612-direct-xcode 2>&1
)"
temporary_xcode_path_rc=$?
set -e
if [ "$temporary_xcode_path_rc" -ne 0 ] &&
   echo "$temporary_xcode_path_out" | grep -q '#612' &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "refuses a direct temporary xcodebuild DerivedData path before Xcode runs"
else
  record_fail "refuses a direct temporary xcodebuild DerivedData path before Xcode runs" \
    "status=$temporary_xcode_path_rc output='$(echo "$temporary_xcode_path_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
fi

for janitor_derived_data in \
  /var/tmp/mt-612-direct-var-tmp \
  /VAR/TMP/mt-612-direct-case-alias \
  "$TMP/mt-612-direct-user-temp"; do
  rm -f "$CLI_XCODEBUILD_LOG"
  set +e
  janitor_xcode_path_out="$(
    PATH="$CLI_FAKE_BIN:$PATH" \
      MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
      MT_SIM_LOCK_TEST_MODE=1 \
      MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
      MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
      "$SIM_LOCK" --seat codex1 xcodebuild test \
        -derivedDataPath "$janitor_derived_data" 2>&1
  )"
  janitor_xcode_path_rc=$?
  set -e
  if [ "$janitor_xcode_path_rc" -ne 0 ] &&
     echo "$janitor_xcode_path_out" | grep -q '#612' &&
     [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
    record_ok "refuses system-managed temporary DerivedData before Xcode: $janitor_derived_data"
  else
    record_fail "refuses system-managed temporary DerivedData before Xcode: $janitor_derived_data" \
      "status=$janitor_xcode_path_rc output='$(echo "$janitor_xcode_path_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
  fi
done

rm -f "$CLI_XCODEBUILD_LOG"
set +e
env_xcode_path_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 env xcodebuild test \
      -derivedDataPath=/private/tmp/mt-612-env-xcode 2>&1
)"
env_xcode_path_rc=$?
set -e
if [ "$env_xcode_path_rc" -ne 0 ] &&
   echo "$env_xcode_path_out" | grep -q '#612' &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "refuses env xcodebuild temporary DerivedData before Xcode runs"
else
  record_fail "refuses env xcodebuild temporary DerivedData before Xcode runs" \
    "status=$env_xcode_path_rc output='$(echo "$env_xcode_path_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
env_assignment_xcode_path_out="$(
  HOME="$DIRECT_XCODE_HOME" \
    PATH="$CLI_FAKE_BIN:$PATH" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 /usr/bin/env \
      MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
      xcodebuild test -derivedDataPath=/private/tmp/mt-612-env-assignment-xcode 2>&1
)"
env_assignment_xcode_path_rc=$?
set -e
if [ "$env_assignment_xcode_path_rc" -ne 0 ] &&
   echo "$env_assignment_xcode_path_out" | grep -q '#612' &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "refuses assignment-prefixed env xcodebuild DerivedData before Xcode runs"
else
  record_fail "refuses assignment-prefixed env xcodebuild DerivedData before Xcode runs" \
    "status=$env_assignment_xcode_path_rc output='$(echo "$env_assignment_xcode_path_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
env_option_xcode_path_out="$(
  HOME="$DIRECT_XCODE_HOME" \
    PATH="$CLI_FAKE_BIN:$PATH" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 /usr/bin/env -u MT_UNUSED -- \
      MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
      xcodebuild test -derivedDataPath=/private/tmp/mt-612-env-option-xcode 2>&1
)"
env_option_xcode_path_rc=$?
set -e
if [ "$env_option_xcode_path_rc" -ne 0 ] &&
   echo "$env_option_xcode_path_out" | grep -q '#612' &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "refuses option-prefixed env xcodebuild DerivedData before Xcode runs"
else
  record_fail "refuses option-prefixed env xcodebuild DerivedData before Xcode runs" \
    "status=$env_option_xcode_path_rc output='$(echo "$env_option_xcode_path_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
env_option_injection_out="$(
  HOME="$DIRECT_XCODE_HOME" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 /usr/bin/env -i -- \
      PATH="$CLI_FAKE_BIN:/usr/bin:/bin" \
      MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
      xcodebuild test 2>&1
)"
env_option_injection_rc=$?
set -e
if [ "$env_option_injection_rc" -eq 0 ] &&
   [ "$(<"$CLI_XCODEBUILD_LOG")" = "$default_derived_data_args" ]; then
  record_ok "injects destination and DerivedData through env options and assignments"
else
  record_fail "injects destination and DerivedData through env options and assignments" \
    "status=$env_option_injection_rc output='$env_option_injection_out' args='$(head -1 "$CLI_XCODEBUILD_LOG" 2>/dev/null)' expected='$default_derived_data_args'"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
env_split_string_out="$(
  HOME="$DIRECT_XCODE_HOME" \
    PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 /usr/bin/env -S \
      'xcodebuild test -derivedDataPath /private/tmp/mt-612-env-split-string' 2>&1
)"
env_split_string_rc=$?
set -e
if [ "$env_split_string_rc" -ne 0 ] &&
   echo "$env_split_string_out" | grep -q 'unsupported env option' &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "fails closed on env split-string syntax before its child runs"
else
  record_fail "fails closed on env split-string syntax before its child runs" \
    "status=$env_split_string_rc output='$(echo "$env_split_string_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
fi

set +e
# shellcheck disable=SC2016 # Expanded by the env-wrapped child shell.
env_non_xcode_out="$(
  HOME="$DIRECT_XCODE_HOME" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 /usr/bin/env MT_NON_XCODE=preserved \
      sh -c 'printf "%s" "$MT_NON_XCODE"' 2>&1
)"
env_non_xcode_rc=$?
set -e
if [ "$env_non_xcode_rc" -eq 0 ] && [ "$env_non_xcode_out" = "preserved" ]; then
  record_ok "preserves an assignment-prefixed env non-Xcode command"
else
  record_fail "preserves an assignment-prefixed env non-Xcode command" \
    "status=$env_non_xcode_rc output='$env_non_xcode_out'"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
absolute_xcode_path_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 "$CLI_FAKE_BIN/xcodebuild" test \
      -derivedDataPath /private/tmp/mt-612-absolute-xcode 2>&1
)"
absolute_xcode_path_rc=$?
set -e
if [ "$absolute_xcode_path_rc" -ne 0 ] &&
   echo "$absolute_xcode_path_out" | grep -q '#612' &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "refuses an absolute xcodebuild temporary DerivedData path before Xcode runs"
else
  record_fail "refuses an absolute xcodebuild temporary DerivedData path before Xcode runs" \
    "status=$absolute_xcode_path_rc output='$(echo "$absolute_xcode_path_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
uppercase_xcode_path_out="$(
  HOME="$DIRECT_XCODE_HOME" \
    PATH="$CLI_CASE_ALIAS_BIN:$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 "$CLI_CASE_ALIAS_BIN/XCODEBUILD" test \
      -derivedDataPath /private/tmp/mt-612-uppercase-xcode 2>&1
)"
uppercase_xcode_path_rc=$?
set -e
if [ "$uppercase_xcode_path_rc" -ne 0 ] &&
   echo "$uppercase_xcode_path_out" | grep -q '#612' &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "refuses a case-alias xcodebuild DerivedData path before Xcode runs"
else
  record_fail "refuses a case-alias xcodebuild DerivedData path before Xcode runs" \
    "status=$uppercase_xcode_path_rc output='$(echo "$uppercase_xcode_path_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -f "$CLI_XCODEBUILD_LOG"
set +e
uppercase_env_xcode_path_out="$(
  HOME="$DIRECT_XCODE_HOME" \
    PATH="$CLI_CASE_ALIAS_BIN:$CLI_FAKE_BIN:$PATH" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 "$CLI_CASE_ALIAS_BIN/ENV" \
      MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
      XCODEBUILD test -derivedDataPath=/private/tmp/mt-612-uppercase-env-xcode 2>&1
)"
uppercase_env_xcode_path_rc=$?
set -e
if [ "$uppercase_env_xcode_path_rc" -ne 0 ] &&
   echo "$uppercase_env_xcode_path_out" | grep -q '#612' &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "refuses case-alias env and xcodebuild DerivedData before Xcode runs"
else
  record_fail "refuses case-alias env and xcodebuild DerivedData before Xcode runs" \
    "status=$uppercase_env_xcode_path_rc output='$(echo "$uppercase_env_xcode_path_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
fi

DANGLING_DIRECT_DERIVED_DATA="$TMP/safe-dangling-direct-derived-data"
ln -s "$DANGLING_TMP_TARGET" "$DANGLING_DIRECT_DERIVED_DATA"
rm -f "$CLI_XCODEBUILD_LOG"
set +e
dangling_direct_xcode_path_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 xcodebuild test \
      -derivedDataPath "$DANGLING_DIRECT_DERIVED_DATA" 2>&1
)"
dangling_direct_xcode_path_rc=$?
set -e
if [ "$dangling_direct_xcode_path_rc" -ne 0 ] &&
   echo "$dangling_direct_xcode_path_out" | grep -q '#612' &&
   [ ! -e "$CLI_XCODEBUILD_LOG" ]; then
  record_ok "refuses a dangling DerivedData symlink to temporary storage before Xcode runs"
else
  record_fail "refuses a dangling DerivedData symlink to temporary storage before Xcode runs" \
    "status=$dangling_direct_xcode_path_rc output='$(echo "$dangling_direct_xcode_path_out" | head -1)' xcode=$(test -e "$CLI_XCODEBUILD_LOG" && echo ran || echo absent)"
fi

ROOT_PARENT_DERIVED_DATA="/mt-612-root-parent-$RELEASE_PID_HEX"
rm -f "$CLI_XCODEBUILD_LOG"
set +e
root_parent_path_out="$(
  PATH="$CLI_FAKE_BIN:$PATH" \
    MT_TEST_XCODEBUILD_LOG="$CLI_XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    MT_RELEASE_GATE_DERIVED_DATA="$ROOT_PARENT_DERIVED_DATA" \
    "$SIM_LOCK" --seat codex1 xcodebuild test 2>&1
)"
root_parent_path_rc=$?
set -e
if [ "$root_parent_path_rc" -eq 0 ] &&
   [ "$(<"$CLI_XCODEBUILD_LOG")" = \
     "test -destination platform=iOS Simulator,id=$FAKE_UDID -derivedDataPath $ROOT_PARENT_DERIVED_DATA" ]; then
  record_ok "passes the canonical root-parent DerivedData path to Xcode"
else
  record_fail "passes the canonical root-parent DerivedData path to Xcode" \
    "status=$root_parent_path_rc output='$(echo "$root_parent_path_out" | head -1)' args='$(head -1 "$CLI_XCODEBUILD_LOG" 2>/dev/null)'"
fi

SEAT_TEST_LEDGER="$TMP/seat-ios-gate-ledger.md"
write_test_ledger "$SEAT_TEST_LEDGER" "platform=iOS Simulator,id=$FAKE_UDID" \
  "| \`codex2\` | \`mt-gate-codex2\` | \`platform=iOS Simulator,id=$OTHER_SEAT_UDID\` |"
SEAT_TEST_HOME="$SAFE_TEST_ROOT/seat-home"
mkdir -p "$SEAT_TEST_HOME"
# shellcheck disable=SC2016 # Expanded by the wrapped child shell.
seat_default_c1="$(
  HOME="$SEAT_TEST_HOME" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$SEAT_TEST_LEDGER" \
    "$SIM_LOCK" --seat codex1 sh -c 'printf "%s|%s\\n" "$MT_SIM_LOCK_SEAT" "$MT_RELEASE_GATE_DERIVED_DATA"'
)"
# shellcheck disable=SC2016 # Expanded by the wrapped child shell.
seat_default_c2="$(
  HOME="$SEAT_TEST_HOME" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
    MT_SIM_LOCK_TEST_LEDGER="$SEAT_TEST_LEDGER" \
    "$SIM_LOCK" --seat codex2 sh -c 'printf "%s|%s\\n" "$MT_SIM_LOCK_SEAT" "$MT_RELEASE_GATE_DERIVED_DATA"'
)"
if [ "$seat_default_c1" = "codex1|$SEAT_TEST_HOME/Library/Caches/making-tracks-gates/codex1" ] &&
   [ "$seat_default_c2" = "codex2|$SEAT_TEST_HOME/Library/Caches/making-tracks-gates/codex2" ]; then
  record_ok "exports distinct persistent DerivedData defaults for each seat"
else
  record_fail "exports distinct persistent DerivedData defaults for each seat" \
    "codex1='$seat_default_c1' codex2='$seat_default_c2'"
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

CEILING_A="$TMP/ceiling-a"
CEILING_B="$TMP/ceiling-b"
CEILING_C="$TMP/ceiling-c"
CEILING_D="$TMP/ceiling-d"
register_release "$CEILING_A"
register_release "$CEILING_B"
register_release "$CEILING_C"
register_release "$CEILING_D"
MT_GATE_MAX_CONCURRENT=3 start_holder "TEST-CEILING-SIM-A" "$CEILING_A" >"$CEILING_A.log" 2>&1 &
ceiling_a_pid=$!
MT_GATE_MAX_CONCURRENT=3 start_holder "TEST-CEILING-SIM-B" "$CEILING_B" >"$CEILING_B.log" 2>&1 &
ceiling_b_pid=$!
MT_GATE_MAX_CONCURRENT=3 start_holder "TEST-CEILING-SIM-C" "$CEILING_C" >"$CEILING_C.log" 2>&1 &
ceiling_c_pid=$!
ceiling_setup_ok=1
wait_for_path "$CEILING_A.started" || ceiling_setup_ok=0
wait_for_path "$CEILING_B.started" || ceiling_setup_ok=0
wait_for_path "$CEILING_C.started" || ceiling_setup_ok=0
if [ "$ceiling_setup_ok" -eq 1 ]; then
  MT_GATE_MAX_CONCURRENT=3 start_holder "TEST-CEILING-SIM-D" "$CEILING_D" >"$CEILING_D.log" 2>&1 &
  ceiling_d_pid=$!
  if wait_for_pattern "$CEILING_D.log" "waiting for one of 3 global gate slots" &&
     [ ! -e "$CEILING_D.started" ]; then
    touch "$CEILING_A.release"
    if wait_for_path "$CEILING_D.started"; then
      record_ok "admits three gates at the measured ceiling and queues a fourth"
    else
      record_fail "admits three gates at the measured ceiling and queues a fourth" \
        "fourth gate stayed queued after a ceiling slot opened"
    fi
  else
    record_fail "admits three gates at the measured ceiling and queues a fourth" \
      "fourth gate started while three ceiling slots were occupied"
    touch "$CEILING_A.release"
  fi
  touch "$CEILING_B.release" "$CEILING_C.release" "$CEILING_D.release"
  wait "$ceiling_a_pid" 2>/dev/null
  wait "$ceiling_b_pid" 2>/dev/null
  wait "$ceiling_c_pid" 2>/dev/null
  wait "$ceiling_d_pid" 2>/dev/null
else
  record_fail "admits three gates at the measured ceiling and queues a fourth" \
    "three different simulators could not occupy the three available slots"
  touch "$CEILING_A.release" "$CEILING_B.release" "$CEILING_C.release"
  wait "$ceiling_a_pid" 2>/dev/null
  wait "$ceiling_b_pid" 2>/dev/null
  wait "$ceiling_c_pid" 2>/dev/null
fi

set +e
oversized_cap_out="$(
  MT_GATE_MAX_CONCURRENT=4 \
    run_gate_for "TEST-CAP-OVERSIZED" true 2>&1
)"
oversized_cap_rc=$?
set -e
if [ "$oversized_cap_rc" -ne 0 ] &&
   echo "$oversized_cap_out" | grep -q "cannot exceed the host ceiling of 3"; then
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
   echo "$noncanonical_cap_out" | grep -q "must be 1, 2 or 3"; then
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

CUTOVER_UDID="TEST-CUTOVER-SIM"
CUTOVER_TARGET_ROOT="$TMP/cutover-target-locks"
CUTOVER_LEGACY_ROOT="$TMP/cutover-legacy-locks"
CUTOVER_TARGET="$CUTOVER_TARGET_ROOT/making-tracks-sim-$CUTOVER_UDID.lock"
CUTOVER_LEGACY="$CUTOVER_LEGACY_ROOT/making-tracks-sim-$CUTOVER_UDID.lock"
CUTOVER_HOLDER="$TMP/cutover-holder"
CUTOVER_ACQUIRED="$TMP/cutover-acquired"
mkdir -p "$CUTOVER_TARGET_ROOT" "$CUTOVER_LEGACY_ROOT"
touch "$CUTOVER_TARGET"
ln -s "$CUTOVER_TARGET" "$CUTOVER_LEGACY"
register_release "$CUTOVER_HOLDER"
# Model an old wrapper flocking the legacy pathname after the planned cutover.
# shellcheck disable=SC2016 # Expanded by the holder shell.
(
  exec 6>>"$CUTOVER_LEGACY"
  "$FLOCK_BIN" -x 6
  touch "$CUTOVER_HOLDER.started"
  while [ ! -e "$CUTOVER_HOLDER.release" ]; do sleep 0.02; done
) &
cutover_holder_pid=$!
if wait_for_path "$CUTOVER_HOLDER.started"; then
  MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK_TEST_ROOT="$CUTOVER_TARGET_ROOT" \
    MT_SIM_LOCK_TEST_UDID="$CUTOVER_UDID" \
    MT_SIM_LOCK_TEST_LEDGER="$TEST_LEDGER" \
    MT_SIM_LOCK_WAIT=5 \
    "$SIM_LOCK" --seat codex1 touch "$CUTOVER_ACQUIRED" >"$TMP/cutover-new.log" 2>&1 &
  cutover_new_pid=$!
  cutover_waiting=0
  wait_for_pattern "$TMP/cutover-new.log" "waiting for" || cutover_waiting=1
  cutover_queued=0
  [ ! -e "$CUTOVER_ACQUIRED" ] || cutover_queued=1
  touch "$CUTOVER_HOLDER.release"
  wait "$cutover_holder_pid" 2>/dev/null
  wait "$cutover_new_pid" 2>/dev/null
  if [ "$cutover_waiting" -eq 0 ] &&
     [ "$cutover_queued" -eq 0 ] &&
     [ -e "$CUTOVER_ACQUIRED" ] &&
     [ "$(stat -Lf %i "$CUTOVER_LEGACY")" = "$(stat -f %i "$CUTOVER_TARGET")" ]; then
    record_ok "serializes old and new wrappers through the cutover symlink inode"
  else
    record_fail "serializes old and new wrappers through the cutover symlink inode" \
      "waiting=$cutover_waiting queued=$cutover_queued acquired=$(test -e "$CUTOVER_ACQUIRED" && echo yes || echo no)"
  fi
else
  record_fail "serializes old and new wrappers through the cutover symlink inode" \
    "legacy holder did not start"
fi

echo
echo "release-gate destination contract:"

FAKE_BIN="$TMP/fake-bin"
XCODEBUILD_LOG="$TMP/xcodebuild.log"
XCRUN_LOG="$TMP/xcrun.log"
REAL_GIT="$(command -v git)"
RELEASE_FIXTURE_REPO="$TMP/release-fixture-repo"
RELEASE_FIXTURE_RESOLVED="$RELEASE_FIXTURE_REPO/ios/Package.resolved"
RELEASE_FIXTURE_PBXPROJ="$RELEASE_FIXTURE_REPO/ios/App/MakingTracks.xcodeproj/project.pbxproj"
RELEASE_FIXTURE_HEAD_RESOLVED="$TMP/release-fixture-head-Package.resolved"

reset_release_fixture_repo() {
  rm -rf "$RELEASE_FIXTURE_REPO"
  mkdir -p \
    "$(dirname "$RELEASE_FIXTURE_RESOLVED")" \
    "$(dirname "$RELEASE_FIXTURE_PBXPROJ")"
  cp "$HERE/../ios/Package.resolved" "$RELEASE_FIXTURE_RESOLVED"
  cp "$HERE/../ios/Package.resolved" "$RELEASE_FIXTURE_HEAD_RESOLVED"
  cp "$HERE/../ios/App/MakingTracks.xcodeproj/project.pbxproj" \
    "$RELEASE_FIXTURE_PBXPROJ"
}

reset_release_fixture_repo
mkdir -p "$FAKE_BIN"
# shellcheck disable=SC2016 # These lines are the literal fake-git program.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'run_real_git() {' \
  '  exec "$MT_TEST_REAL_GIT" -C "$MT_TEST_REPO_ROOT" "$@"' \
  '}' \
  'case "$*" in' \
  '  "rev-parse --show-toplevel") printf "%s\n" "$MT_TEST_REPO_ROOT" ;;' \
  '  "fetch --quiet origin ios") exit 0 ;;' \
  '  "merge-base --is-ancestor origin/ios HEAD") exit 0 ;;' \
  '  "ls-files --error-unmatch -- ios/Package.resolved")' \
  '    [ "${MT_TEST_GIT_USE_REAL_REPO:-0}" != "1" ] || run_real_git "$@"' \
  '    [ "${MT_TEST_GIT_TRACKED:-1}" = "1" ]' \
  '    ;;' \
  '  "diff --quiet -- ios/Package.resolved")' \
  '    [ "${MT_TEST_GIT_USE_REAL_REPO:-0}" != "1" ] || run_real_git "$@"' \
  '    [ "${MT_TEST_GIT_UNSTAGED_DIRTY:-0}" = "0" ]' \
  '    ;;' \
  '  "diff --cached --quiet HEAD -- ios/Package.resolved")' \
  '    [ "${MT_TEST_GIT_USE_REAL_REPO:-0}" != "1" ] || run_real_git "$@"' \
  '    [ "${MT_TEST_GIT_STAGED_DIRTY:-0}" = "0" ]' \
  '    ;;' \
  '  "show HEAD:ios/Package.resolved")' \
  '    [ "${MT_TEST_GIT_USE_REAL_REPO:-0}" != "1" ] || run_real_git "$@"' \
  '    /bin/cat "${MT_TEST_PACKAGE_RESOLVED_HEAD:-$MT_TEST_REPO_ROOT/ios/Package.resolved}"' \
  '    ;;' \
  '  *) exit 97 ;;' \
  'esac' >"$FAKE_BIN/git"
# shellcheck disable=SC2016 # These lines are the literal fake-xcrun program.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '[ -z "${MT_TEST_XCRUN_LOG:-}" ] || printf "%s\n" "$*" >>"$MT_TEST_XCRUN_LOG"' \
  'exit 0' >"$FAKE_BIN/xcrun"
# shellcheck disable=SC2016 # Expanded when the fake xcodebuild runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >>"$MT_TEST_XCODEBUILD_LOG"' \
  'test_status=0' \
  'if [ "${MT_TEST_XCODEBUILD_MUTATE_RESOLVED:-0}" = "1" ]; then' \
  '  printf "%s\n" mutated >>"$MT_TEST_PACKAGE_RESOLVED"' \
  'fi' \
  'case " $* " in *" test-without-building "*) test_status="${MT_TEST_XCODEBUILD_TEST_STATUS:-0}" ;; esac' \
  'case " $* " in *" build "*) test_status="${MT_TEST_XCODEBUILD_BUILD_STATUS:-$test_status}" ;; esac' \
  'while [ "$#" -gt 0 ]; do' \
  '  case "$1" in' \
  '    -resultBundlePath)' \
  '      shift' \
  '      mkdir -p "$1"' \
  '      printf "%s\n" fake-result >"$1/Info.plist"' \
  '      ;;' \
  '    -test-enumeration-output-path)' \
  '      shift' \
  '      mkdir -p "$(dirname "$1")"' \
  '      printf "%s\n" "{\"tests\":[]}" >"$1"' \
  '      ;;' \
  '  esac' \
  '  shift' \
  'done' \
  'exit "$test_status"' >"$FAKE_BIN/xcodebuild"
chmod +x "$FAKE_BIN/git" "$FAKE_BIN/xcrun" "$FAKE_BIN/xcodebuild"

run_artifact_gate() {
  local mode="$1"
  shift

  env "$@" \
    PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$RELEASE_FIXTURE_REPO" \
    MT_TEST_PACKAGE_RESOLVED="$RELEASE_FIXTURE_RESOLVED" \
    MT_TEST_PACKAGE_RESOLVED_HEAD="$RELEASE_FIXTURE_HEAD_RESOLVED" \
    MT_TEST_REAL_GIT="$REAL_GIT" \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_TEST_XCRUN_LOG="$XCRUN_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_DERIVED_DATA="$SAFE_TEST_ROOT/artifact-derived-data" \
    MT_RELEASE_GATE_MODE="$mode" \
    "$RELEASE_GATE"
}

run_artifact_gate_with_system_bash() {
  local mode="$1"
  shift

  env "$@" \
    PATH="$FAKE_BIN:/bin:/usr/bin:/usr/sbin:/sbin" \
    MT_TEST_REPO_ROOT="$RELEASE_FIXTURE_REPO" \
    MT_TEST_PACKAGE_RESOLVED="$RELEASE_FIXTURE_RESOLVED" \
    MT_TEST_PACKAGE_RESOLVED_HEAD="$RELEASE_FIXTURE_HEAD_RESOLVED" \
    MT_TEST_REAL_GIT="$REAL_GIT" \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_TEST_XCRUN_LOG="$XCRUN_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_DERIVED_DATA="$SAFE_TEST_ROOT/artifact-derived-data" \
    MT_RELEASE_GATE_MODE="$mode" \
    /bin/bash "$RELEASE_GATE"
}

all_xcode_calls_use_committed_resolution() {
  local expected_calls="$1"
  local flag="-onlyUsePackageVersionsFromResolvedFile"

  [ "$(wc -l <"$XCODEBUILD_LOG" | tr -d '[:space:]')" = "$expected_calls" ] ||
    return 1
  awk -v flag="$flag" '{
    count = 0
    for (i = 1; i <= NF; i++) if ($i == flag) count++
    if (count != 1) exit 1
  }' "$XCODEBUILD_LOG"
}

check_package_resolution_preflight() {
  local gate_out
  local gate_rc
  local name="$1"
  shift

  : >"$XCODEBUILD_LOG"
  : >"$XCRUN_LOG"
  set +e
  gate_out="$(run_artifact_gate build "$@" 2>&1)"
  gate_rc=$?
  set -e
  if [ "$gate_rc" -ne 0 ] &&
     echo "$gate_out" | grep -Fq 'ios/Package.resolved' &&
     echo "$gate_out" | grep -Fq \
       'commit the intentional update, or restore it from HEAD' &&
     [ ! -s "$XCODEBUILD_LOG" ] &&
     [ ! -s "$XCRUN_LOG" ]; then
    record_ok "$name"
  else
    record_fail "$name" \
      "status=$gate_rc xcode=$(wc -l <"$XCODEBUILD_LOG" | tr -d '[:space:]') sim=$(wc -l <"$XCRUN_LOG" | tr -d '[:space:]') output='$(echo "$gate_out" | tail -1)'"
  fi
  reset_release_fixture_repo
}

rm -f "$RELEASE_FIXTURE_RESOLVED"
check_package_resolution_preflight \
  "release gate refuses an absent Package.resolved before Xcode"

rm -f "$RELEASE_FIXTURE_RESOLVED"
ln -s "$HERE/../ios/Package.resolved" "$RELEASE_FIXTURE_RESOLVED"
check_package_resolution_preflight \
  "release gate refuses a symlinked Package.resolved before Xcode"

check_package_resolution_preflight \
  "release gate refuses an untracked Package.resolved before Xcode" \
  MT_TEST_GIT_TRACKED=0

printf '%s\n' mutated >>"$RELEASE_FIXTURE_RESOLVED"
check_package_resolution_preflight \
  "release gate refuses an unstaged Package.resolved before Xcode"

check_package_resolution_preflight \
  "release gate refuses a staged Package.resolved before Xcode" \
  MT_TEST_GIT_STAGED_DIRTY=1

"$REAL_GIT" -C "$RELEASE_FIXTURE_REPO" init -q
"$REAL_GIT" -C "$RELEASE_FIXTURE_REPO" config user.name "Release Gate Fixture"
"$REAL_GIT" -C "$RELEASE_FIXTURE_REPO" config user.email "release-gate-fixture@example.invalid"
"$REAL_GIT" -C "$RELEASE_FIXTURE_REPO" add ios/Package.resolved ios/App/MakingTracks.xcodeproj/project.pbxproj
"$REAL_GIT" -C "$RELEASE_FIXTURE_REPO" commit -q -m fixture
"$REAL_GIT" -C "$RELEASE_FIXTURE_REPO" update-index --skip-worktree ios/Package.resolved
printf '%s\n' hidden-mutation >>"$RELEASE_FIXTURE_RESOLVED"
check_package_resolution_preflight \
  "release gate compares Package.resolved bytes with HEAD despite skip-worktree" \
  MT_TEST_GIT_USE_REAL_REPO=1

rm -rf "$RELEASE_RUN_DIR_A"
: >"$XCODEBUILD_LOG"
: >"$XCRUN_LOG"
set +e
mutating_resolution_out="$(
  run_artifact_gate full MT_TEST_XCODEBUILD_MUTATE_RESOLVED=1 2>&1
)"
mutating_resolution_rc=$?
set -e
mutating_resolution_calls="$(wc -l <"$XCODEBUILD_LOG" | tr -d '[:space:]')"
mutating_resolution_success=0
for mutating_resolution_run in "$RELEASE_RUN_DIR_A"/runs/run-*; do
  [ ! -f "$mutating_resolution_run/.release-gate-success" ] ||
    mutating_resolution_success=1
done
if [ "$mutating_resolution_rc" -ne 0 ] &&
   [ "$mutating_resolution_calls" = "1" ] &&
   echo "$mutating_resolution_out" | grep -Fq \
     'dependency resolution drift' &&
   [ "$mutating_resolution_success" -eq 0 ]; then
  record_ok \
    "release gate rejects a successful Xcode phase that changes Package.resolved"
else
  record_fail \
    "release gate rejects a successful Xcode phase that changes Package.resolved" \
    "status=$mutating_resolution_rc calls=$mutating_resolution_calls success=$mutating_resolution_success output='$(echo "$mutating_resolution_out" | tail -1)'"
fi
reset_release_fixture_repo
rm -rf "$RELEASE_RUN_DIR_A"

: >"$XCODEBUILD_LOG"
: >"$XCRUN_LOG"
set +e
failed_mutating_resolution_out="$(
  run_artifact_gate full \
    MT_TEST_XCODEBUILD_MUTATE_RESOLVED=1 \
    MT_TEST_XCODEBUILD_BUILD_STATUS=73 2>&1
)"
failed_mutating_resolution_rc=$?
set -e
failed_mutating_resolution_calls="$(wc -l <"$XCODEBUILD_LOG" | tr -d '[:space:]')"
if [ "$failed_mutating_resolution_rc" -eq 1 ] &&
   [ "$failed_mutating_resolution_calls" = "1" ] &&
   echo "$failed_mutating_resolution_out" | grep -Fq \
     'dependency resolution drift' &&
   echo "$failed_mutating_resolution_out" | grep -Fq \
     'phase end: release build status=1'; then
  record_ok "release gate lets resolution drift override a failing Xcode phase"
else
  record_fail "release gate lets resolution drift override a failing Xcode phase" \
    "status=$failed_mutating_resolution_rc calls=$failed_mutating_resolution_calls output='$(echo "$failed_mutating_resolution_out" | tail -1)'"
fi
reset_release_fixture_repo
rm -rf "$RELEASE_RUN_DIR_A"

: >"$XCODEBUILD_LOG"
: >"$XCRUN_LOG"
set +e
unchanged_failure_out="$(
  run_artifact_gate build MT_TEST_XCODEBUILD_BUILD_STATUS=73 2>&1
)"
unchanged_failure_rc=$?
set -e
if [ "$unchanged_failure_rc" -eq 73 ] &&
   echo "$unchanged_failure_out" | grep -Fq \
     'phase end: release build status=73'; then
  record_ok "release gate preserves an unchanged failing Xcode phase status"
else
  record_fail "release gate preserves an unchanged failing Xcode phase status" \
    "status=$unchanged_failure_rc output='$(echo "$unchanged_failure_out" | tail -1)'"
fi
reset_release_fixture_repo

rm -rf "$RELEASE_RUN_DIR_A"
: >"$XCODEBUILD_LOG"
set +e
pinned_full_out="$(run_artifact_gate full 2>&1)"
pinned_full_rc=$?
set -e
if [ "$pinned_full_rc" -eq 0 ] &&
   all_xcode_calls_use_committed_resolution 3; then
  record_ok "full release gate pins all three Xcode phases to Package.resolved"
else
  record_fail "full release gate pins all three Xcode phases to Package.resolved" \
    "status=$pinned_full_rc calls=$(wc -l <"$XCODEBUILD_LOG" | tr -d '[:space:]') output='$(echo "$pinned_full_out" | tail -1)'"
fi
rm -rf "$RELEASE_RUN_DIR_A"
reset_release_fixture_repo

PINNED_ENUMERATION="$TMP/pinned-enumerated-tests.json"
rm -f "$PINNED_ENUMERATION"
: >"$XCODEBUILD_LOG"
set +e
pinned_enumeration_out="$(
  run_artifact_gate enumerate \
    MT_RELEASE_GATE_ENUMERATED_TESTS_JSON="$PINNED_ENUMERATION" 2>&1
)"
pinned_enumeration_rc=$?
set -e
if [ "$pinned_enumeration_rc" -eq 0 ] &&
   [ -f "$PINNED_ENUMERATION" ] &&
   all_xcode_calls_use_committed_resolution 1; then
  record_ok "enumeration gate pins Xcode to Package.resolved"
else
  record_fail "enumeration gate pins Xcode to Package.resolved" \
    "status=$pinned_enumeration_rc calls=$(wc -l <"$XCODEBUILD_LOG" | tr -d '[:space:]') output='$(echo "$pinned_enumeration_out" | tail -1)'"
fi
rm -f "$PINNED_ENUMERATION"
reset_release_fixture_repo

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

SAFE_DERIVED_DATA="$SAFE_TEST_ROOT/safe-derived-data"
SYMLINKED_SAFE_PARENT="$TMP/safe-looking-parent"
DANGLING_RELEASE_DERIVED_DATA="$TMP/safe-dangling-release-derived-data"
ln -s /private/tmp "$SYMLINKED_SAFE_PARENT"
ln -s "$DANGLING_TMP_TARGET" "$DANGLING_RELEASE_DERIVED_DATA"

for unsafe_derived_data in \
  /private/tmp/mt-612-release-gate-private \
  /tmp/mt-612-release-gate-tmp \
  /var/tmp/mt-612-release-gate-var-tmp \
  "$TMP/mt-612-release-gate-user-temp" \
  "$SYMLINKED_SAFE_PARENT/mt-612-release-gate-symlink"; do
  rm -f "$XCODEBUILD_LOG"
  set +e
  unsafe_gate_out="$(
    PATH="$FAKE_BIN:$PATH" \
      MT_TEST_REPO_ROOT="$HERE/.." \
      MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
      MT_SIM_LOCK=1 \
      MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
      MT_SIM_LOCK_SEAT=codex1 \
      MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
      MT_RELEASE_GATE_DERIVED_DATA="$unsafe_derived_data" \
      MT_RELEASE_GATE_MODE=build \
      "$RELEASE_GATE" 2>&1
  )"
  unsafe_gate_rc=$?
  set -e
  if [ "$unsafe_gate_rc" -ne 0 ] &&
     echo "$unsafe_gate_out" | grep -q '#612' &&
     [ ! -e "$XCODEBUILD_LOG" ]; then
    record_ok "release gate refuses temporary DerivedData before Xcode: $unsafe_derived_data"
  else
    record_fail "release gate refuses temporary DerivedData before Xcode: $unsafe_derived_data" \
      "status=$unsafe_gate_rc output='$(echo "$unsafe_gate_out" | head -1)' xcode=$(test -e "$XCODEBUILD_LOG" && echo ran || echo absent)"
  fi
done

mkdir -p "$UNSAFE_EXISTING_DERIVED_DATA"
printf '%s\n' sentinel >"$UNSAFE_EXISTING_DERIVED_DATA/sentinel"
rm -f "$XCODEBUILD_LOG"
set +e
unsafe_existing_gate_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_CLEAN_DERIVED_DATA=1 \
    MT_RELEASE_GATE_DERIVED_DATA="$UNSAFE_EXISTING_DERIVED_DATA" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
unsafe_existing_gate_rc=$?
set -e
if [ "$unsafe_existing_gate_rc" -ne 0 ] &&
   echo "$unsafe_existing_gate_out" | grep -q '#612' &&
   [ -f "$UNSAFE_EXISTING_DERIVED_DATA/sentinel" ] &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "release gate refuses temporary DerivedData before pruning it"
else
  record_fail "release gate refuses temporary DerivedData before pruning it" \
    "status=$unsafe_existing_gate_rc output='$(echo "$unsafe_existing_gate_out" | head -1)' sentinel=$(test -f "$UNSAFE_EXISTING_DERIVED_DATA/sentinel" && echo present || echo absent) xcode=$(test -e "$XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -rf "$UNSAFE_MISSING_DERIVED_DATA"
rm -f "$XCODEBUILD_LOG"
set +e
unsafe_missing_gate_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_CLEAN_DERIVED_DATA=1 \
    MT_RELEASE_GATE_DERIVED_DATA="$UNSAFE_MISSING_DERIVED_DATA" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
unsafe_missing_gate_rc=$?
set -e
if [ "$unsafe_missing_gate_rc" -ne 0 ] &&
   echo "$unsafe_missing_gate_out" | grep -q '#612' &&
   [ ! -e "$UNSAFE_MISSING_DERIVED_DATA" ] &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "release gate refuses temporary DerivedData before creating it"
else
  record_fail "release gate refuses temporary DerivedData before creating it" \
    "status=$unsafe_missing_gate_rc output='$(echo "$unsafe_missing_gate_out" | head -1)' derived_data=$(test -e "$UNSAFE_MISSING_DERIVED_DATA" && echo created || echo absent) xcode=$(test -e "$XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -rf "$UNSAFE_ALIAS_EQUAL"
rm -f "$XCODEBUILD_LOG"
set +e
unsafe_alias_equal_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_CLEAN_DERIVED_DATA=1 \
    MT_RELEASE_GATE_DERIVED_DATA="$UNSAFE_ALIAS_EQUAL" \
    MT_RELEASE_GATE_RUN_DIR="$UNSAFE_ALIAS_EQUAL" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
unsafe_alias_equal_rc=$?
set -e
if [ "$unsafe_alias_equal_rc" -ne 0 ] &&
   echo "$unsafe_alias_equal_out" | grep -q '#612' &&
   [ ! -e "$UNSAFE_ALIAS_EQUAL" ] &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "release gate validates unsafe DerivedData before creating an equal run directory"
else
  record_fail "release gate validates unsafe DerivedData before creating an equal run directory" \
    "status=$unsafe_alias_equal_rc output='$(echo "$unsafe_alias_equal_out" | head -1)' path=$(test -e "$UNSAFE_ALIAS_EQUAL" && echo created || echo absent) xcode=$(test -e "$XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -rf "$UNSAFE_ALIAS_ANCESTOR"
rm -f "$XCODEBUILD_LOG"
set +e
unsafe_alias_ancestor_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_CLEAN_DERIVED_DATA=1 \
    MT_RELEASE_GATE_DERIVED_DATA="$UNSAFE_ALIAS_ANCESTOR/DerivedData" \
    MT_RELEASE_GATE_RUN_DIR="$UNSAFE_ALIAS_ANCESTOR" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
unsafe_alias_ancestor_rc=$?
set -e
if [ "$unsafe_alias_ancestor_rc" -ne 0 ] &&
   echo "$unsafe_alias_ancestor_out" | grep -q '#612' &&
   [ ! -e "$UNSAFE_ALIAS_ANCESTOR" ] &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "release gate validates unsafe DerivedData before creating an ancestor run directory"
else
  record_fail "release gate validates unsafe DerivedData before creating an ancestor run directory" \
    "status=$unsafe_alias_ancestor_rc output='$(echo "$unsafe_alias_ancestor_out" | head -1)' path=$(test -e "$UNSAFE_ALIAS_ANCESTOR" && echo created || echo absent) xcode=$(test -e "$XCODEBUILD_LOG" && echo ran || echo absent)"
fi

mkdir -p "$UNSAFE_ALIAS_DESCENDANT"
printf '%s\n' sentinel >"$UNSAFE_ALIAS_DESCENDANT/sentinel"
rm -rf "$UNSAFE_ALIAS_DESCENDANT/run"
rm -f "$XCODEBUILD_LOG"
set +e
unsafe_alias_descendant_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_CLEAN_DERIVED_DATA=1 \
    MT_RELEASE_GATE_DERIVED_DATA="$UNSAFE_ALIAS_DESCENDANT" \
    MT_RELEASE_GATE_RUN_DIR="$UNSAFE_ALIAS_DESCENDANT/run" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
unsafe_alias_descendant_rc=$?
set -e
if [ "$unsafe_alias_descendant_rc" -ne 0 ] &&
   echo "$unsafe_alias_descendant_out" | grep -q '#612' &&
   [ -f "$UNSAFE_ALIAS_DESCENDANT/sentinel" ] &&
   [ ! -e "$UNSAFE_ALIAS_DESCENDANT/run" ] &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "release gate validates unsafe DerivedData before creating a descendant run directory"
else
  record_fail "release gate validates unsafe DerivedData before creating a descendant run directory" \
    "status=$unsafe_alias_descendant_rc output='$(echo "$unsafe_alias_descendant_out" | head -1)' sentinel=$(test -f "$UNSAFE_ALIAS_DESCENDANT/sentinel" && echo present || echo absent) run_dir=$(test -e "$UNSAFE_ALIAS_DESCENDANT/run" && echo created || echo absent) xcode=$(test -e "$XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -f "$XCODEBUILD_LOG"
set +e
dangling_release_gate_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_DERIVED_DATA="$DANGLING_RELEASE_DERIVED_DATA" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
dangling_release_gate_rc=$?
set -e
if [ "$dangling_release_gate_rc" -ne 0 ] &&
   echo "$dangling_release_gate_out" | grep -q '#612' &&
   [ ! -e "$XCODEBUILD_LOG" ]; then
  record_ok "release gate refuses a dangling DerivedData symlink to temporary storage before Xcode"
else
  record_fail "release gate refuses a dangling DerivedData symlink to temporary storage before Xcode" \
    "status=$dangling_release_gate_rc output='$(echo "$dangling_release_gate_out" | head -1)' xcode=$(test -e "$XCODEBUILD_LOG" && echo ran || echo absent)"
fi

rm -f "$XCODEBUILD_LOG"
set +e
safe_gate_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_DERIVED_DATA="$SAFE_DERIVED_DATA" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
safe_gate_rc=$?
set -e
if [ "$safe_gate_rc" -eq 0 ] &&
   grep -Fq -- "-derivedDataPath $SAFE_DERIVED_DATA" "$XCODEBUILD_LOG"; then
  record_ok "release gate passes a safe explicit DerivedData path to Xcode unchanged"
else
  record_fail "release gate passes a safe explicit DerivedData path to Xcode unchanged" \
    "status=$safe_gate_rc output='$(echo "$safe_gate_out" | head -1)' args='$(head -1 "$XCODEBUILD_LOG" 2>/dev/null)'"
fi

run_release_fixture() {
  local udid="$1"
  : >"$XCODEBUILD_LOG"
  PATH="$FAKE_BIN:$PATH" \
  MT_TEST_REPO_ROOT="$HERE/.." \
  MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
  MT_SIM_LOCK=1 \
  MT_SIM_LOCK_UDID="$udid" \
  MT_SIM_LOCK_SEAT=codex1 \
  MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$udid" \
  MT_RELEASE_GATE_MODE=build \
  HOME="$RELEASE_FIXTURE_HOME" \
  "$RELEASE_GATE" >/dev/null 2>&1
  grep -o -- '-derivedDataPath [^ ]*' "$XCODEBUILD_LOG" | head -1
}

derived_a="$(run_release_fixture "$RELEASE_UDID_A")"
derived_b="$(run_release_fixture "$RELEASE_UDID_B")"
expected_a="-derivedDataPath $RELEASE_FIXTURE_HOME/Library/Caches/making-tracks-gates/codex1"
expected_b="-derivedDataPath $RELEASE_FIXTURE_HOME/Library/Caches/making-tracks-gates/codex1"
if [ "$derived_a" = "$expected_a" ] && [ "$derived_b" = "$expected_b" ]; then
  record_ok "derives the exact persistent default DerivedData path for the selected seat"
else
  record_fail "derives the exact persistent default DerivedData path for the selected seat" \
    "first='$derived_a' expected='$expected_a' second='$derived_b' expected='$expected_b'"
fi

echo
echo "release-gate artifact ownership:"

ARTIFACT_RUNS_A="$RELEASE_RUN_DIR_A/runs"
EXPECTED_ARTIFACT_MARKER="$(printf 'release-gate-artifact-v1\nudid=%s' "$RELEASE_UDID_A")"

rm -rf "$RELEASE_RUN_DIR_A"
: >"$XCODEBUILD_LOG"
set +e
owned_success_out="$(run_artifact_gate test 2>&1)"
owned_success_rc=$?
set -e
owned_success_runs=("$ARTIFACT_RUNS_A"/run-*)
if [ "$owned_success_rc" -eq 0 ] &&
   [ "${#owned_success_runs[@]}" -eq 1 ] &&
   [ -d "${owned_success_runs[0]}/MakingTracksTests.xcresult" ] &&
   [ ! -L "${owned_success_runs[0]}/.release-gate-owned" ] &&
   [ "$(cat "${owned_success_runs[0]}/.release-gate-owned" 2>/dev/null)" = "$EXPECTED_ARTIFACT_MARKER" ] &&
   [ ! -L "${owned_success_runs[0]}/.release-gate-success" ] &&
   [ "$(cat "${owned_success_runs[0]}/.release-gate-success" 2>/dev/null)" = "$EXPECTED_ARTIFACT_MARKER" ]; then
  record_ok "successful local artifact run is uniquely owned and success-marked"
else
  record_fail "successful local artifact run is uniquely owned and success-marked" \
    "status=$owned_success_rc runs=${#owned_success_runs[@]} output='$(echo "$owned_success_out" | tail -1)'"
fi

rm -rf "$RELEASE_RUN_DIR_A"
: >"$XCODEBUILD_LOG"
set +e
system_bash_artifact_out="$(run_artifact_gate_with_system_bash test 2>&1)"
system_bash_artifact_rc=$?
set -e
if [ "$system_bash_artifact_rc" -eq 0 ] &&
   echo "$system_bash_artifact_out" | grep -q 'phase end: tests without building status=0'; then
  record_ok "runs an unfiltered owned test gate with macOS system Bash 3.2"
else
  record_fail "runs an unfiltered owned test gate with macOS system Bash 3.2" \
    "status=$system_bash_artifact_rc output='$(echo "$system_bash_artifact_out" | tail -1)'"
fi

rm -rf "$RELEASE_RUN_DIR_A"
mkdir -p "$ARTIFACT_RUNS_A/run-20260801T000000Z-9001"
printf 'release-gate-artifact-v1\nudid=%s\n' "$RELEASE_UDID_A" \
  >"$ARTIFACT_RUNS_A/run-20260801T000000Z-9001/.release-gate-owned"
printf 'release-gate-artifact-v1\nudid=%s\n' "$RELEASE_UDID_A" \
  >"$ARTIFACT_RUNS_A/run-20260801T000000Z-9001/.release-gate-success"
printf '%s\n' preserve >"$ARTIFACT_RUNS_A/run-20260801T000000Z-9001/sentinel"
: >"$XCODEBUILD_LOG"
set +e
owned_failure_out="$(run_artifact_gate full MT_TEST_XCODEBUILD_TEST_STATUS=9 2>&1)"
owned_failure_rc=$?
set -e
owned_failure_runs=("$ARTIFACT_RUNS_A"/run-*)
owned_failure_dir=""
for candidate in "${owned_failure_runs[@]}"; do
  [ "$(basename "$candidate")" = "run-20260801T000000Z-9001" ] || owned_failure_dir="$candidate"
done
if [ "$owned_failure_rc" -eq 9 ] &&
   [ -n "$owned_failure_dir" ] &&
   [ -d "$owned_failure_dir/MakingTracksTests.xcresult" ] &&
   [ "$(cat "$owned_failure_dir/.release-gate-owned" 2>/dev/null)" = "$EXPECTED_ARTIFACT_MARKER" ] &&
   [ ! -e "$owned_failure_dir/.release-gate-success" ] &&
   [ -f "$ARTIFACT_RUNS_A/run-20260801T000000Z-9001/sentinel" ]; then
  record_ok "failed full gate preserves its unmarked result and does not prune"
else
  record_fail "failed full gate preserves its unmarked result and does not prune" \
    "status=$owned_failure_rc failure_dir='$owned_failure_dir' runs=${#owned_failure_runs[@]} output='$(echo "$owned_failure_out" | tail -1)'"
fi

write_artifact_identity() {
  local path="$1"
  local udid="$2"

  printf 'release-gate-artifact-v1\nudid=%s\n' "$udid" >"$path"
}

seed_successful_artifact() {
  local run_dir="$1"
  local udid="$2"

  mkdir -p "$run_dir"
  write_artifact_identity "$run_dir/.release-gate-owned" "$udid"
  write_artifact_identity "$run_dir/.release-gate-success" "$udid"
  printf '%s\n' preserve >"$run_dir/sentinel"
}

rm -rf "$RELEASE_RUN_DIR_A" "$RELEASE_RUN_DIR_B"
mkdir -p "$ARTIFACT_RUNS_A"
old_success="$ARTIFACT_RUNS_A/run-20260801T000000Z-9101"
equal_success="$ARTIFACT_RUNS_A/run-20260801T000000Z-9102"
unmarked_failure="$ARTIFACT_RUNS_A/run-20260801T000000Z-9103"
wrong_owner="$ARTIFACT_RUNS_A/run-20260801T000000Z-9104"
wrong_success="$ARTIFACT_RUNS_A/run-20260801T000000Z-9105"
wrong_uuid="$ARTIFACT_RUNS_A/run-20260801T000000Z-9106"
symlink_owner="$ARTIFACT_RUNS_A/run-20260801T000000Z-9107"
symlink_success="$ARTIFACT_RUNS_A/run-20260801T000000Z-9108"
invalid_name="$ARTIFACT_RUNS_A/run-invalid-9109"
nested_success="$ARTIFACT_RUNS_A/container/run-20260801T000000Z-9110"
outside_success="$RELEASE_RUN_DIR_B/runs/run-20260801T000000Z-9111"
symlink_target="$TMP/run-20260801T000000Z-9112-target"
symlink_run="$ARTIFACT_RUNS_A/run-20260801T000000Z-9112"
external_owner="$TMP/release-gate-owner-marker"
external_success="$TMP/release-gate-success-marker"

seed_successful_artifact "$old_success" "$RELEASE_UDID_A"
seed_successful_artifact "$equal_success" "$RELEASE_UDID_A"
mkdir -p "$unmarked_failure"
write_artifact_identity "$unmarked_failure/.release-gate-owned" "$RELEASE_UDID_A"
printf '%s\n' preserve >"$unmarked_failure/sentinel"
seed_successful_artifact "$wrong_owner" "$RELEASE_UDID_A"
printf '%s\n' wrong >"$wrong_owner/.release-gate-owned"
seed_successful_artifact "$wrong_success" "$RELEASE_UDID_A"
printf '%s\n' wrong >"$wrong_success/.release-gate-success"
seed_successful_artifact "$wrong_uuid" "$RELEASE_UDID_B"
seed_successful_artifact "$invalid_name" "$RELEASE_UDID_A"
seed_successful_artifact "$nested_success" "$RELEASE_UDID_A"
seed_successful_artifact "$outside_success" "$RELEASE_UDID_B"
mkdir -p "$symlink_target"
printf '%s\n' preserve >"$symlink_target/sentinel"
ln -s "$symlink_target" "$symlink_run"
mkdir -p "$symlink_owner" "$symlink_success"
write_artifact_identity "$external_owner" "$RELEASE_UDID_A"
write_artifact_identity "$external_success" "$RELEASE_UDID_A"
ln -s "$external_owner" "$symlink_owner/.release-gate-owned"
write_artifact_identity "$symlink_owner/.release-gate-success" "$RELEASE_UDID_A"
printf '%s\n' preserve >"$symlink_owner/sentinel"
write_artifact_identity "$symlink_success/.release-gate-owned" "$RELEASE_UDID_A"
ln -s "$external_success" "$symlink_success/.release-gate-success"
printf '%s\n' preserve >"$symlink_success/sentinel"

TZ=UTC touch -t 197001020733.19 "$old_success/.release-gate-success"
TZ=UTC touch -t 197001020733.20 "$equal_success/.release-gate-success"
for retained_marker in \
  "$wrong_owner/.release-gate-success" \
  "$wrong_success/.release-gate-success" \
  "$wrong_uuid/.release-gate-success" \
  "$invalid_name/.release-gate-success" \
  "$nested_success/.release-gate-success" \
  "$outside_success/.release-gate-success" \
  "$symlink_owner/.release-gate-success"; do
  TZ=UTC touch -t 197001020733.19 "$retained_marker"
done

: >"$XCODEBUILD_LOG"
set +e
prune_out="$(run_artifact_gate full MT_RELEASE_GATE_TEST_NOW=200000 2>&1)"
prune_rc=$?
set -e
current_owned_run="$(echo "$prune_out" | sed -n 's/^release-gate: owned artifacts: //p' | head -1)"
if [ "$prune_rc" -eq 0 ] &&
   [ ! -e "$old_success" ] &&
   [ -f "$equal_success/sentinel" ] &&
   [ -f "$unmarked_failure/sentinel" ] &&
   [ -f "$wrong_owner/sentinel" ] &&
   [ -f "$wrong_success/sentinel" ] &&
   [ -f "$wrong_uuid/sentinel" ] &&
   [ -f "$invalid_name/sentinel" ] &&
   [ -f "$nested_success/sentinel" ] &&
   [ -f "$outside_success/sentinel" ] &&
   [ -f "$symlink_target/sentinel" ] &&
   [ -L "$symlink_run" ] &&
   [ -f "$symlink_owner/sentinel" ] &&
   [ -f "$symlink_success/sentinel" ] &&
   [ -n "$current_owned_run" ] &&
   [ -d "$current_owned_run" ] &&
   [ -f "$current_owned_run/.release-gate-success" ]; then
  record_ok "successful full gate prunes only exact owned successes older than 86400 seconds"
else
  record_fail "successful full gate prunes only exact owned successes older than 86400 seconds" \
    "status=$prune_rc old=$(test -e "$old_success" && echo present || echo removed) current='$current_owned_run' output='$(echo "$prune_out" | tail -1)'"
fi

echo
echo "release-gate caller and CI artifact ownership:"

CALLER_RESULT="$TMP/caller-result.xcresult"
mkdir -p "$CALLER_RESULT"
printf '%s\n' preserve >"$CALLER_RESULT/sentinel"
: >"$XCODEBUILD_LOG"
set +e
caller_result_out="$(run_artifact_gate test MT_RELEASE_GATE_RESULT_BUNDLE="$CALLER_RESULT" 2>&1)"
caller_result_rc=$?
set -e
if [ "$caller_result_rc" -ne 0 ] &&
   echo "$caller_result_out" | grep -q 'caller-owned result already exists' &&
   [ -f "$CALLER_RESULT/sentinel" ] &&
   [ ! -s "$XCODEBUILD_LOG" ]; then
  record_ok "refuses and preserves an existing caller-named result before Xcode"
else
  record_fail "refuses and preserves an existing caller-named result before Xcode" \
    "status=$caller_result_rc sentinel=$(test -f "$CALLER_RESULT/sentinel" && echo present || echo missing) output='$(echo "$caller_result_out" | tail -1)'"
fi

CALLER_RUN="$TMP/caller-run"
mkdir -p "$CALLER_RUN/MakingTracksTests.xcresult"
printf '%s\n' preserve >"$CALLER_RUN/MakingTracksTests.xcresult/sentinel"
: >"$XCODEBUILD_LOG"
set +e
caller_run_out="$(run_artifact_gate test MT_RELEASE_GATE_RUN_DIR="$CALLER_RUN" 2>&1)"
caller_run_rc=$?
set -e
if [ "$caller_run_rc" -ne 0 ] &&
   echo "$caller_run_out" | grep -q 'caller-owned result already exists' &&
   [ -f "$CALLER_RUN/MakingTracksTests.xcresult/sentinel" ] &&
   [ ! -s "$XCODEBUILD_LOG" ]; then
  record_ok "refuses and preserves an existing result beneath a caller-named run directory"
else
  record_fail "refuses and preserves an existing result beneath a caller-named run directory" \
    "status=$caller_run_rc sentinel=$(test -f "$CALLER_RUN/MakingTracksTests.xcresult/sentinel" && echo present || echo missing) output='$(echo "$caller_run_out" | tail -1)'"
fi

FRESH_CALLER_RESULT="$TMP/fresh-caller-result.xcresult"
: >"$XCODEBUILD_LOG"
set +e
fresh_caller_out="$(run_artifact_gate test MT_RELEASE_GATE_RESULT_BUNDLE="$FRESH_CALLER_RESULT" 2>&1)"
fresh_caller_rc=$?
set -e
if [ "$fresh_caller_rc" -eq 0 ] &&
   [ -f "$FRESH_CALLER_RESULT/Info.plist" ] &&
   [ ! -e "$(dirname "$FRESH_CALLER_RESULT")/.release-gate-owned" ] &&
   [ ! -e "$(dirname "$FRESH_CALLER_RESULT")/.release-gate-success" ]; then
  record_ok "populates a fresh caller-named result without enrolling it in cleanup"
else
  record_fail "populates a fresh caller-named result without enrolling it in cleanup" \
    "status=$fresh_caller_rc output='$(echo "$fresh_caller_out" | tail -1)'"
fi

CALLER_ENUMERATION="$TMP/caller-enumerated-tests.json"
: >"$XCODEBUILD_LOG"
set +e
caller_enumeration_out="$(run_artifact_gate enumerate MT_RELEASE_GATE_ENUMERATED_TESTS_JSON="$CALLER_ENUMERATION" 2>&1)"
caller_enumeration_rc=$?
set -e
if [ "$caller_enumeration_rc" -eq 0 ] &&
   grep -q '"tests":\[\]' "$CALLER_ENUMERATION"; then
  record_ok "preserves an explicit enumeration artifact outside the cleanup root"
else
  record_fail "preserves an explicit enumeration artifact outside the cleanup root" \
    "status=$caller_enumeration_rc output='$(echo "$caller_enumeration_out" | tail -1)'"
fi

rm -rf "$RELEASE_RUN_DIR_A"
mkdir -p "$ARTIFACT_RUNS_A"
nested_caller_run="$ARTIFACT_RUNS_A/run-20260801T000000Z-9201"
nested_caller_result="$nested_caller_run/caller-owned.xcresult"
seed_successful_artifact "$nested_caller_run" "$RELEASE_UDID_A"
: >"$XCODEBUILD_LOG"
set +e
nested_caller_out="$(run_artifact_gate test MT_RELEASE_GATE_RESULT_BUNDLE="$nested_caller_result" 2>&1)"
nested_caller_rc=$?
set -e
TZ=UTC touch -t 197001020733.19 "$nested_caller_run/.release-gate-success"
set +e
nested_prune_out="$(run_artifact_gate full MT_RELEASE_GATE_TEST_NOW=200000 2>&1)"
nested_prune_rc=$?
set -e
if [ "$nested_caller_rc" -eq 0 ] &&
   [ "$nested_prune_rc" -eq 0 ] &&
   [ -f "$nested_caller_result/Info.plist" ] &&
   [ -f "$nested_caller_run/.release-gate-preserve" ]; then
  record_ok "caller override inside an owned sibling permanently disqualifies that sibling"
else
  record_fail "caller override inside an owned sibling permanently disqualifies that sibling" \
    "caller_status=$nested_caller_rc prune_status=$nested_prune_rc result=$(test -f "$nested_caller_result/Info.plist" && echo present || echo missing) caller_output='$(echo "$nested_caller_out" | tail -1)' prune_output='$(echo "$nested_prune_out" | tail -1)'"
fi

rm -rf "$RELEASE_RUN_DIR_A"
mkdir -p "$ARTIFACT_RUNS_A"
nested_enumeration_run="$ARTIFACT_RUNS_A/run-20260801T000000Z-9202"
nested_enumeration_result="$nested_enumeration_run/caller-enumerated-tests.json"
seed_successful_artifact "$nested_enumeration_run" "$RELEASE_UDID_A"
: >"$XCODEBUILD_LOG"
set +e
nested_enumeration_out="$(run_artifact_gate enumerate \
  MT_RELEASE_GATE_ENUMERATED_TESTS_JSON="$nested_enumeration_result" 2>&1)"
nested_enumeration_rc=$?
set -e
TZ=UTC touch -t 197001020733.19 "$nested_enumeration_run/.release-gate-success"
set +e
nested_enumeration_prune_out="$(run_artifact_gate full MT_RELEASE_GATE_TEST_NOW=200000 2>&1)"
nested_enumeration_prune_rc=$?
set -e
if [ "$nested_enumeration_rc" -eq 0 ] &&
   [ "$nested_enumeration_prune_rc" -eq 0 ] &&
   grep -q '"tests":\[\]' "$nested_enumeration_result" &&
   [ -f "$nested_enumeration_run/.release-gate-preserve" ]; then
  record_ok "enumeration override inside an owned sibling permanently disqualifies that sibling"
else
  record_fail "enumeration override inside an owned sibling permanently disqualifies that sibling" \
    "enumerate_status=$nested_enumeration_rc prune_status=$nested_enumeration_prune_rc result=$(test -f "$nested_enumeration_result" && echo present || echo missing) enumerate_output='$(echo "$nested_enumeration_out" | tail -1)' prune_output='$(echo "$nested_enumeration_prune_out" | tail -1)'"
fi

# shellcheck disable=SC2016 # Expanded when the fake cleanup commands run.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'last=""' \
  'for argument in "$@"; do last="$argument"; done' \
  'if [ -n "${MT_TEST_SWAP_CANDIDATE:-}" ] && [ "$last" = "$MT_TEST_SWAP_CANDIDATE" ] && [ -d "$MT_TEST_SWAP_REPLACEMENT" ]; then' \
  '  /bin/mv "$MT_TEST_SWAP_CANDIDATE" "$MT_TEST_SWAP_AWAY"' \
  '  /bin/mv "$MT_TEST_SWAP_REPLACEMENT" "$MT_TEST_SWAP_CANDIDATE"' \
  'fi' \
  'exec /bin/rm "$@"' >"$FAKE_BIN/rm"
# shellcheck disable=SC2016 # Expanded when the fake cleanup commands run.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ -n "${MT_TEST_SWAP_CANDIDATE:-}" ] && [ "${1:-}" = "$MT_TEST_SWAP_CANDIDATE" ] && [ -d "$MT_TEST_SWAP_REPLACEMENT" ]; then' \
  '  /bin/mv "$MT_TEST_SWAP_CANDIDATE" "$MT_TEST_SWAP_AWAY"' \
  '  /bin/mv "$MT_TEST_SWAP_REPLACEMENT" "$MT_TEST_SWAP_CANDIDATE"' \
  'fi' \
  'exec /bin/mv "$@"' >"$FAKE_BIN/mv"
chmod +x "$FAKE_BIN/rm" "$FAKE_BIN/mv"

rm -rf "$RELEASE_RUN_DIR_A"
mkdir -p "$ARTIFACT_RUNS_A"
swap_candidate="$ARTIFACT_RUNS_A/run-20260801T000000Z-9301"
swap_replacement="$ARTIFACT_RUNS_A/run-20260801T000000Z-9302"
swap_away="$TMP/swap-validated-success"
seed_successful_artifact "$swap_candidate" "$RELEASE_UDID_A"
mkdir -p "$swap_replacement"
write_artifact_identity "$swap_replacement/.release-gate-owned" "$RELEASE_UDID_A"
printf '%s\n' failure-evidence >"$swap_replacement/failure-sentinel"
TZ=UTC touch -t 197001020733.19 "$swap_candidate/.release-gate-success"
set +e
swap_prune_out="$(run_artifact_gate full \
  MT_RELEASE_GATE_TEST_NOW=200000 \
  MT_TEST_SWAP_CANDIDATE="$swap_candidate" \
  MT_TEST_SWAP_REPLACEMENT="$swap_replacement" \
  MT_TEST_SWAP_AWAY="$swap_away" 2>&1)"
swap_prune_rc=$?
set -e
if [ "$swap_prune_rc" -eq 0 ] &&
   [ -f "$swap_candidate/failure-sentinel" ] &&
   [ -d "$swap_away" ]; then
  record_ok "detects a candidate pathname replacement before deletion and restores failure evidence"
else
  record_fail "detects a candidate pathname replacement before deletion and restores failure evidence" \
    "status=$swap_prune_rc failure=$(test -f "$swap_candidate/failure-sentinel" && echo preserved || echo missing) validated=$(test -d "$swap_away" && echo moved || echo missing) output='$(echo "$swap_prune_out" | tail -1)'"
fi

# shellcheck disable=SC2016 # Expanded when the fake tee runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '/usr/bin/tee "$@"' \
  'tee_status=$?' \
  '[ "$tee_status" -eq 0 ] || exit "$tee_status"' \
  'exit "${MT_TEST_TEE_STATUS:-0}"' >"$FAKE_BIN/tee"
# shellcheck disable=SC2016 # Expanded when the fake formatter runs.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'cat' \
  'cat_status=$?' \
  '[ "$cat_status" -eq 0 ] || exit "$cat_status"' \
  'exit "${MT_TEST_XCBEAUTIFY_STATUS:-0}"' >"$FAKE_BIN/xcbeautify"
chmod +x "$FAKE_BIN/tee" "$FAKE_BIN/xcbeautify"

CI_STATUS_RUN="$TMP/ci-status-run"
rm -rf "$CI_STATUS_RUN"
: >"$XCODEBUILD_LOG"
set +e
ci_xcode_status_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$RELEASE_FIXTURE_REPO" \
    MT_TEST_PACKAGE_RESOLVED="$RELEASE_FIXTURE_RESOLVED" \
    MT_TEST_PACKAGE_RESOLVED_HEAD="$RELEASE_FIXTURE_HEAD_RESOLVED" \
    MT_TEST_REAL_GIT="$REAL_GIT" \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_TEST_XCRUN_LOG="$XCRUN_LOG" \
    MT_TEST_XCODEBUILD_BUILD_STATUS=73 \
    MT_TEST_TEE_STATUS=9 \
    GITHUB_ACTIONS=true \
    MT_RELEASE_GATE_SKIP_LOCK=1 \
    MT_RELEASE_GATE_CI_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_RUN_DIR="$CI_STATUS_RUN" \
    MT_RELEASE_GATE_DERIVED_DATA="$SAFE_TEST_ROOT/ci-status-derived-data" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
ci_xcode_status_rc=$?
set -e
if [ "$ci_xcode_status_rc" -eq 73 ] &&
   [ "$(wc -l <"$XCODEBUILD_LOG" | tr -d '[:space:]')" = "1" ] &&
   echo "$ci_xcode_status_out" | grep -Fq \
     'phase end: release build status=73'; then
  record_ok "CI release gate preserves Xcode status when log formatting also fails"
else
  record_fail "CI release gate preserves Xcode status when log formatting also fails" \
    "status=$ci_xcode_status_rc calls=$(wc -l <"$XCODEBUILD_LOG" | tr -d '[:space:]') output='$(echo "$ci_xcode_status_out" | tail -1)'"
fi

CI_RUN="$TMP/ci-release-run"
CI_RESULT="$CI_RUN/ci-result.xcresult"
mkdir -p "$CI_RESULT"
printf '%s\n' replace >"$CI_RESULT/sentinel"
: >"$XCODEBUILD_LOG"
set +e
ci_artifact_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_PACKAGE_RESOLVED_HEAD="$HERE/../ios/Package.resolved" \
    MT_TEST_REAL_GIT="$REAL_GIT" \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    GITHUB_ACTIONS=true \
    MT_RELEASE_GATE_SKIP_LOCK=1 \
    MT_RELEASE_GATE_CI_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_RUN_DIR="$CI_RUN" \
    MT_RELEASE_GATE_RESULT_BUNDLE="$CI_RESULT" \
    MT_RELEASE_GATE_DERIVED_DATA="$SAFE_TEST_ROOT/ci-derived-data" \
    MT_RELEASE_GATE_MODE=test \
    "$RELEASE_GATE" 2>&1
)"
ci_artifact_rc=$?
set -e
if [ "$ci_artifact_rc" -eq 0 ] &&
   [ -f "$CI_RESULT/Info.plist" ] &&
   [ ! -e "$CI_RESULT/sentinel" ] &&
   [ ! -e "$CI_RUN/.release-gate-owned" ] &&
   [ ! -e "$CI_RUN/.release-gate-success" ]; then
  record_ok "keeps CI explicit-artifact replacement outside local ownership markers"
else
  record_fail "keeps CI explicit-artifact replacement outside local ownership markers" \
    "status=$ci_artifact_rc sentinel=$(test -e "$CI_RESULT/sentinel" && echo present || echo removed) output='$(echo "$ci_artifact_out" | tail -1)'"
fi

echo
echo "sim-lock: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
