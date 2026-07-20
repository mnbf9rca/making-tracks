# Retrace Map Mockups

Static design renders for the frozen Retrace/tracks redesign. These are design
assets only; no app code changes accompany them.

Rob's accepted direction:

- Retrace opens as a map view, not a hidden list state.
- Visited places remain individual pins.
- Scrubbing time makes connection arcs glide across the map.
- Pins pop into colour as the scrubber reaches each visit.
- The slider must read as a real time slider, with Google Photos-style temporal
  affordance rather than a generic progress bar.
- The entry point must be obvious from the map.

Files:

- `retrace-entry-point.svg` / `.png` - obvious map-level entry into Retrace.
- `retrace-map-mid-scrub.svg` / `.png` - mid-scrub map state with arcs, pins,
  and the active time slider.
- `retrace-map-mid-scrub-axxxl.svg` / `.png` - same state at an accessibility
  text size, preserving the map and slider hierarchy.
- `retrace-slider-detail.svg` / `.png` - close-up of the event-indexed slider.

Validation notes:

- The map entry card treats Retrace as the primary destination; the old
  mapless Tracks drawer should not survive as a separate replay surface.
- Retrace does not show unreached or hidden places as faded tappable pins, and
  it does not expose hidden-place counts.
- The connection line is scaffolding: it stays behind the places, avoids system
  blue, and never dominates coloured pins.
- Same-day reordering is represented as a continuous track.
- Each phone-frame source includes a subtle fold/safe-area marker so reviewers
  can judge what remains visible without scrolling.

Render command, from repo root:

```bash
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-retrace-entry --screenshot=docs/design/retrace/retrace-entry-point.png --window-size=390,844 file://$PWD/docs/design/retrace/retrace-entry-point.svg
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-retrace-mid --screenshot=docs/design/retrace/retrace-map-mid-scrub.png --window-size=390,844 file://$PWD/docs/design/retrace/retrace-map-mid-scrub.svg
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-retrace-axxxl --screenshot=docs/design/retrace/retrace-map-mid-scrub-axxxl.png --window-size=390,844 file://$PWD/docs/design/retrace/retrace-map-mid-scrub-axxxl.svg
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-retrace-slider --screenshot=docs/design/retrace/retrace-slider-detail.png --window-size=390,390 file://$PWD/docs/design/retrace/retrace-slider-detail.svg
```
