#!/usr/bin/env bash
# Runs the iOS release build and simulator UI suite under the shared simulator
# lock. Successful runs remove this invocation's DerivedData after xcodebuild
# has finished; failed runs keep DerivedData and the .xcresult for diagnosis.
set -euo pipefail

PROJECT="ios/App/MakingTracks.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
SCHEME="MakingTracks"
UDID="C4A64D49-24A2-4429-B6E2-AD9A14142A99"
LOCK="/private/tmp/making-tracks-ios-tests.lock"
RUN_DIR="${MT_RELEASE_GATE_RUN_DIR:-/private/tmp/release-gate-${AM_ME:-agent}}"
FLOCK_BIN="/opt/homebrew/bin/flock"
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

if [ -n "${MT_RELEASE_GATE_FLOCK_BIN:-}" ]; then
  [ "${MT_RELEASE_GATE_TEST_MODE:-}" = "1" ] ||
    refuse "MT_RELEASE_GATE_FLOCK_BIN is only allowed in test mode"
  FLOCK_BIN="$MT_RELEASE_GATE_FLOCK_BIN"
fi

[ -x "$FLOCK_BIN" ] || refuse "flock not executable at $FLOCK_BIN"

mkdir -p "$RUN_DIR" "$DERIVED_DATA"
rm -rf "$RESULT_BUNDLE"

UDID="$UDID" DERIVED_DATA="$DERIVED_DATA" RESULT_BUNDLE="$RESULT_BUNDLE" "$FLOCK_BIN" "$LOCK" sh -ec '
  xcrun simctl bootstatus "$UDID" -b
  xcodebuild build \
    -configuration Release \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED_DATA"
  xcodebuild \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "platform=iOS Simulator,id=$UDID" \
    -parallel-testing-enabled NO \
    -disable-concurrent-destination-testing \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$RESULT_BUNDLE" \
    test
'

rm -rf "$DERIVED_DATA"
