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
PACKAGE_RESOLVED="ios/Package.resolved"
PACKAGE_RESOLVED_DIGEST=""
PACKAGE_RESOLUTION_ARGS=(-onlyUsePackageVersionsFromResolvedFile)
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
# #546 planner ruling: successful local artifacts are eligible only when strictly older than 24 hours.
SUCCESSFUL_ARTIFACT_MAX_AGE_SECONDS=86400
OWNS_ARTIFACT_RUN=false
PRUNE_AFTER_SUCCESS=false
RUNS_ROOT=""
RUNS_ROOT_CANONICAL=""
OWNERSHIP_MARKER=""
SUCCESS_MARKER=""

refuse() {
  echo "release-gate: refused: $1" >&2
  exit 1
}

package_resolution_digest() {
  shasum -a 256 "$PACKAGE_RESOLVED" | awk '{print $1}'
}

package_resolution_matches_head() {
  [ -f "$PACKAGE_RESOLVED" ] &&
    [ ! -L "$PACKAGE_RESOLVED" ] &&
    git ls-files --error-unmatch -- "$PACKAGE_RESOLVED" >/dev/null 2>&1 &&
    git diff --quiet -- "$PACKAGE_RESOLVED" &&
    git diff --cached --quiet HEAD -- "$PACKAGE_RESOLVED"
}

capture_committed_package_resolution() {
  package_resolution_matches_head ||
    refuse "$PACKAGE_RESOLVED must be a regular tracked file matching HEAD; commit the intentional update, or restore it from HEAD"
  PACKAGE_RESOLVED_DIGEST="$(package_resolution_digest)" ||
    refuse "could not hash committed package resolution: $PACKAGE_RESOLVED"
  [ -n "$PACKAGE_RESOLVED_DIGEST" ] ||
    refuse "could not hash committed package resolution: $PACKAGE_RESOLVED"
  echo "release-gate: package resolution: $PACKAGE_RESOLVED sha256=$PACKAGE_RESOLVED_DIGEST" >&2
}

verify_committed_package_resolution() {
  local current_digest

  if ! package_resolution_matches_head; then
    echo "release-gate: dependency resolution drift: Xcode changed $PACKAGE_RESOLVED; refusing gate result" >&2
    return 1
  fi
  current_digest="$(package_resolution_digest)" || {
    echo "release-gate: dependency resolution drift: could not hash $PACKAGE_RESOLVED after Xcode" >&2
    return 1
  }
  if [ "$current_digest" != "$PACKAGE_RESOLVED_DIGEST" ]; then
    echo "release-gate: dependency resolution drift: $PACKAGE_RESOLVED sha256=$current_digest expected=$PACKAGE_RESOLVED_DIGEST" >&2
    return 1
  fi
}

mtime_seconds() {
  stat -f %m "$1" 2>/dev/null || echo 0
}

gate_now_seconds() {
  if [ "${MT_SIM_LOCK_TEST_MODE:-}" = "1" ] &&
     [ -n "${MT_RELEASE_GATE_TEST_NOW:-}" ]; then
    case "$MT_RELEASE_GATE_TEST_NOW" in
      *[!0-9]*) refuse "MT_RELEASE_GATE_TEST_NOW must be decimal seconds in test mode" ;;
    esac
    printf '%s\n' "$MT_RELEASE_GATE_TEST_NOW"
    return
  fi
  date +%s
}

canonical_directory() {
  (cd "$1" 2>/dev/null && pwd -P)
}

marker_matches_identity() {
  marker_matches_identity_for_udid "$1" "$GATE_UDID"
}

marker_matches_identity_for_udid() {
  local byte_count
  local expected_byte_count
  local line_count
  local marker="$1"
  local expected_udid="$2"

  [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
  line_count="$(wc -l <"$marker" | tr -d '[:space:]')"
  byte_count="$(wc -c <"$marker" | tr -d '[:space:]')"
  expected_byte_count="$(printf '%s\nudid=%s\n' "$ARTIFACT_MARKER_SCHEMA" "$expected_udid" | wc -c | tr -d '[:space:]')"
  [ "$line_count" = "2" ] &&
    [ "$byte_count" = "$expected_byte_count" ] &&
    [ "$(sed -n '1p' "$marker")" = "$ARTIFACT_MARKER_SCHEMA" ] &&
    [ "$(sed -n '2p' "$marker")" = "udid=$expected_udid" ]
}

write_identity_marker() {
  write_identity_marker_for_udid "$1" "$GATE_UDID"
}

write_identity_marker_for_udid() {
  local marker="$1"
  local marker_udid="$2"

  printf '%s\nudid=%s\n' "$ARTIFACT_MARKER_SCHEMA" "$marker_udid" >"$marker"
  marker_matches_identity_for_udid "$marker" "$marker_udid" ||
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

mark_containing_owned_run_preserved() {
  local artifact_path="$1"
  local containing_run
  local containing_udid
  local existing_ancestor
  local existing_ancestor_canonical
  local owned_run_pattern
  local preserve_marker

  if [ -d "$artifact_path" ]; then
    existing_ancestor="$artifact_path"
  else
    existing_ancestor="$(dirname "$artifact_path")"
  fi
  while [ ! -d "$existing_ancestor" ]; do
    [ "$existing_ancestor" != "/" ] || return 0
    existing_ancestor="$(dirname "$existing_ancestor")"
  done
  existing_ancestor_canonical="$(canonical_directory "$existing_ancestor")" || return 0
  owned_run_pattern='^(/private/tmp/release-gate-([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})/runs/run-[0-9]{8}T[0-9]{6}Z-[0-9]+)(/|$)'
  [[ "$existing_ancestor_canonical" =~ $owned_run_pattern ]] || return 0
  containing_run="${BASH_REMATCH[1]}"
  containing_udid="${BASH_REMATCH[2]}"
  [ -d "$containing_run" ] && [ ! -L "$containing_run" ] || return 0
  marker_matches_identity_for_udid "$containing_run/.release-gate-owned" "$containing_udid" || return 0
  marker_matches_identity_for_udid "$containing_run/.release-gate-success" "$containing_udid" || return 0

  preserve_marker="$containing_run/.release-gate-preserve"
  if [ -e "$preserve_marker" ] || [ -L "$preserve_marker" ]; then
    marker_matches_identity_for_udid "$preserve_marker" "$containing_udid" ||
      refuse "caller-owned artifact preserve marker is unsafe: $preserve_marker"
    return 0
  fi
  write_identity_marker_for_udid "$preserve_marker" "$containing_udid"
  echo "release-gate: caller-owned artifact permanently preserves containing run: $containing_run" >&2
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
    if [ "$MODE" = "enumerate" ] &&
       [ -n "${MT_RELEASE_GATE_ENUMERATED_TESTS_JSON:-}" ]; then
      mark_containing_owned_run_preserved "$ENUMERATED_TESTS_JSON"
    fi
    if [ "$MODE" = "full" ] &&
       [ -z "$ONLY_TESTING_FILE" ] &&
       [ -z "$XCTESTRUN_FILE" ]; then
      PRUNE_AFTER_SUCCESS=true
    fi
    echo "release-gate: owned artifacts: $RUN_DIR" >&2
    return
  fi

  RUN_DIR="${RUN_DIR_OVERRIDE:-$DEFAULT_GATE_ROOT}"
  RESULT_BUNDLE="${RESULT_BUNDLE_OVERRIDE:-$RUN_DIR/MakingTracksTests.xcresult}"
  ENUMERATED_TESTS_JSON="${MT_RELEASE_GATE_ENUMERATED_TESTS_JSON:-$RUN_DIR/enumerated-tests.json}"
  if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    case "$MODE" in
      full|test) mark_containing_owned_run_preserved "$RESULT_BUNDLE" ;;
      enumerate) mark_containing_owned_run_preserved "$ENUMERATED_TESTS_JSON" ;;
    esac
  fi
  mkdir -p "$RUN_DIR"
}

validate_current_owned_run() {
  local current_canonical
  local current_parent_canonical

  [ "$OWNS_ARTIFACT_RUN" = "true" ] || return 0
  if [ ! -d "$RUN_DIR" ] || [ -L "$RUN_DIR" ]; then
    refuse "owned release-gate run is no longer a real directory: $RUN_DIR"
  fi
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
  [ "$PRUNE_AFTER_SUCCESS" != "true" ] || prune_successful_artifacts
}

prune_successful_artifacts() {
  local age
  local candidate
  local candidate_basename
  local candidate_canonical
  local candidate_identity
  local candidate_parent_canonical
  local cleanup_path
  local cleanup_canonical
  local cleanup_identity
  local cleanup_parent_canonical
  local marker_mtime
  local now

  validate_current_owned_run
  if [ ! -d "$RUNS_ROOT" ] || [ -L "$RUNS_ROOT" ]; then
    refuse "release-gate runs root became unsafe before cleanup: $RUNS_ROOT"
  fi
  [ "$(canonical_directory "$RUNS_ROOT")" = "$RUNS_ROOT_CANONICAL" ] ||
    refuse "release-gate runs root changed before cleanup: $RUNS_ROOT"
  now="$(gate_now_seconds)"

  for candidate in "$RUNS_ROOT"/*; do
    if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
      continue
    fi
    [ "$candidate" != "$RUN_DIR" ] || continue
    candidate_basename="$(basename "$candidate")"
    [[ "$candidate_basename" =~ ^run-[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] || continue
    if [ ! -d "$candidate" ] || [ -L "$candidate" ]; then
      continue
    fi
    candidate_canonical="$(canonical_directory "$candidate")" || continue
    candidate_parent_canonical="$(canonical_directory "$(dirname "$candidate_canonical")")" || continue
    [ "$candidate_parent_canonical" = "$RUNS_ROOT_CANONICAL" ] || continue
    [ "$candidate_canonical" = "$RUNS_ROOT_CANONICAL/$candidate_basename" ] || continue
    if [ -e "$candidate/.release-gate-preserve" ] || [ -L "$candidate/.release-gate-preserve" ]; then
      continue
    fi
    marker_matches_identity "$candidate/.release-gate-owned" || continue
    marker_matches_identity "$candidate/.release-gate-success" || continue
    marker_mtime="$(stat -f %m "$candidate/.release-gate-success" 2>/dev/null)" || continue
    case "$marker_mtime" in
      ""|*[!0-9]*) continue ;;
    esac
    age=$((now - marker_mtime))
    [ "$age" -gt "$SUCCESSFUL_ARTIFACT_MAX_AGE_SECONDS" ] || continue

    candidate_identity="$(stat -f '%d:%i' "$candidate" 2>/dev/null)" || continue
    cleanup_path="$RUNS_ROOT/.release-gate-cleanup-$$-$candidate_basename"
    if [ -e "$cleanup_path" ] || [ -L "$cleanup_path" ]; then
      echo "release-gate: cleanup warning: quarantine path already exists: $cleanup_path" >&2
      continue
    fi
    if ! mv "$candidate" "$cleanup_path"; then
      echo "release-gate: cleanup warning: could not quarantine eligible successful artifact: $candidate" >&2
      continue
    fi

    cleanup_identity="$(stat -f '%d:%i' "$cleanup_path" 2>/dev/null)" || cleanup_identity=""
    cleanup_canonical="$(canonical_directory "$cleanup_path")" || cleanup_canonical=""
    cleanup_parent_canonical="$(canonical_directory "$(dirname "$cleanup_path")")" || cleanup_parent_canonical=""
    if [ "$cleanup_identity" != "$candidate_identity" ] ||
       [ -z "$cleanup_canonical" ] ||
       [ "$cleanup_parent_canonical" != "$RUNS_ROOT_CANONICAL" ] ||
       [ -L "$cleanup_path" ] ||
       ! marker_matches_identity "$cleanup_path/.release-gate-owned" ||
       ! marker_matches_identity "$cleanup_path/.release-gate-success" ||
       [ -e "$cleanup_path/.release-gate-preserve" ] ||
       [ -L "$cleanup_path/.release-gate-preserve" ]; then
      echo "release-gate: cleanup warning: candidate changed during quarantine; preserving it: $candidate" >&2
      if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
        mv "$cleanup_path" "$candidate" ||
          echo "release-gate: cleanup warning: changed candidate remains preserved at: $cleanup_path" >&2
      else
        echo "release-gate: cleanup warning: changed candidate remains preserved at: $cleanup_path" >&2
      fi
      continue
    fi

    marker_mtime="$(stat -f %m "$cleanup_path/.release-gate-success" 2>/dev/null)" || marker_mtime=""
    case "$marker_mtime" in
      ""|*[!0-9]*) age=0 ;;
      *) age=$((now - marker_mtime)) ;;
    esac
    if [ "$age" -le "$SUCCESSFUL_ARTIFACT_MAX_AGE_SECONDS" ]; then
      echo "release-gate: cleanup warning: candidate age changed during quarantine; preserving it: $candidate" >&2
      mv "$cleanup_path" "$candidate" ||
        echo "release-gate: cleanup warning: changed candidate remains preserved at: $cleanup_path" >&2
      continue
    fi

    if ! rm -rf -- "$cleanup_path"; then
      echo "release-gate: cleanup warning: could not remove eligible successful artifact: $candidate" >&2
      if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
        mv "$cleanup_path" "$candidate" ||
          echo "release-gate: cleanup warning: partial artifact remains preserved at: $cleanup_path" >&2
      fi
    fi
  done
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
  local xcode_status

  label="$1"
  shift

  if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    xcodebuild "${PACKAGE_RESOLUTION_ARGS[@]}" "$@"
    xcode_status=$?
  else
    command -v xcbeautify >/dev/null 2>&1 ||
      refuse "xcbeautify must be installed for GitHub Actions release-gate logs"

    raw_log="$RUN_DIR/$(xcodebuild_log_name "$label")"
    xcodebuild "${PACKAGE_RESOLUTION_ARGS[@]}" "$@" 2>&1 | tee "$raw_log" | xcbeautify
    xcode_status=$?
  fi

  verify_committed_package_resolution || return 1
  return "$xcode_status"
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
    test_args+=("-only-testing:$line")
    only_testing_count=$((only_testing_count + 1))
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

capture_committed_package_resolution

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
    only_testing_count=0
    populate_test_plan_args
    populate_only_testing_args
    [ -z "$ONLY_TESTING_FILE" ] || [ "$only_testing_count" -gt 0 ] ||
      refuse "MT_RELEASE_GATE_ONLY_TESTING_FILE has no runnable entries: $ONLY_TESTING_FILE"
    phase "tests without building" run_xcodebuild "tests without building" test-without-building \
      "${test_args[@]}" \
      -destination "$DESTINATION" \
      -parallel-testing-enabled NO \
      -disable-concurrent-destination-testing \
      -derivedDataPath "$DERIVED_DATA" \
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
