#!/usr/bin/env bash

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
DESTINATION="${MT_RELEASE_GATE_DESTINATION:-}"
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
  echo "capture-t2.8-implementation: MT_RELEASE_GATE_DESTINATION is required" >&2
  exit 1
}
[ -n "$DERIVED_DATA" ] || {
  echo "capture-t2.8-implementation: MT_RELEASE_GATE_DERIVED_DATA is required" >&2
  exit 1
}
case "$DERIVED_DATA" in
  /private/tmp/dd-*) ;;
  *)
    echo "capture-t2.8-implementation: derived data must be a stable /private/tmp/dd-* path" >&2
    exit 1
    ;;
esac

cd "$ROOT"

./scripts/sim-lock.sh xcodebuild test \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testMapHomeExposesBothDoorsAndExploreOpensScopeDirectly \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testDoorsRemainTappableAtAX5InDarkAppearance \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testExploreDoorIndicatorAndClearScopeRoundTrip \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLovedTrackChipDrivesMapSource \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testExploreOtherListsDrillInUpdatesLiveAndClearStaysOutsideCollection \
    -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testExploreOtherListsEmptyStateNamesExcludedLists

trap cleanup_results EXIT

declare -a captures=(
  explore-door-default
  explore-door-ax
  explore-door-scope-default
  explore-door-scope-adjusted
  explore-scope-list-open
  explore-scope-other-lists
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
