# Snow system-appearance lock implementation evidence

These runtime captures prove issue #589's implementation. They are not a new design ruling: the mode model is already ratified as theme-locked, with Snow intrinsically Light regardless of the system appearance.

## Captures

| Surface | Forced system appearance | Dimensions | SHA-256 |
|---|---|---:|---|
| [Appearance](snow-theme-lock-appearance-light.png) | Light | 1206×2622 px | `2acc73a7fa15a29925c127cb51e6506467a4dfa797ae0e0a7eb4a8cbf7bfd54e` |
| [Appearance](snow-theme-lock-appearance-dark.png) | Dark | 1206×2622 px | `2acc73a7fa15a29925c127cb51e6506467a4dfa797ae0e0a7eb4a8cbf7bfd54e` |
| [Map & data](snow-theme-lock-map-data-light.png) | Light | 1206×2622 px | `8a3842fd012aa10a2579e85ea383289ebe4801a1c055f6b07bbe877826726749` |
| [Map & data](snow-theme-lock-map-data-dark.png) | Dark | 1206×2622 px | `8a3842fd012aa10a2579e85ea383289ebe4801a1c055f6b07bbe877826726749` |
| [Location](snow-theme-lock-location-light.png) | Light | 1206×2622 px | `cfe9a3398a3a0357c710d6e0a0767bc7b2f102189ec610fc7708d8eb0016de48` |
| [Location](snow-theme-lock-location-dark.png) | Dark | 1206×2622 px | `cfe9a3398a3a0357c710d6e0a0767bc7b2f102189ec610fc7708d8eb0016de48` |

The paired full-frame hashes happen to be identical in this run. The executable regression contract is narrower and stable: byte equality is required inside inclusive raster envelopes covering opaque material-card regions, while surrounding live-map pixels are excluded because their content is nondeterministic. A DEBUG-only bypass also re-renders the legacy behavior in the same run: legacy Light must match fixed Light exactly, and legacy Dark must differ materially from fixed Dark.

## Rendered measurements

All coordinates are app-window points. Pixel counts are native 3× screenshot pixels. Primary counts meet at least 4.5:1 against Snow `surfaceRaised`; secondary counts meet at least 3:1 and preserve the exact existing Light rendering. Each foreground assertion requires raised-surface pixels to outnumber qualifying ink pixels inside that same text frame, rather than assuming a white background from elsewhere in the card.

| Surface | Compared card frame | Fixed Light/Dark diff | Legacy/fixed Light diff | Legacy/fixed Dark diff | Primary pixels ≥4.5:1 | Primary local background | Secondary pixels ≥3:1 | Secondary local background |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| Appearance | `12.00,214.33 378.00×288.00` | 0 | 0 | 26,066 | 3,580 | 17,075 | 1,292 | 9,000 |
| Map & data | `12.00,214.33 378.00×589.33` | 0 | 0 | 36,157 | 1,707 | 8,698 | 1,077 | 6,355 |
| Location | `29.00,230.33 345.00×52.00` | 0 | 0 | 4,242 | 3,186 | 18,119 | — | — |

Primary maximum contrast is 21.000:1 on every surface. Secondary maximum contrast is 3.439:1 on Appearance and Map & data. The broad raised-surface counts remain 904,429, 652,274, and 155,660 respectively.

The secondary maximum is recorded rather than presented as body-text AA. Issue #589 requires no Light-mode visual change; its regression invariant is that Dark renders the already-legible Light result exactly. Raising the existing Light secondary treatment is separate token/typography scope.

The machine-readable source is [`snow-theme-lock-measurements.txt`](snow-theme-lock-measurements.txt), SHA-256 `0a425a435f00b83f1da5ecf7230182e3aead9dacbb6d4da423238d1b2d8dedff`.

## Provenance and gate

- Production preference introduced in commit `b0c597ad58e29f29bd21a6d33169b96b6c4f013d` on `wp-589-dark-mode-fix`, based on `origin/ios` `04e4201`.
- Evidence source head: `2a16556d421533cc2449d54b3f69b142f14e8964` (production preference, DEBUG bypass, rendered oracle, and regeneration harness).
- Test: `MakingTracksCoreLoopUITests.testSnowSettingsAdaptiveInkIsLegibleAndInvariantAcrossSystemAppearances`.
- Harness: XCTest `XCUIScreen.main.screenshot()` under Xcode 26.6 (17F113).
- Device: locked `codex2` iPhone 17 simulator, iOS 26.5 (23F77), 402×874 pt @3×.
- Status bar: frozen at 09:41 with Wi-Fi, four cellular bars, and 100% charged battery.
- Focused Release gate: Release build and Debug build-for-testing succeeded with warnings-as-errors; 1 UI test passed, 0 failed in 140.252 seconds.
- Test teeth: before the DEBUG-only bypass was wired, the strengthened oracle failed on its intended legacy-Dark assertion. With the bypass present, the same passing run reproduces 26,066, 36,157, and 4,242 changed pixels across Appearance, Map & data, and Location while proving zero fixed Light/Dark differences and zero legacy/fixed Light differences.

## Regeneration

Run from the repository root. The script refuses to run outside the assigned simulator lock or under a different Xcode version, uses `$HOME/Library/Caches/making-tracks-gates/codex2` by default, isolates exports by simulator (safe under the per-simulator lock), performs the focused Release gate, extracts the test counts, removes its exact result bundle, validates every source image before installing tracked output, and prints measurements plus SHA-256 digests.

```bash
./scripts/sim-lock.sh --seat codex2 \
  ./docs/design/design-system/regenerate-snow-theme-lock.sh
```
