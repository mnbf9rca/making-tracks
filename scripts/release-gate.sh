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
# Successful runs remove this invocation's DerivedData after xcodebuild has
# finished; failed runs keep DerivedData and the .xcresult for diagnosis.
set -euo pipefail

PROJECT="ios/App/MakingTracks.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
SCHEME="MakingTracks"
UDID="C4A64D49-24A2-4429-B6E2-AD9A14142A99"
RUN_DIR="${MT_RELEASE_GATE_RUN_DIR:-/private/tmp/release-gate-${AM_ME:-agent}}"
DERIVED_DATA="${MT_RELEASE_GATE_DERIVED_DATA:-$RUN_DIR/DerivedData}"
RESULT_BUNDLE="$RUN_DIR/MakingTracksTests.xcresult"

refuse() {
  echo "release-gate: refused: $1" >&2
  exit 1
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not inside a git worktree"
cd "$REPO_ROOT"

git fetch --quiet origin ios || refuse "could not fetch origin/ios"

[ -f "$PBXPROJ" ] || refuse "MakingTracksTests target missing from $PROJECT"
grep -q 'PBXNativeTarget "MakingTracksTests"' "$PBXPROJ" ||
  refuse "MakingTracksTests target missing from $PROJECT"

git merge-base --is-ancestor origin/ios HEAD ||
  refuse "HEAD is not based on current origin/ios"

[ "${MT_SIM_LOCK:-}" = "1" ] ||
  refuse "must be run through scripts/sim-lock.sh (which holds the simulator lock)"

mkdir -p "$RUN_DIR" "$DERIVED_DATA"
rm -rf "$RESULT_BUNDLE"

UDID="$UDID" SCHEME="$SCHEME" DERIVED_DATA="$DERIVED_DATA" RESULT_BUNDLE="$RESULT_BUNDLE" sh -ec '
  xcrun simctl bootstatus "$UDID" -b
  xcodebuild build \
    -configuration Release \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED_DATA"
  xcodebuild \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -parallel-testing-enabled NO \
    -disable-concurrent-destination-testing \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$RESULT_BUNDLE" \
    test
'

rm -rf "$DERIVED_DATA"
