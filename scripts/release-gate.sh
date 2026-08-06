#!/usr/bin/env bash
# Runs the iOS release build and simulator UI suite.
#
# MUST be invoked through scripts/sim-lock.sh, which owns the simulator lock:
#
#   ./scripts/sim-lock.sh --seat codexN ./scripts/release-gate.sh
#
# This script does not take the lock itself. Two lock-takers is how the lock
# path drifted apart in the first place, so there is exactly one.
#
# Successful runs keep this invocation's DerivedData warm; failed runs keep
# DerivedData and the .xcresult for diagnosis.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091 # Runtime-relative shared library.
# shellcheck source=derived-data-path.sh
. "$SCRIPT_DIR/derived-data-path.sh"

PROJECT="ios/App/MakingTracks.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
SCHEME="MakingTracks"
if [ "${GITHUB_ACTIONS:-}" = "true" ] &&
   [ "${MT_RELEASE_GATE_SKIP_LOCK:-}" = "1" ]; then
  DESTINATION_VARIABLE="MT_RELEASE_GATE_CI_DESTINATION"
  DESTINATION="${MT_RELEASE_GATE_CI_DESTINATION:-}"
else
  DESTINATION_VARIABLE="MT_SIM_LOCK_DESTINATION"
  DESTINATION="${MT_SIM_LOCK_DESTINATION:-}"
fi
[ -n "$DESTINATION" ] || {
  echo "release-gate: refused: $DESTINATION_VARIABLE is missing; run through scripts/sim-lock.sh --seat <seat>" >&2
  exit 1
}
DESTINATION_FIELDS=",$DESTINATION,"
case "$DESTINATION_FIELDS" in
  *,id=*) DESTINATION_AFTER_ID="${DESTINATION_FIELDS#*,id=}" ;;
  *)
    echo "release-gate: refused: $DESTINATION_VARIABLE must include id=<simulator-udid>" >&2
    exit 1
    ;;
esac
GATE_UDID="${DESTINATION_AFTER_ID%%,*}"
DESTINATION_REMAINDER="${DESTINATION_AFTER_ID#"$GATE_UDID"}"
case "$DESTINATION_REMAINDER" in
  *,id=*)
    echo "release-gate: refused: $DESTINATION_VARIABLE must contain exactly one id=<simulator-udid>" >&2
    exit 1
    ;;
esac
case "$GATE_UDID" in
  ""|*[!A-Za-z0-9-]*)
    echo "release-gate: refused: $DESTINATION_VARIABLE contains an invalid simulator UDID" >&2
    exit 1
    ;;
esac
if [[ ! "$GATE_UDID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo "release-gate: refused: $DESTINATION_VARIABLE id must be a valid CoreSimulator UUID" >&2
  exit 1
fi
DEFAULT_GATE_ROOT="/private/tmp/release-gate-$GATE_UDID"
RUN_DIR_OVERRIDE="${MT_RELEASE_GATE_RUN_DIR:-}"
RESULT_BUNDLE_OVERRIDE="${MT_RELEASE_GATE_RESULT_BUNDLE:-}"
RUN_DIR="${RUN_DIR_OVERRIDE:-$DEFAULT_GATE_ROOT}"
DERIVED_DATA="${MT_RELEASE_GATE_DERIVED_DATA:-}"
RESULT_BUNDLE="$RUN_DIR/MakingTracksTests.xcresult"
MODE="${MT_RELEASE_GATE_MODE:-full}"
ONLY_TESTING_FILE="${MT_RELEASE_GATE_ONLY_TESTING_FILE:-}"
XCTESTRUN_FILE="${MT_RELEASE_GATE_XCTESTRUN_FILE:-}"
ENUMERATED_TESTS_JSON="${MT_RELEASE_GATE_ENUMERATED_TESTS_JSON:-$RUN_DIR/enumerated-tests.json}"
DERIVED_DATA_MAX_AGE_SECONDS="${MT_RELEASE_GATE_DERIVED_DATA_MAX_AGE_SECONDS:-604800}"
ARTIFACT_MARKER_SCHEMA="release-gate-artifact-v1"
OWNS_ARTIFACT_RUN=false
RUNS_ROOT=""
RUNS_ROOT_CANONICAL=""
OWNERSHIP_MARKER=""
SUCCESS_MARKER=""

refuse() {
  echo "release-gate: refused: $1" >&2
  exit 1
}

mtime_seconds() {
  stat -f %m "$1" 2>/dev/null || echo 0
}

canonical_directory() {
  (cd "$1" 2>/dev/null && pwd -P)
}

marker_matches_identity() {
  local byte_count
  local expected_byte_count
  local line_count
  local marker="$1"

  [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
  line_count="$(wc -l <"$marker" | tr -d '[:space:]')"
  byte_count="$(wc -c <"$marker" | tr -d '[:space:]')"
  expected_byte_count="$(printf '%s\nudid=%s\n' "$ARTIFACT_MARKER_SCHEMA" "$GATE_UDID" | wc -c | tr -d '[:space:]')"
  [ "$line_count" = "2" ] &&
    [ "$byte_count" = "$expected_byte_count" ] &&
    [ "$(sed -n '1p' "$marker")" = "$ARTIFACT_MARKER_SCHEMA" ] &&
    [ "$(sed -n '2p' "$marker")" = "udid=$GATE_UDID" ]
}

write_identity_marker() {
  local marker="$1"

  printf '%s\nudid=%s\n' "$ARTIFACT_MARKER_SCHEMA" "$GATE_UDID" >"$marker"
  marker_matches_identity "$marker" ||
    refuse "could not create an exact release-gate identity marker: $marker"
}

require_real_directory() {
  local label="$1"
  local path="$2"

  [ ! -L "$path" ] || refuse "$label must not be a symlink: $path"
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    refuse "$label must be a directory: $path"
  fi
}

prepare_artifact_paths() {
  local gate_root_canonical
  local run_name

  if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    case "$MODE" in
      full|test|enumerate)
        if [ -z "$RUN_DIR_OVERRIDE" ] && [ -z "$RESULT_BUNDLE_OVERRIDE" ]; then
          OWNS_ARTIFACT_RUN=true
        fi
        ;;
    esac
  fi

  if [ "$OWNS_ARTIFACT_RUN" = "true" ]; then
    require_real_directory "release-gate artifact root" "$DEFAULT_GATE_ROOT"
    mkdir -p "$DEFAULT_GATE_ROOT"
    gate_root_canonical="$(canonical_directory "$DEFAULT_GATE_ROOT")" ||
      refuse "could not canonicalize release-gate artifact root: $DEFAULT_GATE_ROOT"
    [ "$gate_root_canonical" = "$DEFAULT_GATE_ROOT" ] ||
      refuse "release-gate artifact root resolves outside its validated UUID path: $DEFAULT_GATE_ROOT"

    RUNS_ROOT="$DEFAULT_GATE_ROOT/runs"
    require_real_directory "release-gate runs root" "$RUNS_ROOT"
    mkdir -p "$RUNS_ROOT"
    RUNS_ROOT_CANONICAL="$(canonical_directory "$RUNS_ROOT")" ||
      refuse "could not canonicalize release-gate runs root: $RUNS_ROOT"
    [ "$RUNS_ROOT_CANONICAL" = "$RUNS_ROOT" ] ||
      refuse "release-gate runs root resolves outside its validated UUID path: $RUNS_ROOT"

    run_name="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    RUN_DIR="$RUNS_ROOT/$run_name"
    if [ -e "$RUN_DIR" ] || [ -L "$RUN_DIR" ]; then
      refuse "release-gate owned run path already exists: $RUN_DIR"
    fi
    mkdir "$RUN_DIR"
    OWNERSHIP_MARKER="$RUN_DIR/.release-gate-owned"
    SUCCESS_MARKER="$RUN_DIR/.release-gate-success"
    write_identity_marker "$OWNERSHIP_MARKER"
    RESULT_BUNDLE="$RUN_DIR/MakingTracksTests.xcresult"
    ENUMERATED_TESTS_JSON="${MT_RELEASE_GATE_ENUMERATED_TESTS_JSON:-$RUN_DIR/enumerated-tests.json}"
    echo "release-gate: owned artifacts: $RUN_DIR" >&2
    return
  fi

  RUN_DIR="${RUN_DIR_OVERRIDE:-$DEFAULT_GATE_ROOT}"
  RESULT_BUNDLE="${RESULT_BUNDLE_OVERRIDE:-$RUN_DIR/MakingTracksTests.xcresult}"
  ENUMERATED_TESTS_JSON="${MT_RELEASE_GATE_ENUMERATED_TESTS_JSON:-$RUN_DIR/enumerated-tests.json}"
  mkdir -p "$RUN_DIR"
}

validate_current_owned_run() {
  local current_canonical
  local current_parent_canonical

  [ "$OWNS_ARTIFACT_RUN" = "true" ] || return 0
  [ -d "$RUN_DIR" ] && [ ! -L "$RUN_DIR" ] ||
    refuse "owned release-gate run is no longer a real directory: $RUN_DIR"
  current_canonical="$(canonical_directory "$RUN_DIR")" ||
    refuse "could not canonicalize owned release-gate run: $RUN_DIR"
  current_parent_canonical="$(canonical_directory "$(dirname "$current_canonical")")" ||
    refuse "could not canonicalize owned release-gate run parent: $RUN_DIR"
  [ "$current_parent_canonical" = "$RUNS_ROOT_CANONICAL" ] ||
    refuse "owned release-gate run escaped its runs root: $RUN_DIR"
  [[ "$(basename "$current_canonical")" =~ ^run-[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] ||
    refuse "owned release-gate run has an invalid name: $RUN_DIR"
  marker_matches_identity "$OWNERSHIP_MARKER" ||
    refuse "owned release-gate marker is missing or invalid: $OWNERSHIP_MARKER"
}

finalize_owned_artifacts() {
  [ "$OWNS_ARTIFACT_RUN" = "true" ] || return 0
  validate_current_owned_run
  if [ -e "$SUCCESS_MARKER" ] || [ -L "$SUCCESS_MARKER" ]; then
    refuse "release-gate success marker already exists: $SUCCESS_MARKER"
  fi
  write_identity_marker "$SUCCESS_MARKER"
}

prune_derived_data_if_stale() {
  if [ ! -d "$DERIVED_DATA" ]; then
    return
  fi

  if [ "${MT_RELEASE_GATE_CLEAN_DERIVED_DATA:-}" = "1" ]; then
    echo "release-gate: pruning DerivedData because MT_RELEASE_GATE_CLEAN_DERIVED_DATA=1" >&2
    rm -rf "$DERIVED_DATA"
    return
  fi

  if [ "$DERIVED_DATA_MAX_AGE_SECONDS" = "0" ]; then
    return
  fi

  now="$(date +%s)"
  mtime="$(mtime_seconds "$DERIVED_DATA")"
  age=$((now - mtime))
  if [ "$age" -gt "$DERIVED_DATA_MAX_AGE_SECONDS" ]; then
    echo "release-gate: pruning DerivedData older than ${DERIVED_DATA_MAX_AGE_SECONDS}s" >&2
    rm -rf "$DERIVED_DATA"
  fi
}

phase() {
  local label
  local start
  local status
  local end

  label="$1"
  shift
  start="$(date +%s)"
  echo "release-gate: phase start: $label" >&2
  set +e
  "$@"
  status=$?
  set -e
  end="$(date +%s)"
  echo "release-gate: phase end: $label status=$status elapsed=$((end - start))s" >&2
  return "$status"
}

xcodebuild_log_name() {
  local label

  label="${1// /-}"
  printf "%s.xcodebuild.log" "$label"
}

run_xcodebuild() {
  local label
  local raw_log

  label="$1"
  shift

  if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    xcodebuild "$@"
    return
  fi

  command -v xcbeautify >/dev/null 2>&1 ||
    refuse "xcbeautify must be installed for GitHub Actions release-gate logs"

  raw_log="$RUN_DIR/$(xcodebuild_log_name "$label")"
  xcodebuild "$@" 2>&1 | tee "$raw_log" | xcbeautify
}

populate_only_testing_args() {
  local line

  [ -n "$ONLY_TESTING_FILE" ] || return 0
  [ -f "$ONLY_TESTING_FILE" ] ||
    refuse "MT_RELEASE_GATE_ONLY_TESTING_FILE does not exist: $ONLY_TESTING_FILE"

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
      ""|\#*) continue ;;
    esac
    only_testing_args+=("-only-testing:$line")
  done < "$ONLY_TESTING_FILE"
}

populate_test_plan_args() {
  if [ -n "$XCTESTRUN_FILE" ]; then
    [ -f "$XCTESTRUN_FILE" ] ||
      refuse "MT_RELEASE_GATE_XCTESTRUN_FILE does not exist: $XCTESTRUN_FILE"
    test_args=(-xctestrun "$XCTESTRUN_FILE")
  else
    test_args=(-project ios/App/MakingTracks.xcodeproj -scheme "$SCHEME")
  fi
}

destination_udid() {
  printf '%s\n' "$GATE_UDID"
}

lock_is_satisfied() {
  if [ "${MT_RELEASE_GATE_SKIP_LOCK:-}" = "1" ] && [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    return 0
  fi
  [ "${MT_SIM_LOCK:-}" = "1" ] || return 1
  [ -n "${MT_SIM_LOCK_UDID:-}" ] ||
    refuse "simulator lock identity is missing (MT_SIM_LOCK_UDID)"
  [ "$MT_SIM_LOCK_UDID" = "$GATE_UDID" ] ||
    refuse "simulator lock is for simulator $MT_SIM_LOCK_UDID, not $GATE_UDID"
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not inside a git worktree"
cd "$REPO_ROOT"

git fetch --quiet origin ios || refuse "could not fetch origin/ios"

[ -f "$PBXPROJ" ] || refuse "MakingTracksTests target missing from $PROJECT"
grep -q 'PBXNativeTarget "MakingTracksTests"' "$PBXPROJ" ||
  refuse "MakingTracksTests target missing from $PROJECT"

git merge-base --is-ancestor origin/ios HEAD ||
  refuse "HEAD is not based on current origin/ios"

lock_is_satisfied ||
  refuse "must be run through scripts/sim-lock.sh --seat <seat> (which holds the simulator lock)"

if [ -z "$DERIVED_DATA" ]; then
  case "${MT_SIM_LOCK_SEAT:-}" in
    codex1|codex2|codex3|codex4) ;;
    *)
      refuse "MT_SIM_LOCK_SEAT is missing or invalid; run through scripts/sim-lock.sh --seat <seat>"
      ;;
  esac
  DERIVED_DATA="$HOME/Library/Caches/making-tracks-gates/$MT_SIM_LOCK_SEAT"
  mkdir -p "$HOME/Library/Caches/making-tracks-gates"
fi
DERIVED_DATA="$(mt_refuse_tmp_derived_data "$DERIVED_DATA" "release-gate:")" || exit 1

prepare_artifact_paths
prune_derived_data_if_stale
mkdir -p "$DERIVED_DATA"
case "$MODE" in
  full|test)
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      rm -rf "$RESULT_BUNDLE"
    elif [ "$OWNS_ARTIFACT_RUN" != "true" ] &&
         { [ -e "$RESULT_BUNDLE" ] || [ -L "$RESULT_BUNDLE" ]; }; then
      refuse "caller-owned result already exists; move it to \$HOME/Library/Application Support/making-tracks-gates/evidence/ or remove it after extraction: $RESULT_BUNDLE"
    fi
    ;;
esac

phase "simulator boot" xcrun simctl bootstatus "$(destination_udid)" -b

case "$MODE" in
  full|build)
    phase "release build" run_xcodebuild "release build" build \
      -configuration Release \
      -project ios/App/MakingTracks.xcodeproj \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED_DATA"
    phase "debug build for testing" run_xcodebuild "debug build for testing" build-for-testing \
      -project ios/App/MakingTracks.xcodeproj \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -parallel-testing-enabled NO \
      -disable-concurrent-destination-testing \
      -derivedDataPath "$DERIVED_DATA"
    ;;
  test|enumerate)
    ;;
  *)
    refuse "unknown MT_RELEASE_GATE_MODE: $MODE"
    ;;
esac

case "$MODE" in
  full|test)
    test_args=()
    only_testing_args=()
    populate_test_plan_args
    populate_only_testing_args
    [ -z "$ONLY_TESTING_FILE" ] || [ "${#only_testing_args[@]}" -gt 0 ] ||
      refuse "MT_RELEASE_GATE_ONLY_TESTING_FILE has no runnable entries: $ONLY_TESTING_FILE"
    phase "tests without building" run_xcodebuild "tests without building" test-without-building \
      "${test_args[@]}" \
      -destination "$DESTINATION" \
      -parallel-testing-enabled NO \
      -disable-concurrent-destination-testing \
      -derivedDataPath "$DERIVED_DATA" \
      "${only_testing_args[@]}" \
      -resultBundlePath "$RESULT_BUNDLE"
    ;;
  enumerate)
    test_args=()
    populate_test_plan_args
    phase "enumerate tests" run_xcodebuild "enumerate tests" test-without-building \
      "${test_args[@]}" \
      -destination "$DESTINATION" \
      -parallel-testing-enabled NO \
      -disable-concurrent-destination-testing \
      -derivedDataPath "$DERIVED_DATA" \
      -enumerate-tests \
      -test-enumeration-style flat \
      -test-enumeration-format json \
      -test-enumeration-output-path "$ENUMERATED_TESTS_JSON"
    ;;
esac

touch "$DERIVED_DATA"
finalize_owned_artifacts
