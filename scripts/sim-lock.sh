#!/usr/bin/env bash
# The only way to touch the designated iOS simulator.
#
# Everything that boots, builds against, tests against, erases or deletes the
# designated simulator runs through here. Nothing else takes the lock, and
# nothing else calls simctl against this UDID.
#
#   sim-lock.sh <command> [args...]   run the command holding the lock
#   sim-lock.sh --status              report HELD or FREE, and by what
#   sim-lock.sh --erase               erase the simulator, under the lock
#   sim-lock.sh --shutdown            shut it down, under the lock
#   sim-lock.sh --boot                boot it, under the lock
#
# Why a single entry point: a lock file tells you only who holds the lock, not
# who is using the simulator. A hand-check of the file reports FREE while a
# build is mid-flight without it, and acting on that reading destroys the run.
# --status therefore checks two independent signals and reports HELD if either
# fires. Both can be wrong alone; they are not wrong together in the same way.

set -euo pipefail

UDID="C4A64D49-24A2-4429-B6E2-AD9A14142A99"
LOCK="/private/tmp/making-tracks-ios-tests.lock"
FLOCK_BIN="/opt/homebrew/bin/flock"

# Set for the duration of a locked command. Consumers refuse to run without it,
# which turns "forgot the lock" from an accident into a deliberate act. It is a
# guard against mistakes, not against someone who sets the variable by hand.
export_marker="MT_SIM_LOCK"

die() { echo "sim-lock: $1" >&2; exit 1; }

# Test seams. Guarded so they cannot be reached in normal use.
if [ -n "${MT_SIM_LOCK_TEST_MODE:-}" ]; then
  [ "${MT_SIM_LOCK_TEST_MODE}" = "1" ] || die "MT_SIM_LOCK_TEST_MODE must be 1 or unset"
  LOCK="${MT_SIM_LOCK_TEST_LOCK:-$LOCK}"
  UDID="${MT_SIM_LOCK_TEST_UDID:-$UDID}"
  FLOCK_BIN="${MT_SIM_LOCK_TEST_FLOCK_BIN:-$FLOCK_BIN}"
fi

[ -x "$FLOCK_BIN" ] || die "flock not executable at $FLOCK_BIN"

# --- status -----------------------------------------------------------------
#
# Two signals, either sufficient to report HELD:
#
#   1. lsof on the lock file. Catches a holder that is between phases — after a
#      build, before the tests — when no xcodebuild is running.
#   2. pgrep for a process naming this UDID. Catches work that never took the
#      lock, which is the case that caused the incident this script exists for.
#
# Reporting FREE requires both to be silent.

lock_holders() {
  # -t: pids only. Returns non-zero when nothing holds it; that is not an error.
  lsof -t -- "$LOCK" 2>/dev/null || true
}

udid_users() {
  # Any process whose argv names the designated simulator. Excludes this script
  # and its own pgrep so a --status call never reports itself.
  pgrep -f -- "$UDID" 2>/dev/null | grep -v -x -- "$$" || true
}

status() {
  local by_lock by_proc
  by_lock="$(lock_holders)"
  by_proc="$(udid_users)"

  if [ -n "$by_lock" ] || [ -n "$by_proc" ]; then
    echo "HELD"
    [ -n "$by_lock" ] && echo "  lock held by pid(s): $(echo "$by_lock" | tr '\n' ' ')"
    [ -n "$by_proc" ] && echo "  simulator in use by pid(s): $(echo "$by_proc" | tr '\n' ' ')"
    [ -n "$by_proc" ] && [ -z "$by_lock" ] &&
      echo "  NOTE: simulator in use WITHOUT the lock — do not act on a FREE reading of the lock file alone"
    return 0
  fi

  echo "FREE"
  return 0
}

# --- destructive operations -------------------------------------------------
#
# These exist so that erase/delete/boot cannot be done by hand. The incident
# this script exists for was a hand-run erase against a simulator that a gate
# was using.

destructive() {
  local action="$1"
  case "$action" in
    erase)    set -- xcrun simctl erase "$UDID" ;;
    shutdown) set -- xcrun simctl shutdown "$UDID" ;;
    boot)     set -- xcrun simctl bootstatus "$UDID" -b ;;
    *) die "unknown operation: $action" ;;
  esac
  run_locked "$@"
}

# --- run under the lock -----------------------------------------------------

run_locked() {
  [ "$#" -gt 0 ] || die "no command given"
  MT_SIM_LOCK=1 "$FLOCK_BIN" "$LOCK" "$@"
}

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  --status)   shift; status ;;
  --erase)    shift; destructive erase ;;
  --shutdown) shift; destructive shutdown ;;
  --boot)     shift; destructive boot ;;
  -h|--help)  usage ;;
  "")         usage; exit 1 ;;
  --*)        die "unknown flag: $1" ;;
  *)          run_locked "$@" ;;
esac
