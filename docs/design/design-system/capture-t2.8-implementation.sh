#!/usr/bin/env bash

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
DESTINATION="${MT_SIM_LOCK_DESTINATION:-}"
SEAT="${MT_SIM_LOCK_SEAT:-}"
DERIVED_DATA="${MT_RELEASE_GATE_DERIVED_DATA:-}"
ARTIFACTS="/private/tmp/making-tracks-artifacts"
OUTPUT="$ROOT/docs/design/design-system"

cleanup_results() {
  [ -d "$DERIVED_DATA/Logs/Test" ] || return 0
  while IFS= read -r result_bundle; do
    rm -rf "$result_bundle"
  done < <(find "$DERIVED_DATA/Logs/Test" -type d -name '*.xcresult' -prune -print)
}

[ -n "$DESTINATION" ] || {
  echo "capture-t2.8-implementation: MT_SIM_LOCK_DESTINATION is required" >&2
  exit 1
}
[ -n "$DERIVED_DATA" ] || {
  echo "capture-t2.8-implementation: MT_RELEASE_GATE_DERIVED_DATA is required" >&2
  exit 1
}
[ "${MT_SIM_LOCK:-}" = "1" ] || {
  echo "capture-t2.8-implementation: invoke through scripts/sim-lock.sh --seat <seat>" >&2
  exit 1
}
[ -n "$SEAT" ] || {
  echo "capture-t2.8-implementation: MT_SIM_LOCK_SEAT is required" >&2
  exit 1
}
expected_derived_data="$HOME/Library/Caches/making-tracks-gates/$SEAT"
[ "$DERIVED_DATA" = "$expected_derived_data" ] || {
  echo "capture-t2.8-implementation: derived data must be the locked seat cache path: $expected_derived_data" >&2
  exit 1
}

destination_fields=",$DESTINATION,"
case "$destination_fields" in
  *,id=*) destination_after_id="${destination_fields#*,id=}" ;;
  *)
    echo "capture-t2.8-implementation: destination must include id=<simulator-udid>" >&2
    exit 1
    ;;
esac
simulator_udid="${destination_after_id%%,*}"
[ "${MT_SIM_LOCK_UDID:-}" = "$simulator_udid" ] || {
  echo "capture-t2.8-implementation: simulator lock does not match destination" >&2
  exit 1
}

xcrun simctl bootstatus "$simulator_udid" -b

cd "$ROOT"

xcodebuild test \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testMapHomeExposesBothDoorsAndExploreOpensScopeDirectly \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testDoorsRemainTappableAtAX5InDarkAppearance \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testExploreDoorIndicatorAndClearScopeRoundTrip \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLovedTrackChipDrivesMapSource \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testExploreOtherListsDrillInUpdatesLiveAndClearStaysOutsideCollection \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testExploreOtherListsAX5KeepsLongLiteralRowsAndFixedActionsContained \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testExploreOtherListsEmptyStateNamesExcludedLists

trap cleanup_results EXIT

declare -a captures=(
  explore-door-default
  explore-door-ax
  explore-door-scope-default
  explore-door-scope-adjusted
  explore-scope-list-open
  explore-scope-other-lists
  explore-scope-other-lists-ax
  explore-scope-other-lists-empty
)

for name in "${captures[@]}"; do
  source="$ARTIFACTS/$name.png"
  target="$OUTPUT/t2.8-$name.png"
  measurements="$ARTIFACTS/$name.txt"
  [ -s "$source" ] || {
    echo "capture-t2.8-implementation: missing capture $source" >&2
    exit 1
  }
  [ -s "$measurements" ] || {
    echo "capture-t2.8-implementation: missing measurements $measurements" >&2
    exit 1
  }
  cp "$source" "$target"
  cp "$measurements" "$OUTPUT/t2.8-$name.txt"
done

metadata="$OUTPUT/t2.8-implementation-captures.txt"
{
  echo "Making Tracks T2.8 implementation captures"
  echo "git: $(git rev-parse HEAD)"
  echo "destination: $DESTINATION"
  echo "capture: XCUIScreen.main.screenshot via Xcode UI testing"
  xcodebuild -version | sed 's/^/capture-tool: /'
  echo
  for name in "${captures[@]}"; do
    target="$OUTPUT/t2.8-$name.png"
    shasum -a 256 "$target"
    sips -g pixelWidth -g pixelHeight "$target" | sed 's/^/  /'
    sed 's/^/  /' "$OUTPUT/t2.8-$name.txt"
  done
} > "$metadata"

cat "$metadata"
