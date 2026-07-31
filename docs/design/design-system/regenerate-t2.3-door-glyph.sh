#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
destination="${MT_RELEASE_GATE_DESTINATION:-}"
expected_xcode_version=$'Xcode 26.6\nBuild version 17F113'
artifact_dir="/private/tmp/making-tracks-artifacts"
output_dir="$repo_root/docs/design/design-system"

[ -n "$destination" ] || {
  echo "regenerate-t2.3-door-glyph: MT_RELEASE_GATE_DESTINATION is required" >&2
  exit 1
}
[ "${MT_SIM_LOCK:-}" = "1" ] || {
  echo "regenerate-t2.3-door-glyph: invoke through scripts/sim-lock.sh" >&2
  exit 1
}

destination_fields=",$destination,"
case "$destination_fields" in
  *,id=*) destination_after_id="${destination_fields#*,id=}" ;;
  *)
    echo "regenerate-t2.3-door-glyph: destination must include id=<simulator-udid>" >&2
    exit 1
    ;;
esac
simulator_udid="${destination_after_id%%,*}"
[ "${MT_SIM_LOCK_UDID:-}" = "$simulator_udid" ] || {
  echo "regenerate-t2.3-door-glyph: simulator lock does not match destination" >&2
  exit 1
}

actual_xcode_version="$(xcodebuild -version)"
[ "$actual_xcode_version" = "$expected_xcode_version" ] || {
  echo "regenerate-t2.3-door-glyph: requires $expected_xcode_version; found $actual_xcode_version" >&2
  exit 1
}

only_testing_file="$(mktemp /private/tmp/t2.3-door-glyph-only-testing.XXXXXX)"
cleanup() {
  xcrun simctl status_bar "$simulator_udid" clear >/dev/null 2>&1 || true
  rm -f "$only_testing_file"
}
trap cleanup EXIT

printf '%s\n' \
  'MakingTracksUITests/MakingTracksCoreLoopUITests/testDoorGlyphEvidenceFixturePinsColumnsAndCopySeparation' \
  > "$only_testing_file"

xcrun simctl status_bar "$simulator_udid" override \
  --time 09:41 \
  --dataNetwork wifi \
  --wifiBars 3 \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100

cd "$repo_root"
MAKING_TRACKS_EXPORT_UI_TEST_SCREENSHOTS=1 \
MT_RELEASE_GATE_ONLY_TESTING_FILE="$only_testing_file" \
  ./scripts/release-gate.sh

assets=(
  t2.3-door-glyph-before-default.png
  t2.3-door-glyph-after-default.png
  t2.3-door-glyph-before-ax.png
  t2.3-door-glyph-after-ax.png
)

for asset in "${assets[@]}"; do
  source_path="$artifact_dir/$asset"
  output_path="$output_dir/$asset"
  [ -s "$source_path" ] || {
    echo "regenerate-t2.3-door-glyph: missing capture $source_path" >&2
    exit 1
  }
  sips --resampleHeightWidth 844 390 "$source_path" --out "$output_path" >/dev/null

  pixel_width="$(sips -g pixelWidth "$output_path" | awk '/pixelWidth/ { print $2 }')"
  pixel_height="$(sips -g pixelHeight "$output_path" | awk '/pixelHeight/ { print $2 }')"
  [ "$pixel_width" = "390" ] && [ "$pixel_height" = "844" ] || {
    echo "regenerate-t2.3-door-glyph: $asset is ${pixel_width}x${pixel_height}, expected 390x844" >&2
    exit 1
  }
done

echo "$actual_xcode_version"
echo "XCTest XCUIScreen captures: 1206x2622 px, resampled without cropping to 390x844"
shasum -a 256 "${assets[@]/#/$output_dir/}"
