#!/usr/bin/env bash
# The only way to touch the designated iOS simulator.
#
# Everything that boots, builds against, tests against, erases or deletes the
# designated simulator runs through here. Nothing else takes the lock, and
# nothing else calls simctl against this UDID.
#
# Why a single entry point: a lock file records who holds the lock, not who is
# using the simulator. A hand-check of the file reports FREE while a build is
# mid-flight without it, and acting on that reading destroys the run.

set -euo pipefail

UDID="C4A64D49-24A2-4429-B6E2-AD9A14142A99"
LOCK="/private/tmp/making-tracks-ios-tests.lock"
RETIRED_LOCK="/tmp/agent-ios-sim.lock"
FLOCK_BIN="/opt/homebrew/bin/flock"
LOCK_WAIT_SECONDS="${MT_SIM_LOCK_WAIT:-1800}"

die() { echo "sim-lock: $1" >&2; exit 1; }

# Test seams. Guarded so they cannot be reached in normal use.
if [ -n "${MT_SIM_LOCK_TEST_MODE:-}" ]; then
  [ "${MT_SIM_LOCK_TEST_MODE}" = "1" ] || die "MT_SIM_LOCK_TEST_MODE must be 1 or unset"
  LOCK="${MT_SIM_LOCK_TEST_LOCK:-$LOCK}"
  UDID="${MT_SIM_LOCK_TEST_UDID:-$UDID}"
  FLOCK_BIN="${MT_SIM_LOCK_TEST_FLOCK_BIN:-$FLOCK_BIN}"
  RETIRED_LOCK="${MT_SIM_LOCK_TEST_RETIRED_LOCK:-$RETIRED_LOCK}"
fi

[ -x "$FLOCK_BIN" ] || die "flock not executable at $FLOCK_BIN"

# --- the retired path must stay an alias --------------------------------------
#
# /private/tmp is cleared on reboot, so a symlink made by hand does not survive.
# Once it is gone the retired path becomes a separate regular file, the lock
# splits in two, and the lock leg of --status watches only the canonical side.
# That is the original regression returning silently. Assert it on every run
# rather than trusting that someone made it once.
#
# flock locks the resolved inode, so a symlinked alias shares the lock.

ensure_retired_alias() {
  if [ -L "$RETIRED_LOCK" ]; then
    [ "$(readlink "$RETIRED_LOCK")" = "$LOCK" ] && return 0
    ln -sfn "$LOCK" "$RETIRED_LOCK"
    return 0
  fi

  if [ -e "$RETIRED_LOCK" ]; then
    # A regular file. If anything holds it, a run is using the retired path now
    # and replacing it would split the lock underneath that run.
    if lsof -t -- "$RETIRED_LOCK" >/dev/null 2>&1; then
      die "$RETIRED_LOCK is a regular file and in use — a run holds the retired path. Wait for it, then re-run."
    fi
    rm -f "$RETIRED_LOCK"
  fi

  ln -sfn "$LOCK" "$RETIRED_LOCK"
}

# --- status -------------------------------------------------------------------
#
# Two signals, either sufficient to report HELD:
#
#   1. lsof on the lock. Catches a holder between phases — after a build, before
#      the tests — when no xcodebuild is running.
#   2. pgrep for a process naming this UDID. Catches work that never took the
#      lock, which is the case that caused the incident this script exists for.
#
# Reporting FREE requires both to be silent.

lock_holders() {
  lsof -t -- "$LOCK" 2>/dev/null || true
}

udid_users() {
  # Excludes this script so a --status call never reports itself.
  local pid
  { pgrep -f -- "$UDID" 2>/dev/null || true; } | while IFS= read -r pid; do
    [ "$pid" != "$$" ] || continue
    process_is_idle_launchd_sim "$pid" && continue
    echo "$pid"
  done
}

process_is_idle_launchd_sim() {
  local command
  command="$(ps -p "$1" -o command= 2>/dev/null || true)"
  case "$command" in
    launchd_sim\ *|*/launchd_sim\ *) return 0 ;;
    *) return 1 ;;
  esac
}

# Exit 0 when FREE, 1 when HELD, so callers branch on the code rather than parse.
status() {
  local by_lock by_proc
  by_lock="$(lock_holders)"
  by_proc="$(udid_users)"

  if [ -z "$by_lock" ] && [ -z "$by_proc" ]; then
    echo "FREE"
    return 0
  fi

  echo "HELD"
  [ -n "$by_lock" ] && echo "  lock held by pid(s): $(echo "$by_lock" | tr '\n' ' ')"
  [ -n "$by_proc" ] && echo "  simulator in use by pid(s): $(echo "$by_proc" | tr '\n' ' ')"
  if [ -n "$by_proc" ] && [ -z "$by_lock" ]; then
    echo "  NOTE: in use WITHOUT the lock — a bare lsof on the lock file reports FREE here"
  fi
  return 1
}

# --- destructive operations ---------------------------------------------------
#
# Taking the lock is not sufficient protection for erase. A process using the
# simulator without the lock does not block a lock acquisition, so
# flock-then-erase destroys it exactly as a hand-run erase did. Erase refuses on
# that signal and requires an explicit override.

destructive() {
  local action="$1"
  case "$action" in
    erase)
      local in_use
      in_use="$(udid_users)"
      if [ -n "$in_use" ] && [ "${MT_SIM_LOCK_FORCE_ERASE:-}" != "1" ]; then
        echo "sim-lock: refusing to erase — simulator in use by pid(s): $(echo "$in_use" | tr '\n' ' ')" >&2
        echo "sim-lock: those may not hold the lock, which is why taking it is not enough." >&2
        echo "sim-lock: if you are certain, re-run with MT_SIM_LOCK_FORCE_ERASE=1" >&2
        exit 1
      fi
      set -- xcrun simctl erase "$UDID"
      ;;
    shutdown) set -- xcrun simctl shutdown "$UDID" ;;
    boot)     set -- xcrun simctl bootstatus "$UDID" -b ;;
    *) die "unknown operation: $action" ;;
  esac
  run_locked "$@"
}

# --- run under the lock -------------------------------------------------------

run_locked() {
  [ "$#" -gt 0 ] || die "no command given"

  # Re-entrancy: a locked command that calls back into sim-lock.sh already holds
  # the lock. Re-flocking the same file from a child blocks on the parent and
  # deadlocks with no output, so run through instead.
  if [ "${MT_SIM_LOCK:-}" = "1" ]; then
    exec "$@"
  fi

  ensure_retired_alias

  local holders
  holders="$(lock_holders)"
  if [ -n "$holders" ]; then
    echo "sim-lock: waiting for pid(s) $(echo "$holders" | tr '\n' ' ') (timeout ${LOCK_WAIT_SECONDS}s)" >&2
  fi

  # -w bounds the wait so a stale holder cannot hang an agent indefinitely.
  local rc=0
  MT_SIM_LOCK=1 "$FLOCK_BIN" -w "$LOCK_WAIT_SECONDS" "$LOCK" "$@" || rc=$?
  if [ "$rc" -eq 1 ] && [ -n "$(lock_holders)" ]; then
    die "timed out after ${LOCK_WAIT_SECONDS}s waiting for the simulator lock"
  fi
  return "$rc"
}

usage() {
  cat <<'USAGE'
sim-lock.sh — the only way to touch the designated iOS simulator

  sim-lock.sh <command> [args...]   run the command holding the lock
  sim-lock.sh --status              report HELD or FREE (exit 0 = FREE, 1 = HELD)
  sim-lock.sh --erase               erase the simulator, under the lock
  sim-lock.sh --shutdown            shut it down, under the lock
  sim-lock.sh --boot                boot it, under the lock

Never read the lock file by hand to decide whether the simulator is free. The
file records who holds the lock, not who is using the simulator.
USAGE
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
