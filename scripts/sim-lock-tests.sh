#!/usr/bin/env bash
# Tests for sim-lock.sh --status truthfulness.
#
# The point of --status is that either signal alone lies. These prove it
# reports HELD when only one fires, and FREE only when neither does. Neuter
# either branch of the status check and one of these goes red.
#
#   ./scripts/sim-lock-tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SIM_LOCK="$HERE/sim-lock.sh"
TMP="$(mktemp -d)"
LOCK="$TMP/test.lock"
FAKE_UDID="TEST-UDID-0000-1111-2222-333344445555"
FLOCK_BIN="/opt/homebrew/bin/flock"

pass=0; fail=0
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

RETIRED="$TMP/retired.lock"

run_status() {
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_LOCK="$LOCK" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_RETIRED_LOCK="$RETIRED" \
  "$SIM_LOCK" --status 2>&1
}

run_locked() {
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_LOCK="$LOCK" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_RETIRED_LOCK="$RETIRED" \
  "$SIM_LOCK" "$@" 2>&1
}

run_erase() {
  MT_SIM_LOCK_TEST_MODE=1 \
  MT_SIM_LOCK_TEST_LOCK="$LOCK" \
  MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" \
  MT_SIM_LOCK_TEST_RETIRED_LOCK="$RETIRED" \
  "$SIM_LOCK" --erase 2>&1
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

# 4. The warning fires on the dangerous case specifically.
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

# 5. Back to free once everything exits — proves the signals clear rather than
#    latching, so a stale HELD cannot wedge the fleet.
sleep 0.3
check "free again after holders exit" "FREE" "$(run_status)"

echo
echo "sim-lock retired-path alias:"

# 6. The alias is recreated when missing. /private/tmp clears on reboot, so a
#    symlink made once does not survive; if it is not asserted the lock splits
#    and the whole --status lock leg watches the wrong file.
rm -f "$RETIRED"
run_locked true >/dev/null 2>&1 || true
if [ -L "$RETIRED" ] && [ "$(readlink "$RETIRED")" = "$LOCK" ]; then
  echo "  ok    recreates the retired alias when absent"; pass=$((pass+1))
else
  echo "  FAIL  recreates the retired alias when absent"; fail=$((fail+1))
fi

# 7. An idle regular file at the retired path is replaced, not tolerated.
rm -f "$RETIRED"; touch "$RETIRED"
run_locked true >/dev/null 2>&1 || true
if [ -L "$RETIRED" ]; then
  echo "  ok    replaces an idle regular file at the retired path"; pass=$((pass+1))
else
  echo "  FAIL  replaces an idle regular file at the retired path"; fail=$((fail+1))
fi

# 8. A BUSY regular file is refused rather than replaced — replacing it would
#    split the lock underneath the run that is holding it.
rm -f "$RETIRED"; touch "$RETIRED"
"$FLOCK_BIN" -x "$RETIRED" -c 'sleep 3' &
busy_pid=$!
sleep 0.5
out="$(run_locked true 2>&1 || true)"
if echo "$out" | grep -q "regular file and in use"; then
  echo "  ok    refuses to replace a busy regular file at the retired path"; pass=$((pass+1))
else
  echo "  FAIL  refuses to replace a busy regular file at the retired path"; fail=$((fail+1))
fi
kill "$busy_pid" 2>/dev/null; wait 2>/dev/null
rm -f "$RETIRED"

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
out="$(MT_SIM_LOCK_TEST_MODE=1 MT_SIM_LOCK_TEST_LOCK="$LOCK" \
       MT_SIM_LOCK_TEST_UDID="$FAKE_UDID" MT_SIM_LOCK_TEST_RETIRED_LOCK="$RETIRED" \
       "$SIM_LOCK" "$SIM_LOCK" echo nested-ok 2>&1)" || true
if echo "$out" | grep -q "nested-ok"; then
  echo "  ok    nested invocation runs through instead of deadlocking"; pass=$((pass+1))
else
  echo "  FAIL  nested invocation runs through instead of deadlocking"
  echo "        got: $out"; fail=$((fail+1))
fi

echo
echo "sim-lock: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
