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
#
# File descriptors 7, 8 and 9 deliberately remain open across the wrapped
# command and its descendants. That inheritance keeps all three locks held
# across shell/xcodebuild process transitions; closing them in the child would
# reintroduce the split-ownership incident this wrapper prevents.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEAT_LEDGER="$SCRIPT_DIR/../docs/ios-gate-ledger.md"
SEAT=""
DESTINATION=""
UDID=""
LOCK=""
LOCK_ROOT="/private/tmp"
FLOCK_BIN="/opt/homebrew/bin/flock"
LSOF_BIN="/usr/sbin/lsof"
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
  LSOF_BIN="${MT_SIM_LOCK_TEST_LSOF_BIN:-$LSOF_BIN}"
  PGREP_BIN="${MT_SIM_LOCK_TEST_PGREP_BIN:-$PGREP_BIN}"
  PS_BIN="${MT_SIM_LOCK_TEST_PS_BIN:-$PS_BIN}"
  SEAT_LEDGER="${MT_SIM_LOCK_TEST_LEDGER:-$SEAT_LEDGER}"
fi

[ -x "$FLOCK_BIN" ] || die "flock not executable at $FLOCK_BIN"
[ -x "$LSOF_BIN" ] || die "lsof not executable at $LSOF_BIN"
[ -x "$PGREP_BIN" ] || die "pgrep not executable at $PGREP_BIN"
[ -x "$PS_BIN" ] || die "ps not executable at $PS_BIN"
umask 077

case "$LOCK_WAIT_SECONDS" in
  0|[1-9]|[1-9][0-9]*) ;;
  *) die "MT_SIM_LOCK_WAIT must be a canonical non-negative integer" ;;
esac
case "$GATE_MAX_CONCURRENT" in
  1|2) ;;
  [3-9]|[1-9][0-9]*)
    die "MT_GATE_MAX_CONCURRENT cannot exceed the host ceiling of 2"
    ;;
  *) die "MT_GATE_MAX_CONCURRENT must be 1 or 2" ;;
esac

parse_destination_udid() {
  local fields
  local remainder
  local value
  local value_and_remainder

  fields=",$1,"
  case "$fields" in
    *,id=*) value_and_remainder="${fields#*,id=}" ;;
    *) die "simulator destination must include id=<simulator-udid>" ;;
  esac
  value="${value_and_remainder%%,*}"
  remainder="${value_and_remainder#"$value"}"
  case "$remainder" in
    *,id=*) die "simulator destination must contain exactly one id=<simulator-udid>" ;;
  esac
  case "$value" in
    ""|*[!A-Za-z0-9-]*)
      die "simulator destination contains an invalid simulator UDID"
      ;;
  esac
  if ! { [ -n "${MT_SIM_LOCK_TEST_MODE:-}" ] &&
         [ "${MT_SIM_LOCK_TEST_UDID:-}" = "$value" ]; } &&
     ! is_core_simulator_uuid "$value"; then
    die "simulator destination id must be a valid CoreSimulator UUID"
  fi
  printf '%s\n' "$value"
}

is_core_simulator_uuid() {
  [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

resolve_seat_destination() {
  local count
  local destination
  local result

  [ -r "$SEAT_LEDGER" ] || die "cannot read host gate seat ledger: $SEAT_LEDGER"
  result="$(
    awk -F '|' -v wanted="$1" '
      function trim(value) {
        gsub(/^[[:space:]]+/, "", value)
        gsub(/[[:space:]]+$/, "", value)
        return value
      }
      function unquote(value) {
        if (substr(value, 1, 1) == "`" &&
            substr(value, length(value), 1) == "`") {
          return substr(value, 2, length(value) - 2)
        }
        return value
      }
      {
        sub(/\r$/, "", $0)
        if ($0 == "## Host Gate Seats") {
          section_count++
          in_section = 1
          next
        }
        if ($0 ~ /^## /) {
          in_section = 0
          in_rows = 0
          next
        }
        if (!in_section) {
          next
        }
        if (!header_seen) {
          if (NF == 5 && trim($2) == "Seat" &&
              trim($3) == "Simulator" && trim($4) == "Destination") {
            header_seen = 1
            expect_separator = 1
          }
          next
        }
        if (expect_separator) {
          if ($0 ~ /^[[:space:]]*$/) {
            next
          }
          if (NF == 5 && trim($2) == "---" &&
              trim($3) == "---" && trim($4) == "---") {
            expect_separator = 0
            in_rows = 1
            next
          }
          malformed = 1
          expect_separator = 0
          next
        }
        if (!in_rows) {
          next
        }
        if ($0 !~ /^[[:space:]]*\|/) {
          in_rows = 0
          next
        }
        if (NF != 5) {
          malformed = 1
          next
        }

        seat = unquote(trim($2))
        simulator = unquote(trim($3))
        row_destination = unquote(trim($4))
        if (seat == "" || simulator == "" || row_destination == "") {
          malformed = 1
          next
        }
        row_count++
        if (seat == wanted) {
          count++
          destination = row_destination
        }
      }
      END {
        if (section_count != 1 || header_seen != 1 ||
            expect_separator || row_count == 0 || malformed) {
          exit 2
        }
        printf "%d\t%s\n", count, destination
      }
    ' "$SEAT_LEDGER"
  )" || die "malformed Host Gate Seats table in $SEAT_LEDGER"

  count="${result%%$'\t'*}"
  destination="${result#*$'\t'}"
  [ "$count" = "1" ] ||
    die "seat $1 must appear exactly once in host gate seat ledger (found $count)"
  [ -n "$destination" ] || die "seat $1 has an empty destination in host gate seat ledger"
  printf '%s\n' "$destination"
}

select_seat() {
  DESTINATION="$(resolve_seat_destination "$SEAT")"
  if [ -n "${MT_SIM_LOCK_TEST_MODE:-}" ] && [ -n "${MT_SIM_LOCK_TEST_UDID:-}" ]; then
    DESTINATION="platform=iOS Simulator,id=$MT_SIM_LOCK_TEST_UDID"
  fi
  UDID="$(parse_destination_udid "$DESTINATION")"
  LOCK="$LOCK_ROOT/making-tracks-sim-$UDID.lock"
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
  local diagnostics=""
  local diagnostics_file
  local lsof_rc=0
  local matches
  local mode="${1:-strict}"

  [ -e "$LOCK" ] || return 0
  diagnostics_file="$(mktemp "$LOCK_ROOT/.making-tracks-lsof.XXXXXX")" || {
    [ "$mode" = "advisory" ] && return 0
    die "cannot create temporary output for simulator lock inspection"
  }
  matches="$("$LSOF_BIN" -t -- "$LOCK" 2>"$diagnostics_file")" || lsof_rc=$?
  diagnostics="$(<"$diagnostics_file")"
  rm -f "$diagnostics_file"
  case "$lsof_rc" in
    0)
      if [ -n "$diagnostics" ] && [ "$mode" != "advisory" ]; then
        die "cannot inspect simulator lock $LOCK (lsof status 0 with diagnostics): $diagnostics"
      fi
      printf '%s\n' "$matches"
      ;;
    1)
      if [ -n "$diagnostics" ] && [ "$mode" != "advisory" ]; then
        die "cannot inspect simulator lock $LOCK (lsof status 1): $diagnostics"
      fi
      return 0
      ;;
    *)
      [ "$mode" = "advisory" ] && return 0
      die "cannot inspect simulator lock $LOCK (lsof status $lsof_rc): $diagnostics"
      ;;
  esac
}

udid_users() {
  # pgrep exit 1 is a valid empty result. Any other error means we do not know
  # whether the simulator is idle, so fail closed (#545).
  local diagnostics=""
  local diagnostics_file
  local matches
  local pgrep_rc=0
  local pid

  diagnostics_file="$(mktemp "$LOCK_ROOT/.making-tracks-pgrep.XXXXXX")" ||
    die "cannot create temporary output for simulator process inspection"
  matches="$("$PGREP_BIN" -f -- "$UDID" 2>"$diagnostics_file")" || pgrep_rc=$?
  diagnostics="$(<"$diagnostics_file")"
  rm -f "$diagnostics_file"
  case "$pgrep_rc" in
    0)
      [ -z "$diagnostics" ] ||
        die "cannot inspect simulator processes for $UDID (pgrep status 0 with diagnostics): $diagnostics"
      ;;
    1)
      [ -z "$diagnostics" ] ||
        die "cannot inspect simulator processes for $UDID (pgrep status 1): $diagnostics"
      return 0
      ;;
    *) die "cannot inspect simulator processes for $UDID (pgrep status $pgrep_rc): $diagnostics" ;;
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
    shutdown) set -- xcrun simctl shutdown ;;
    boot)     set -- xcrun simctl bootstatus -b ;;
    *) die "unknown operation: $action" ;;
  esac
  run_locked "$@"
}

# --- run under the lock -------------------------------------------------------

acquire_gate_policy() {
  local flock_rc=0
  local policy_path="$LOCK_ROOT/making-tracks-gate-policy.lock"
  local policy_kind
  local policy_option

  exec 7>>"$policy_path"
  if [ "$GATE_MAX_CONCURRENT" -eq 1 ]; then
    policy_kind="fleet-exclusive"
    policy_option="-x"
  else
    policy_kind="shared"
    policy_option="-s"
  fi

  "$FLOCK_BIN" "$policy_option" -n 7 || flock_rc=$?
  case "$flock_rc" in
    0) return 0 ;;
    1) ;;
    *) die "could not acquire $policy_kind gate admission (flock status $flock_rc)" ;;
  esac

  echo "sim-lock: waiting for $policy_kind gate admission (timeout ${LOCK_WAIT_SECONDS}s)" >&2
  flock_rc=0
  "$FLOCK_BIN" "$policy_option" -w "$LOCK_WAIT_SECONDS" 7 || flock_rc=$?
  case "$flock_rc" in
    0) ;;
    1) die "timed out after ${LOCK_WAIT_SECONDS}s waiting for $policy_kind gate admission" ;;
    *) die "could not acquire $policy_kind gate admission (flock status $flock_rc)" ;;
  esac
}

acquire_gate_slot() {
  local elapsed
  local flock_rc
  local slot
  local slot_path
  local started="$SECONDS"
  local waiting_reported=0

  while true; do
    for ((slot = 1; slot <= GATE_MAX_CONCURRENT; slot++)); do
      slot_path="$LOCK_ROOT/making-tracks-gate-slot-$slot.lock"
      exec 9>>"$slot_path"
      flock_rc=0
      "$FLOCK_BIN" -n 9 || flock_rc=$?
      case "$flock_rc" in
        0) return 0 ;;
        1) exec 9>&- ;;
        *) die "could not inspect or acquire global gate slot $slot (flock status $flock_rc)" ;;
      esac
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

validate_command_destination() {
  local command_destination
  local command_udid

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -destination)
        shift
        [ "$#" -gt 0 ] || die "wrapped command has -destination without a value"
        command_destination="$1"
        command_udid="$(parse_destination_udid "$command_destination")"
        [ "$command_udid" = "$UDID" ] ||
          die "wrapped command targets simulator $command_udid while the lock is for $UDID"
        [ "$command_destination" = "$DESTINATION" ] ||
          die "wrapped command destination does not exactly match seat $SEAT destination"
        ;;
      -destination=*)
        command_destination="${1#-destination=}"
        command_udid="$(parse_destination_udid "$command_destination")"
        [ "$command_udid" = "$UDID" ] ||
          die "wrapped command targets simulator $command_udid while the lock is for $UDID"
        [ "$command_destination" = "$DESTINATION" ] ||
          die "wrapped command destination does not exactly match seat $SEAT destination"
        ;;
    esac
    shift
  done
}

command_has_destination() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -destination|-destination=*) return 0 ;;
    esac
    shift
  done
  return 1
}

run_locked() {
  local simctl_verb

  [ "$#" -gt 0 ] || die "no command given"
  if [ "$1" = "xcodebuild" ] && ! command_has_destination "$@"; then
    set -- "$@" -destination "$DESTINATION"
  fi
  if [ "$#" -ge 3 ] && [ "$1" = "xcrun" ] && [ "$2" = "simctl" ]; then
    simctl_verb="$3"
    case "$simctl_verb" in
      bootstatus|shutdown|launch|terminate|install|uninstall|io|get_app_container|spawn)
        shift 3
        if [ "$#" -gt 0 ]; then
          case "$1" in
            all|booted)
              die "omit the simulator target after simctl $simctl_verb; seat $SEAT supplies it"
              ;;
          esac
          if is_core_simulator_uuid "$1"; then
            die "omit the simulator target after simctl $simctl_verb; seat $SEAT supplies it"
          fi
        fi
        set -- xcrun simctl "$simctl_verb" "$UDID" "$@"
        ;;
    esac
  fi
  validate_command_destination "$@"

  # Re-entrancy for the same selected simulator. A nested command targeting a
  # different simulator must not inherit authority from the outer lock.
  if [ "${MT_SIM_LOCK:-}" = "1" ]; then
    [ -n "${MT_SIM_LOCK_UDID:-}" ] ||
      die "nested invocation is missing simulator identity MT_SIM_LOCK_UDID"
    [ "$MT_SIM_LOCK_UDID" = "$UDID" ] ||
      die "nested invocation changed simulator from $MT_SIM_LOCK_UDID to $UDID"
    exec "$@"
  fi

  mkdir -p "$LOCK_ROOT"
  umask 077

  local flock_rc=0
  exec 8>>"$LOCK"
  "$FLOCK_BIN" -n 8 || flock_rc=$?
  if [ "$flock_rc" -ne 0 ]; then
    [ "$flock_rc" -eq 1 ] ||
      die "could not inspect or acquire simulator $UDID lock (flock status $flock_rc)"
    local holders
    holders="$(lock_holders advisory)"
    if [ -n "$holders" ]; then
      echo "sim-lock: waiting for pid(s) $(echo "$holders" | tr '\n' ' ') on $UDID (timeout ${LOCK_WAIT_SECONDS}s)" >&2
    else
      echo "sim-lock: waiting for simulator $UDID lock (timeout ${LOCK_WAIT_SECONDS}s)" >&2
    fi
    flock_rc=0
    "$FLOCK_BIN" -w "$LOCK_WAIT_SECONDS" 8 || flock_rc=$?
    case "$flock_rc" in
      0) ;;
      1) die "timed out after ${LOCK_WAIT_SECONDS}s waiting for simulator $UDID" ;;
      *) die "could not acquire simulator $UDID lock (flock status $flock_rc)" ;;
    esac
  fi

  acquire_gate_policy
  acquire_gate_slot

  local rc=0
  MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$UDID" \
    MT_SIM_LOCK_DESTINATION="$DESTINATION" \
    "$@" || rc=$?
  return "$rc"
}

usage() {
  cat <<'USAGE'
sim-lock.sh — the only way to touch a Making Tracks gate simulator

  sim-lock.sh --seat <seat> <command> [args...]   run holding the seat lock
  sim-lock.sh --seat <seat> --status              report HELD or FREE
  sim-lock.sh --seat <seat> --erase               erase under the lock
  sim-lock.sh --seat <seat> --shutdown            shut down under the lock
  sim-lock.sh --seat <seat> --boot                boot under the lock

<seat> is one of codex1, codex2, codex3 or codex4. Its destination is resolved
from docs/ios-gate-ledger.md. Same-simulator work serializes, while stable
global slot locks cap aggregate concurrency (MT_GATE_MAX_CONCURRENT, default 2).

Never read lock files by hand to decide whether a simulator is free. A file
records who holds its inode, not every process that may be using the simulator.
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

[ "${1:-}" = "--seat" ] || die "--seat <seat> is required before the command"
[ "$#" -ge 2 ] || die "--seat requires a seat name"
SEAT="$2"
case "$SEAT" in
  codex1|codex2|codex3|codex4) ;;
  *) die "unknown seat: $SEAT (expected codex1, codex2, codex3 or codex4)" ;;
esac
shift 2
select_seat

case "${1:-}" in
  --status)   shift; status ;;
  --erase)    shift; destructive erase ;;
  --shutdown) shift; destructive shutdown ;;
  --boot)     shift; destructive boot ;;
  "")         usage; exit 1 ;;
  --*)        die "unknown flag: $1" ;;
  *)          run_locked "$@" ;;
esac
