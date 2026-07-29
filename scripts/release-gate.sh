#!/usr/bin/env bash
# Runs the iOS release build and simulator UI suite.
#
# MUST be invoked through scripts/sim-lock.sh, which owns the simulator lock:
#
#   ./scripts/sim-lock.sh ./scripts/release-gate.sh
#
# This script does not take the lock itself. Two lock-takers is how the lock
# path drifted apart in the first place, so there is exactly one.
#
# Successful runs keep this invocation's DerivedData warm; failed runs keep
# DerivedData and the .xcresult for diagnosis.
set -euo pipefail

PROJECT="ios/App/MakingTracks.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
SCHEME="MakingTracks"
DESTINATION="${MT_RELEASE_GATE_DESTINATION:-}"
[ -n "$DESTINATION" ] || {
  echo "release-gate: refused: MT_RELEASE_GATE_DESTINATION is required; export this seat's destination from wp-infra-sim-concurrency" >&2
  exit 1
}
case "$DESTINATION" in
  *id=*) GATE_UDID="${DESTINATION#*id=}" ;;
  *)
    echo "release-gate: refused: MT_RELEASE_GATE_DESTINATION must include id=<simulator-udid>" >&2
    exit 1
    ;;
esac
GATE_UDID="${GATE_UDID%%,*}"
case "$GATE_UDID" in
  ""|*[!A-Za-z0-9-]*)
    echo "release-gate: refused: MT_RELEASE_GATE_DESTINATION contains an invalid simulator UDID" >&2
    exit 1
    ;;
esac
RUN_DIR="${MT_RELEASE_GATE_RUN_DIR:-/private/tmp/release-gate-$GATE_UDID}"
DERIVED_DATA="${MT_RELEASE_GATE_DERIVED_DATA:-$RUN_DIR/DerivedData}"
RESULT_BUNDLE="$RUN_DIR/MakingTracksTests.xcresult"
MODE="${MT_RELEASE_GATE_MODE:-full}"
ONLY_TESTING_FILE="${MT_RELEASE_GATE_ONLY_TESTING_FILE:-}"
XCTESTRUN_FILE="${MT_RELEASE_GATE_XCTESTRUN_FILE:-}"
ENUMERATED_TESTS_JSON="${MT_RELEASE_GATE_ENUMERATED_TESTS_JSON:-$RUN_DIR/enumerated-tests.json}"
DERIVED_DATA_MAX_AGE_SECONDS="${MT_RELEASE_GATE_DERIVED_DATA_MAX_AGE_SECONDS:-604800}"

refuse() {
  echo "release-gate: refused: $1" >&2
  exit 1
}

mtime_seconds() {
  stat -f %m "$1" 2>/dev/null || echo 0
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
  [ "${MT_SIM_LOCK:-}" = "1" ] && return 0
  [ "${MT_RELEASE_GATE_SKIP_LOCK:-}" = "1" ] && [ "${GITHUB_ACTIONS:-}" = "true" ]
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
  refuse "must be run through scripts/sim-lock.sh (which holds the simulator lock)"

mkdir -p "$RUN_DIR"
prune_derived_data_if_stale
mkdir -p "$DERIVED_DATA"
[ "${MT_RELEASE_GATE_RESULT_BUNDLE:-}" = "" ] || RESULT_BUNDLE="$MT_RELEASE_GATE_RESULT_BUNDLE"
rm -rf "$RESULT_BUNDLE"

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
