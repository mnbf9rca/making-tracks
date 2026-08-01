# Snow System-Appearance Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep every Snow-material surface legible when the phone uses Dark appearance, without changing Snow's Light rendering.

**Architecture:** Apply the selected material's existing `MaterialTheme.colorScheme` at the app scene boundary so SwiftUI adaptive ink and system controls resolve in the same intrinsic mode as the material token sheet. Prove the behavior with a rendered UI oracle that captures the affected Appearance, Map & data, and Location cards under forced Light and Dark system appearances, requires AA foreground/background contrast, and requires byte-identical pixels inside the opaque card regions.

**Tech Stack:** Swift 6, SwiftUI, XCTest/XCUITest rendered-pixel helpers, Xcode 26.6, the `codex2` simulator seat.

## Global Constraints

- Target branch is `ios`; the branch starts from `origin/ios` `04e4201` and serves issue #589.
- The ratified mode model is theme-locked: Snow is Light and renders independently of system appearance (`docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md` §3).
- Consume `MaterialTheme.snow.colorScheme`; do not add a second Light-mode literal or change material tokens.
- Preserve the four legacy map-theme IDs and every T2.9 route, control, accessibility identifier, and layout.
- The rejected alternative is token-fixing only the three reported surfaces; that would leave the same adaptive-ink defect class armed elsewhere.
- The UI regression must fail if the scene preference is removed, exercise real rendered controls, and verify the three Rob-reported surfaces rather than inspect source text.
- Evidence is nondeterministic-content class because the live map remains visible around sheet corners: image SHA-256 pins reviewed bytes; card-region pixel measurements and Light/Dark difference counts are the reproduction oracle.
- All simulator work goes through `./scripts/sim-lock.sh --seat codex2 ...`; no caller supplies or copies a simulator UDID.

---

### Task 1: Add a rendered regression oracle before production code

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: `RenderedPixelRaster`, `launch`, `openExploreDoor`, `attachScreenshot`
- Produces: `testSnowSettingsAdaptiveInkIsLegibleAndInvariantAcrossSystemAppearances`
- Produces: a private capture helper returning one raster and opaque card frame for each of Appearance, Map & data, and Location

- [x] **Step 1: Add the Light/Dark capture model and test**

Add a small `@MainActor` capture value holding named `(raster, frame)` regions. Launch the fixture app twice with Snow pinned, once under Light and once under forced Dark. In each launch:

1. Open Settings → Appearance and capture the union of all four `settings.theme.*` rows.
2. Open Settings → Map & data and capture the union of `settings.downloads.allow-cellular`, the Pin size/value labels, and `settings.pin-size`.
3. Open Settings → Location with denied permission and capture the union of `Location off` and `settings.location.open-system`.

For every named region, require identical frames and `RenderedPixelRaster.differingPixelCount(..., tolerance: 0) == 0` between Light and Dark. In the Dark capture, count foreground pixels whose measured contrast against the sampled raised-card background reaches `4.5:1` for primary ink and `3:1` for secondary ink, require the target text frames to contain those pixels, and record each maximum observed text/background ratio. Appearance and Map & data additionally exercise their secondary-label frames. Exact Light/Dark equality is the regression invariant; the secondary floor preserves the existing Light rendering rather than broadening this urgent fix into a typography change.

Export six stable screenshots named `snow-theme-lock-{appearance,map-data,location}-{light,dark}`.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
./scripts/sim-lock.sh --seat codex2 xcodebuild \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testSnowSettingsAdaptiveInkIsLegibleAndInvariantAcrossSystemAppearances \
  test
```

Observed: FAIL before production changes because the forced-Dark Appearance card differed from the Light capture by 26,066 pixels. One test ran and failed on the intended rendered-invariance assertion.

---

### Task 2: Pin the material mode at the scene boundary

**Files:**
- Modify: `ios/App/Sources/MakingTracksApp.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: `MaterialTheme.snow.colorScheme`
- Produces: a scene-wide SwiftUI preferred color scheme matching the active Snow material

- [x] **Step 1: Add the minimal production fix**

Apply the material mode to one transparent group spanning the `WindowGroup` content:

```swift
WindowGroup {
    Group {
#if DEBUG
        if let variant = Self.debugDoorGlyphFixtureVariant {
            DoorGlyphEvidenceFixture(legacy: variant == "before")
        } else if Self.debugShowChipTargetFixture {
            ChipHitTargetFixture()
        } else {
            rootView
        }
#else
        rootView
#endif
    }
    .preferredColorScheme(MaterialTheme.snow.colorScheme)
}
```

This deliberately fixes the environment at the scene boundary. Do not edit the three affected Settings views or replace their adaptive colors with local tokens.

- [x] **Step 2: Run the focused test and verify GREEN**

Repeat Task 1 Step 2. Expected: 1 test passed, 0 failures, all three opaque card regions byte-identical across system appearances, with observed AA contrast.

- [x] **Step 3: Prove test teeth**

The pre-production RED is the neutered-fix run: with no scene preference, the Appearance region differed by 26,066 pixels. With the scene preference present, the unchanged oracle passed 1/1 and all three regions reported zero differing pixels. Record both results in the PR evidence.

---

### Task 3: Produce measured evidence and complete gates

**Files:**
- Create: `docs/design/design-system/regenerate-snow-theme-lock.sh`
- Create: `docs/design/design-system/snow-theme-lock-evidence.md`
- Create: `docs/design/design-system/snow-theme-lock-appearance-{light,dark}.png`
- Create: `docs/design/design-system/snow-theme-lock-map-data-{light,dark}.png`
- Create: `docs/design/design-system/snow-theme-lock-location-{light,dark}.png`
- Modify: `docs/design/design-system/README.md`
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`

**Interfaces:**
- Consumes: the focused UI test and `/private/tmp/making-tracks-artifacts`
- Produces: six reviewed captures, SHA-256 inventory, per-card ink/background counts, contrast ratios, and Light/Dark difference counts

- [ ] **Step 1: Add the deterministic regeneration wrapper**

The script must refuse runs outside `sim-lock.sh`, validate Xcode 26.6 / build 17F113, freeze the status bar, run only the focused test through `release-gate.sh`, copy the six captures, validate `1206×2622` dimensions, print SHA-256 values, and clear the status bar on exit. It must boot through the assigned wrapper path or state the locked-seat precondition.

- [ ] **Step 2: Record the evidence class and measurements**

The evidence record names the source head, simulator seat, SDK/runtime, capture test, dimensions, SHA-256 values, foreground/background pixel counts, observed contrast ratio for each affected card, and exact zero Light/Dark differing-pixel count within each opaque comparison frame. State that the surrounding live-map pixels are excluded from byte equality and that the images are implementation evidence, not a new design ruling.

- [ ] **Step 3: Run all required gates**

Run `swift test` and record the exact host count. Then run:

```bash
./scripts/sim-lock.sh --seat codex2 ./scripts/release-gate.sh
```

Record Release, unit, UI, warning, duration, and artifact-cleanup results. Verify no `.xcresult` remains and only the reusable seat DerivedData path was used.

- [ ] **Step 4: Review and publish**

Run the mandatory adversarial lenses, fix every surviving finding test-first, and request the task's reviewer tier. Re-ground on fresh `origin/ios`, verify the two-dot diff contains only #589 work, commit and push, then open a draft PR into `ios` with `sourcery-review`, `track-b-ios`, and `wp`. The body names #589, includes exact gates and review accounting, and carries this taste guess: scene-level material pin selected; three-surface token patch rejected because it leaves the defect class armed. Do not self-merge.
