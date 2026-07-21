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
UDID="C4A64D49-24A2-4429-B6E2-AD9A14142A99"
DESTINATION="${MT_RELEASE_GATE_DESTINATION:-platform=iOS Simulator,id=$UDID}"
RUN_DIR="${MT_RELEASE_GATE_RUN_DIR:-/private/tmp/release-gate-${AM_ME:-agent}}"
DERIVED_DATA="${MT_RELEASE_GATE_DERIVED_DATA:-$RUN_DIR/DerivedData}"
RESULT_BUNDLE="$RUN_DIR/MakingTracksTests.xcresult"
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

destination_udid() {
  case "$DESTINATION" in
    *id=*)
      value="${DESTINATION#*id=}"
      echo "${value%%,*}"
      ;;
    *)
      refuse "MT_RELEASE_GATE_DESTINATION must include id=<simulator-udid>"
      ;;
  esac
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
rm -rf "$RESULT_BUNDLE"

phase "simulator boot" xcrun simctl bootstatus "$(destination_udid)" -b
phase "release build" xcodebuild build \
  -configuration Release \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA"
phase "debug build for testing" xcodebuild build-for-testing \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -derivedDataPath "$DERIVED_DATA"
phase "tests without building" xcodebuild test-without-building \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE"

touch "$DERIVED_DATA"
