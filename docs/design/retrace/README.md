# Retrace Map Mockups

Static design renders for the frozen Retrace/tracks redesign. These are design
assets only; no app code changes accompany them.

Rob's accepted direction:

- Retrace opens as a map view, not a hidden list state.
- Visited places remain individual pins.
- Scrubbing time makes dotted connection arcs glide across the map.
- Pins appear with a pulse as the scrubber reaches each visit.
- The slider must read as a real time slider, with Google Photos-style temporal
  affordance rather than a generic progress bar.
- The slider must scale to years of visits: fast scrubbing moves coarsely across
  years, then slowing zooms the timeline for fine positioning around nearby
  visits. Fast scrub advances through many visits per step and slow scrub advances
  through fewer; neither mode skips the arc drawing or pin arrival animation.
- Retrace can be filtered by list or lists and by place type. A filtered view is
  a shorter continuous track over the filtered visit set.
- The entry point must be obvious from the map.

Files:

- `retrace-entry-point.svg` / `.png` - obvious map-level entry into Retrace.
- `retrace-map-mid-scrub.svg` / `.png` - mid-scrub map state with arcs, pins,
  and the active time slider.
- `retrace-map-mid-scrub-axxxl.svg` / `.png` - same state at an accessibility
  text size, preserving the map and slider hierarchy.
- `retrace-slider-detail.svg` / `.png` - close-up of coarse and zoomed slider
  states for a separate long-history scoped track.

Validation notes:

- The map entry card treats Retrace as the primary destination; the old
  mapless Tracks drawer should not survive as a separate replay surface.
- The Retrace map has a visible filter affordance for list and place-type
  filtering, with active filters reflected as chips on the map surface.
- Active filters are presented as scope, not omissions. Filtered-out visits
  contribute no beats, no markers, no dwell, and no gap readout.
- Hidden places are still bridged silently and never surfaced as markers or
  counts.
- Retrace does not show unreached or hidden places as faded tappable pins, and
  it does not expose hidden-place counts.
- The dotted connection line is scaffolding: it stays behind the places, avoids
  the default navigation accent, stays bold/clear enough to read as one nice arc,
  and never dominates coloured pins.
- The mid-scrub render draws the visited arc at opacity 0.76. The **shipped**
  line opacity is **1.0**, ruled after this render against the paper-theme
  contrast floor (SC 1.4.11, 3:1); see wp-b6-tracks §1c. Hue (`#2d8c83`), width
  (6.2) and the dotted pattern are unchanged. The render is not re-cut for the
  alpha because the hierarchy it demonstrates is unaffected.
- Same-day reordering is represented as a continuous track.
- Autoplay advances one visit at a time with a uniform cadence and equal dwell
  per item. It is not derived from `visited_at` gaps or real-world temporal
  spacing.
- Manual scrubbing is velocity-sensitive: coarse movement advances through many
  visits on a year-scale event axis; slowing down expands the local visit cluster
  for precise selection without changing the event order. In both modes, reached
  paths still draw and pins still animate; fast scrub must not teleport state.
- Timeline zoom changes events per pixel, never the spacing rule: adjacent
  visits remain equally spaced whether they are minutes or months apart.
- Under filters, the timeline is re-indexed to only the filtered visit set:
  counters, markers, autoplay steps, dwell, and consecutive arcs all operate
  within that scoped set.
- Date labels decimate by available width. Coarse year-scale scrubbing shows
  sparse labels; the zoomed state can show more local labels.
- The slider-detail sheet intentionally uses a large long-history scope
  (`84 / 168`) so the fast-versus-slow zoom behavior is necessary and visible;
  the map mockups use a separate one-day filtered scope (`4 / 11`).
- The AXXXL render deliberately drops endpoint time labels from the slider row
  so the event control remains reachable and unclipped at the largest text size.
- Each phone-frame source includes a subtle fold/safe-area marker so reviewers
  can judge what remains visible without scrolling.

Render command, from repo root:

```bash
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-retrace-entry --screenshot=docs/design/retrace/retrace-entry-point.png --window-size=390,844 file://$PWD/docs/design/retrace/retrace-entry-point.svg
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-retrace-mid --screenshot=docs/design/retrace/retrace-map-mid-scrub.png --window-size=390,844 file://$PWD/docs/design/retrace/retrace-map-mid-scrub.svg
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-retrace-axxxl --screenshot=docs/design/retrace/retrace-map-mid-scrub-axxxl.png --window-size=390,844 file://$PWD/docs/design/retrace/retrace-map-mid-scrub-axxxl.svg
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-retrace-slider --screenshot=docs/design/retrace/retrace-slider-detail.png --window-size=390,640 file://$PWD/docs/design/retrace/retrace-slider-detail.svg
```
