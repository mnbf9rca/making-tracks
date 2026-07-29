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
LOCK="$LOCK_ROOT/making-tracks-sim-TEST-UDID-0000-1111-2222-333344445555.lock"
FAKE_UDID="TEST-UDID-0000-1111-2222-333344445555"
FLOCK_BIN="/opt/homebrew/bin/flock"
RELEASE_FIXTURE_SEAT="sim-lock-test-$$"
RELEASE_LEGACY_RUN_DIR="/private/tmp/release-gate-$RELEASE_FIXTURE_SEAT"
RELEASE_UDID_A="TEST-DERIVED-AAAA"
RELEASE_UDID_B="TEST-DERIVED-BBBB"
RELEASE_RUN_DIR_A="/private/tmp/release-gate-$RELEASE_UDID_A"
RELEASE_RUN_DIR_B="/private/tmp/release-gate-$RELEASE_UDID_B"

pass=0; fail=0
cleanup() {
  rm -rf \
    "$TMP" \
    "$RELEASE_LEGACY_RUN_DIR" \
    "$RELEASE_RUN_DIR_A" \
    "$RELEASE_RUN_DIR_B"
}
trap cleanup EXIT

RETIRED="$TMP/retired.lock"

run_status() {
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
  "$SIM_LOCK" --status 2>&1
}

run_locked() {
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
  "$SIM_LOCK" "$@" 2>&1
}

run_erase() {
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
  "$SIM_LOCK" --erase 2>&1
}

run_gate_for() {
  local udid="$1"
  shift

  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$udid" \
  MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$udid" \
  MT_GATE_MAX_CONCURRENT="${MT_GATE_MAX_CONCURRENT:-2}" \
  MT_SIM_LOCK_WAIT=5 \
  "$SIM_LOCK" "$@"
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

record_ok() {
  echo "  ok    $1"
  pass=$((pass+1))
}

record_fail() {
  echo "  FAIL  $1"
  [ -z "${2:-}" ] || echo "        $2"
  fail=$((fail+1))
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

check() {
  local name="$1" expected="$2" actual="$3"
  if echo "$actual" | head -1 | grep -qx -- "$expected"; then
    echo "  ok    $name"
    pass=$((pass+1))
  else
    echo "  FAIL  $name"
    echo "        expected first line: $expected"
    echo "        got: $(echo "$actual" | head -1)"
    fail=$((fail+1))
  fi
}

mkdir -p "$LOCK_ROOT"
touch "$LOCK"

echo "sim-lock --status:"

# 1. Neither signal — the only case that may report FREE.
check "free when nothing holds it and nothing uses the sim" "FREE" "$(run_status)"

# 2. Lock held, no process naming the UDID. This is the between-phases case:
#    a gate that has finished building and has not started testing.
"$FLOCK_BIN" -x "$LOCK" -c 'sleep 4' &
lock_pid=$!
sleep 0.5
check "held when the lock is taken but no process names the UDID" "HELD" "$(run_status)"
wait "$lock_pid" 2>/dev/null

# 3. Process using the simulator, lock NOT taken. This is the incident case:
#    a hand-check of the lock file reports FREE while work is in flight.
# Rename the process's argv so pgrep -f matches the UDID, the way a real
# xcodebuild destination argument would.
(exec -a "xcodebuild -destination platform=iOS Simulator,id=$FAKE_UDID" sleep 4) &
fake_pid=$!
sleep 0.5
check "held when the sim is in use WITHOUT the lock" "HELD" "$(run_status)"
kill "$fake_pid" 2>/dev/null
wait 2>/dev/null

# 4. CoreSimulator's idle launchd_sim process names the UDID but is not work.
#    Treating it as a holder wedges the shared simulator after every boot.
(exec -a "launchd_sim $FAKE_UDID" sleep 4) &
launchd_pid=$!
sleep 0.5
check "free when only idle launchd_sim names the UDID" "FREE" "$(run_status)"
kill "$launchd_pid" 2>/dev/null
wait 2>/dev/null

# 5. The warning fires on the dangerous case specifically.
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

# 6. Back to free once everything exits — proves the signals clear rather than
#    latching, so a stale HELD cannot wedge the fleet.
sleep 0.3
check "free again after holders exit" "FREE" "$(run_status)"

# 7. Process enumeration failure is not evidence that the simulator is idle.
#    If this branch returns FREE, destructive work can race an unknown holder.
PGREP_ERROR="$TMP/pgrep-error"
printf '%s\n' '#!/usr/bin/env bash' 'exit 2' >"$PGREP_ERROR"
chmod +x "$PGREP_ERROR"
set +e
pgrep_error_out="$(
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_ROOT="$LOCK_ROOT" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
  MT_SIM_LOCK_TEST_PGREP_BIN="$PGREP_ERROR" \
  "$SIM_LOCK" --status 2>&1
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

echo
echo "sim-lock retired-path retirement:"

# 8. The per-seat design has no canonical target for the retired global alias.
#    Touching or replacing it can split an inode underneath a legacy holder,
#    which is #497's failure shape. New invocations leave it completely alone.
rm -f "$RETIRED"
printf '%s\n' "legacy-sentinel" >"$RETIRED"
retired_inode_before="$(stat -f %i "$RETIRED")"
run_gate_for "TEST-RETIRED-UNTOUCHED" true >/dev/null 2>&1 || true
retired_inode_after="$(stat -f %i "$RETIRED")"
if [ ! -L "$RETIRED" ] &&
   [ "$retired_inode_before" = "$retired_inode_after" ] &&
   [ "$(cat "$RETIRED")" = "legacy-sentinel" ]; then
  record_ok "never deletes or replaces the retired global lock path"
else
  record_fail "never deletes or replaces the retired global lock path" \
    "the retired path changed during a new per-simulator invocation"
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
       MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$FAKE_UDID" \
       "$SIM_LOCK" "$SIM_LOCK" echo nested-ok 2>&1)" || true
if echo "$out" | grep -q "nested-ok"; then
  echo "  ok    nested invocation runs through instead of deadlocking"; pass=$((pass+1))
else
  echo "  FAIL  nested invocation runs through instead of deadlocking"
  echo "        got: $out"; fail=$((fail+1))
fi

echo
echo "sim-lock per-simulator concurrency:"

SAME_A="$TMP/same-a"
SAME_B="$TMP/same-b"
start_holder "TEST-SAME-SIM" "$SAME_A" >"$SAME_A.log" 2>&1 &
same_a_pid=$!
if wait_for_path "$SAME_A.started"; then
  run_gate_for "TEST-SAME-SIM" touch "$SAME_B.started" >"$SAME_B.log" 2>&1 &
  same_b_pid=$!
  sleep 0.3
  if [ ! -e "$SAME_B.started" ]; then
    record_ok "serializes two commands targeting the same simulator"
  else
    record_fail "serializes two commands targeting the same simulator" \
      "second command started while the first still held the simulator"
  fi
  touch "$SAME_A.release"
  wait "$same_a_pid" 2>/dev/null
  wait "$same_b_pid" 2>/dev/null
else
  record_fail "serializes two commands targeting the same simulator" \
    "first holder did not start"
  touch "$SAME_A.release"
  wait "$same_a_pid" 2>/dev/null
fi

CROSS_A="$TMP/cross-a"
CROSS_B="$TMP/cross-b"
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
MT_GATE_MAX_CONCURRENT=2 start_holder "TEST-CAP-SIM-A" "$CAP_A" >"$CAP_A.log" 2>&1 &
cap_a_pid=$!
MT_GATE_MAX_CONCURRENT=2 start_holder "TEST-CAP-SIM-B" "$CAP_B" >"$CAP_B.log" 2>&1 &
cap_b_pid=$!
cap_setup_ok=1
wait_for_path "$CAP_A.started" || cap_setup_ok=0
wait_for_path "$CAP_B.started" || cap_setup_ok=0
if [ "$cap_setup_ok" -eq 1 ]; then
  MT_GATE_MAX_CONCURRENT=2 start_holder "TEST-CAP-SIM-C" "$CAP_C" >"$CAP_C.log" 2>&1 &
  cap_c_pid=$!
  sleep 0.3
  if [ ! -e "$CAP_C.started" ]; then
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

echo
echo "sim-lock stable lock inode:"

INODE_UDID="TEST-INODE-SIM"
INODE_LOCK="$LOCK_ROOT/making-tracks-sim-$INODE_UDID.lock"
INODE_HOLDER="$TMP/inode-holder"
mkdir -p "$LOCK_ROOT"
touch "$INODE_LOCK"
inode_before="$(stat -f %i "$INODE_LOCK")"
start_holder "$INODE_UDID" "$INODE_HOLDER" >"$INODE_HOLDER.log" 2>&1 &
inode_pid=$!
if wait_for_path "$INODE_HOLDER.started" && [ -f "$INODE_LOCK" ]; then
  inode_during="$(stat -f %i "$INODE_LOCK")"
  touch "$INODE_HOLDER.release"
  wait "$inode_pid" 2>/dev/null
  inode_after="$(stat -f %i "$INODE_LOCK")"
  if [ "$inode_before" = "$inode_during" ] && [ "$inode_before" = "$inode_after" ]; then
    record_ok "keeps the per-simulator lock file on one stable inode"
  else
    record_fail "keeps the per-simulator lock file on one stable inode" \
      "inode changed: before=$inode_before during=$inode_during after=$inode_after"
  fi
else
  record_fail "keeps the per-simulator lock file on one stable inode" \
    "holder did not use the expected per-simulator lock path"
  touch "$INODE_HOLDER.release"
  wait "$inode_pid" 2>/dev/null
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

missing_destination_out="$(
  env -u MT_RELEASE_GATE_DESTINATION \
    PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_RELEASE_GATE_MODE=build \
    AM_ME="$RELEASE_FIXTURE_SEAT" \
    "$RELEASE_GATE" 2>&1
)" || true
if echo "$missing_destination_out" | grep -q "wp-infra-sim-concurrency"; then
  record_ok "refuses an unset destination with the simulator-row message"
else
  record_fail "refuses an unset destination with the simulator-row message" \
    "got: $(echo "$missing_destination_out" | head -1)"
fi

run_release_fixture() {
  local udid="$1"
  : >"$XCODEBUILD_LOG"
  PATH="$FAKE_BIN:$PATH" \
  MT_TEST_REPO_ROOT="$HERE/.." \
  MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
  MT_SIM_LOCK=1 \
  MT_RELEASE_GATE_MODE=build \
  MT_RELEASE_GATE_DESTINATION="platform=iOS Simulator,id=$udid" \
  AM_ME="$RELEASE_FIXTURE_SEAT" \
  "$RELEASE_GATE" >/dev/null 2>&1
  grep -o -- '-derivedDataPath [^ ]*' "$XCODEBUILD_LOG" | head -1
}

derived_a="$(run_release_fixture "$RELEASE_UDID_A")"
derived_b="$(run_release_fixture "$RELEASE_UDID_B")"
if [ -n "$derived_a" ] && [ -n "$derived_b" ] && [ "$derived_a" != "$derived_b" ]; then
  record_ok "derives distinct default DerivedData paths from destination UDIDs"
else
  record_fail "derives distinct default DerivedData paths from destination UDIDs" \
    "first='$derived_a' second='$derived_b'"
fi

echo
echo "sim-lock: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
