#!/usr/bin/env bash
# The only way to touch a Making Tracks gate simulator.
#
# Everything that boots, builds against, tests against, erases or deletes the
# selected simulator runs through here. Nothing else takes its lock, and
# nothing else calls simctl against its UDID.
#
# Per-simulator locks let different seats run concurrently. Stable global slot
# locks cap aggregate gate load. Every lock is opened once and flocked by file
# descriptor; lock paths are never removed or replaced (#497).

set -euo pipefail

DESTINATION="${MT_RELEASE_GATE_DESTINATION:-}"
LOCK_ROOT="/private/tmp"
FLOCK_BIN="/opt/homebrew/bin/flock"
PGREP_BIN="/usr/bin/pgrep"
PS_BIN="/bin/ps"
LOCK_WAIT_SECONDS="${MT_SIM_LOCK_WAIT:-1800}"
GATE_MAX_CONCURRENT="${MT_GATE_MAX_CONCURRENT:-2}"

die() { echo "sim-lock: $1" >&2; exit 1; }

# Test seams. Guarded so they cannot be reached in normal use.
if [ -n "${MT_SIM_LOCK_TEST_MODE:-}" ]; then
  [ "${MT_SIM_LOCK_TEST_MODE}" = "1" ] || die "MT_SIM_LOCK_TEST_MODE must be 1 or unset"
  LOCK_ROOT="${MT_SIM_LOCK_TEST_ROOT:-$LOCK_ROOT}"
  FLOCK_BIN="${MT_SIM_LOCK_TEST_FLOCK_BIN:-$FLOCK_BIN}"
  PGREP_BIN="${MT_SIM_LOCK_TEST_PGREP_BIN:-$PGREP_BIN}"
  PS_BIN="${MT_SIM_LOCK_TEST_PS_BIN:-$PS_BIN}"
  if [ -n "${MT_SIM_LOCK_TEST_UDID:-}" ]; then
    DESTINATION="platform=iOS Simulator,id=$MT_SIM_LOCK_TEST_UDID"
  fi
fi

[ -x "$FLOCK_BIN" ] || die "flock not executable at $FLOCK_BIN"
[ -x "$PGREP_BIN" ] || die "pgrep not executable at $PGREP_BIN"
[ -x "$PS_BIN" ] || die "ps not executable at $PS_BIN"

case "$LOCK_WAIT_SECONDS" in
  ""|*[!0-9]*) die "MT_SIM_LOCK_WAIT must be a non-negative integer" ;;
esac
case "$GATE_MAX_CONCURRENT" in
  ""|*[!0-9]*|0) die "MT_GATE_MAX_CONCURRENT must be a positive integer" ;;
esac

destination_udid() {
  local value

  [ -n "$DESTINATION" ] ||
    die "MT_RELEASE_GATE_DESTINATION is required; export this seat's destination from wp-infra-sim-concurrency"
  case "$DESTINATION" in
    *id=*) value="${DESTINATION#*id=}" ;;
    *) die "MT_RELEASE_GATE_DESTINATION must include id=<simulator-udid>" ;;
  esac
  value="${value%%,*}"
  case "$value" in
    ""|*[!A-Za-z0-9-]*)
      die "MT_RELEASE_GATE_DESTINATION contains an invalid simulator UDID"
      ;;
  esac
  printf '%s\n' "$value"
}

UDID="$(destination_udid)"
LOCK="$LOCK_ROOT/making-tracks-sim-$UDID.lock"

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
  # pgrep exit 1 is a valid empty result. Any other error means we do not know
  # whether the simulator is idle, so fail closed (#545).
  local matches
  local pgrep_rc=0
  local pid

  matches="$("$PGREP_BIN" -f -- "$UDID" 2>&1)" || pgrep_rc=$?
  case "$pgrep_rc" in
    0) ;;
    1) return 0 ;;
    *) die "cannot inspect simulator processes for $UDID (pgrep status $pgrep_rc): $matches" ;;
  esac

  while IFS= read -r pid; do
    [ "$pid" != "$$" ] || continue
    process_is_idle_launchd_sim "$pid" && continue
    echo "$pid"
  done <<<"$matches"
}

process_is_idle_launchd_sim() {
  local command
  command="$("$PS_BIN" -p "$1" -o command= 2>/dev/null || true)"
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

acquire_gate_slot() {
  local candidate_fd
  local elapsed
  local slot
  local slot_path
  local started="$SECONDS"
  local waiting_reported=0

  while true; do
    for ((slot = 1; slot <= GATE_MAX_CONCURRENT; slot++)); do
      slot_path="$LOCK_ROOT/making-tracks-gate-slot-$slot.lock"
      exec {candidate_fd}>>"$slot_path"
      if "$FLOCK_BIN" -n "$candidate_fd"; then
        return 0
      fi
      exec {candidate_fd}>&-
    done

    elapsed=$((SECONDS - started))
    if [ "$elapsed" -ge "$LOCK_WAIT_SECONDS" ]; then
      die "timed out after ${LOCK_WAIT_SECONDS}s waiting for one of $GATE_MAX_CONCURRENT global gate slots"
    fi
    if [ "$waiting_reported" -eq 0 ]; then
      echo "sim-lock: waiting for one of $GATE_MAX_CONCURRENT global gate slots (timeout ${LOCK_WAIT_SECONDS}s)" >&2
      waiting_reported=1
    fi
    sleep 0.1
  done
}

run_locked() {
  [ "$#" -gt 0 ] || die "no command given"

  # Re-entrancy for the same selected simulator. A nested command targeting a
  # different simulator must not inherit authority from the outer lock.
  if [ "${MT_SIM_LOCK:-}" = "1" ]; then
    [ "${MT_SIM_LOCK_UDID:-$UDID}" = "$UDID" ] ||
      die "nested invocation changed simulator from $MT_SIM_LOCK_UDID to $UDID"
    exec "$@"
  fi

  mkdir -p "$LOCK_ROOT"
  umask 077

  local sim_lock_fd
  exec {sim_lock_fd}>>"$LOCK"
  if ! "$FLOCK_BIN" -n "$sim_lock_fd"; then
    local holders
    holders="$(lock_holders)"
    if [ -n "$holders" ]; then
      echo "sim-lock: waiting for pid(s) $(echo "$holders" | tr '\n' ' ') on $UDID (timeout ${LOCK_WAIT_SECONDS}s)" >&2
    else
      echo "sim-lock: waiting for simulator $UDID lock (timeout ${LOCK_WAIT_SECONDS}s)" >&2
    fi
    "$FLOCK_BIN" -w "$LOCK_WAIT_SECONDS" "$sim_lock_fd" ||
      die "timed out after ${LOCK_WAIT_SECONDS}s waiting for simulator $UDID"
  fi

  acquire_gate_slot

  local rc=0
  MT_SIM_LOCK=1 MT_SIM_LOCK_UDID="$UDID" "$@" || rc=$?
  return "$rc"
}

usage() {
  cat <<'USAGE'
sim-lock.sh — the only way to touch a Making Tracks gate simulator

  sim-lock.sh <command> [args...]   run the command holding the lock
  sim-lock.sh --status              report HELD or FREE (exit 0 = FREE, 1 = HELD)
  sim-lock.sh --erase               erase the simulator, under the lock
  sim-lock.sh --shutdown            shut it down, under the lock
  sim-lock.sh --boot                boot it, under the lock

MT_RELEASE_GATE_DESTINATION must name the seat's simulator with id=<UDID>.
Same-simulator work serializes, while stable global slot locks cap aggregate
concurrency (MT_GATE_MAX_CONCURRENT, default 2).

Never read lock files by hand to decide whether a simulator is free. A file
records who holds its inode, not every process that may be using the simulator.
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
