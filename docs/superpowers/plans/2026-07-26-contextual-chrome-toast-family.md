# Contextual Chrome Toast Family Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the map’s download progress, location-off notice, nearby prompt, and hide-undo toast onto the ratified `DesignSystem` toast/progress family without changing when they appear or what their actions do.

**Architecture:** Add one focused app source file containing four small adapters over `MaterialToast`; each adapter owns only presentation and receives behavior through closures. `MapScreen` remains the state/lifecycle authority for download routing, location permission, nearby selection/suppression, and hide-toast auto-dismiss. Concrete XCUITests pin the live controls’ 44×44 targets, the mounted download accessibility value, identifiers, routing, and undo semantics.

**Tech Stack:** Swift 6, SwiftUI, UIKit interoperability removal, XCTest/XCUITest, XcodeGen, static HTML/CSS rendered with headless Chrome.

## Global Constraints

- Target iOS 18+ and Swift 6 strict concurrency.
- Consume `MaterialTheme.snow`, `MaterialToast`, `MaterialProgressState`, `MaterialFilledButtonStyle`, `MaterialTonalButtonStyle`, and `MaterialQuietButtonStyle`; define no colour or font literal in the adopting views.
- Preserve identifiers `map.download-progress`, `map.location-settings`, `map.nearby-prompt`, `map.nearby-prompt.seen`, `map.nearby-prompt.dismiss`, and `place-card.hide.undo`.
- Preserve the download deep link, Settings action, nearby Seen/Dismiss behavior, hide Undo behavior, and five-second hide-toast auto-dismiss.
- Every interactive control mounted in the four adapters must expose at least a 44×44 point live hit target.
- The mounted download surface must expose its derived percentage as an accessibility value.
- Use one filled action at most: nearby “Seen it” is filled; location Settings is quiet; hide Undo is tonal.
- Reduce Transparency must flow through `MaterialToast`, which swaps material blur for solid `surface`.
- Keep AC23 visibility guards in `MapScreen`: no adapter appears without its existing state predicate.
- Extract all four view bodies from `MapScreen.swift` into `MapContextualChrome.swift`; do not move business state or timers.
- Regenerate `ios/App/MakingTracks.xcodeproj` after adding the app source file.
- Ship 390×844 default and AX renders with HTML sources, showing all four contextual states.
- Run `swift test --package-path ios` and `./scripts/sim-lock.sh ./scripts/release-gate.sh`; CI never replaces either host gate.

---

### Task 1: Add live RED coverage for the inherited obligations

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: the existing UI-test launch fixtures for hidden toast, offline progress, denied location, and nearby prompt.
- Produces: concrete frame assertions and the mounted download accessibility-value assertion.

- [ ] **Step 1: Add one reusable test-only target assertion**

Add this helper inside `MakingTracksCoreLoopUITests`:

```swift
private func assertMinimumInteractiveTarget(
    _ element: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(element.frame.width, 44, file: file, line: line)
    XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
}
```

The production break caught is a visually present control whose live tappable frame is smaller than the platform minimum.

- [ ] **Step 2: Pin the hide Undo control**

In `testHiddenToastUndoRestoresHiddenPlace`, capture `app.buttons["place-card.hide.undo"]`, wait for it, call `assertMinimumInteractiveTarget`, then tap it. Retain the existing restoration assertion.

- [ ] **Step 3: Pin the mounted download surface**

In `testOfflineProgressChipDeepLinksToOfflineMaps`, assert:

```swift
XCTAssertEqual(progressChip.label, "Offline maps download")
XCTAssertEqual(progressChip.value as? String, "42%")
assertMinimumInteractiveTarget(progressChip)
```

Retain the tap and Offline maps destination assertions. The test catches a call site that displays a percentage as text but fails to mount it as an accessibility value.

- [ ] **Step 4: Pin location Settings**

In `testLocateMeChromeExplainsWhenLocationIsDenied`, require `app.buttons["map.location-settings"]` and call `assertMinimumInteractiveTarget`. Remove the fallback to `otherElements`; the extracted control is a real SwiftUI button.

- [ ] **Step 5: Pin both nearby-prompt controls**

In `testLocateMeShowsNearbyPromptForFixturePlace`, assert minimum targets for `map.nearby-prompt.seen` and `map.nearby-prompt.dismiss` before tapping Seen. Retain the prompt disappearance and visit-count assertions.

- [ ] **Step 6: Pin nearby Dismiss behavior**

Add `testNearbyPromptDismissSuppressesPrompt` using the same simulated-authorized location fixture as `testLocateMeShowsNearbyPromptForFixturePlace`. Tap `map.locate-me`, wait for `map.nearby-prompt`, tap `map.nearby-prompt.dismiss`, then assert the prompt remains absent for two seconds and the visit count stays zero.

- [ ] **Step 7: Run the five tests and verify RED**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testHiddenToastUndoRestoresHiddenPlace \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testOfflineProgressChipDeepLinksToOfflineMaps \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLocateMeChromeExplainsWhenLocationIsDenied \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLocateMeShowsNearbyPromptForFixturePlace \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testNearbyPromptDismissSuppressesPrompt
```

Expected: failures for sub-44pt controls and the missing mounted `42%` accessibility value. A launch/setup error is not a valid RED; fix test setup until the assertions fail against the existing product.

---

### Task 2: Extract the four toast adapters

**Files:**
- Create: `ios/App/Sources/Map/MapContextualChrome.swift`
- Modify: `ios/App/MakingTracks.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `MaterialToast`, `MaterialToastSurfaceAction`, `MaterialProgressState`, and the three material button styles.
- Produces:
  - `MapDownloadProgressToast(progress:onOpenOfflineMaps:)`
  - `MapLocationOffToast(onOpenSettings:)`
  - `MapNearbyPromptToast(message:onSeen:onDismiss:)`
  - `MapHiddenUndoToast(onUndo:)`

- [ ] **Step 1: Add the download adapter**

Implement:

```swift
struct MapDownloadProgressToast: View {
    let progress: OfflineDownloadProgress
    let onOpenOfflineMaps: () -> Void

    var body: some View {
        MaterialToast(
            message: progress.isWaitingForConnectivity
                ? "Offline maps \(progress.statusText)"
                : "Offline maps",
            surfaceAction: MaterialToastSurfaceAction(
                accessibilityLabel: "Offline maps download",
                accessibilityHint: "Opens Offline maps",
                accessibilityIdentifier: "map.download-progress",
                action: onOpenOfflineMaps
            ),
            leadingSystemImage: "arrow.down.circle",
            progressState: .percentage(progress.percentComplete)
        )
    }
}
```

The closed whole-surface initializer owns the 44pt surface target and derives visible/spoken percentage from the same `MaterialProgressState`.

- [ ] **Step 2: Add the location-off adapter**

Implement `MapLocationOffToast` with `MaterialToast(message: "Location is off", primaryActionAccessibilityIdentifier: "map.location-settings", actionContent:)`. Its action content is a SwiftUI `Button` with a monochrome `gearshape.fill` label, accessibility label `Settings`, hint `Opens location settings`, and `MaterialQuietButtonStyle`.

This deliberately retires `LocationSettingsButton: UIViewRepresentable`; the wrapper has no behavior beyond forwarding a closure and is the source of the fixed 68×16 target.

- [ ] **Step 3: Add the nearby adapter**

Implement `MapNearbyPromptToast` with:

- `message` passed verbatim;
- custom primary action identifier `map.nearby-prompt.seen`;
- a `Button("Seen it", action: onSeen)` using `MaterialFilledButtonStyle`;
- built-in dismiss action `onDismiss`;
- dismiss label `Dismiss nearby prompt`;
- dismiss identifier `map.nearby-prompt.dismiss`;
- container identifier `map.nearby-prompt`.

The filled style owns the Seen target; `MaterialToastDismissButton` owns the dismiss target.

- [ ] **Step 4: Add the undo adapter**

Implement `MapHiddenUndoToast` with message `Hidden — Undo` and a custom `Button("Undo", action: onUndo)` using `MaterialTonalButtonStyle`, identified as `place-card.hide.undo`.

Tonal is intentional: recovery stays visually discoverable without consuming the one filled-action slot.

- [ ] **Step 5: Regenerate the project**

Run:

```bash
cd ios/App && xcodegen generate
```

Verify the generated project contains `MapContextualChrome.swift` in the `MakingTracks` app target and no unrelated project setting changed.

---

### Task 3: Replace the four bespoke `MapScreen` bodies without moving behavior

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift`

**Interfaces:**
- Consumes: Task 2’s four adapter views.
- Preserves: `AppShellModel.openOfflineMapsDeepLink`, `openLocationSettings`, `handleNearbyPromptSeen`, nearby suppression, `showHiddenToast`, `undoHiddenToast`, and the five-second dismiss task.

- [ ] **Step 1: Replace download progress**

In `shellChrome`, replace the bespoke button with:

```swift
MapDownloadProgressToast(
    progress: offlineDownloadProgress,
    onOpenOfflineMaps: appShell.openOfflineMapsDeepLink
)
```

Keep the existing `activeListMap == nil` and `currentOfflineDownloadProgress != nil` guards.

- [ ] **Step 2: Replace the location banner**

Make `locationOffBanner` return:

```swift
MapLocationOffToast(onOpenSettings: openLocationSettings)
```

Delete `LocationSettingsButton` from the bottom of `MapScreen.swift`.

- [ ] **Step 3: Replace the nearby prompt body**

In the existing conditional overlay, instantiate:

```swift
MapNearbyPromptToast(
    message: "You're near \(prompt.name) — seen it?",
    onSeen: { handleNearbyPromptSeen(prompt) },
    onDismiss: {
        suppressedNearbyPromptPlaceIDs.insert(prompt.placeID)
    }
)
```

Delete `nearbyPromptView(for:)`. Do not alter `nearbyPromptCandidate` or suppression semantics.

- [ ] **Step 4: Replace the undo body**

In the hidden-toast overlay, instantiate:

```swift
MapHiddenUndoToast {
    Task { await undoHiddenToast() }
}
```

Delete `hiddenToastView(for:)`. Do not alter `showHiddenToast`, `undoHiddenToast`, cancellation, or the five-second task.

- [ ] **Step 5: Confirm the bespoke styling is gone from the four migrated sites**

Run:

```bash
rg -n 'map\.download-progress|LocationSettingsButton|map\.nearby-prompt|place-card\.hide\.undo|\.borderedProminent|\.bordered|ultraThinMaterial|regularMaterial' \
  ios/App/Sources/Map/MapScreen.swift \
  ios/App/Sources/Map/MapContextualChrome.swift
```

Expected: identifiers remain in `MapContextualChrome.swift`; `LocationSettingsButton` and the four old material/button recipes are absent. Unrelated material/button sites elsewhere in `MapScreen.swift` are out of this task.

---

### Task 4: Verify GREEN and prove behavior did not drift

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Test: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: live evidence for AC11, AC12, AC23, AC26, and AC29.

- [ ] **Step 1: Run the focused app-unit suite**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MakingTracksTests/AppShellTests
```

Expected: all `AppShellTests` pass with zero failures.

- [ ] **Step 2: Re-run the five focused UI tests**

Run Task 1 Step 7’s command.

Expected: all five pass; each mounted control clears 44×44, download progress exposes `42%` as its value, and nearby Dismiss suppresses without recording a visit.

- [ ] **Step 3: Run the existing lifecycle regressions**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testHiddenToastAutoDismissesWithoutUnhidingPlace \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testHiddenToastUndoRestoresHiddenPlace \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testCardVisitStateSuppressesNearbyPromptWithoutViewportRefresh \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testNearbyPromptDismissSuppressesPrompt
```

Expected: the undo toast still disappears without mutating hidden state, Undo still restores, and nearby suppression remains immediate.

- [ ] **Step 4: Prove test teeth**

Perform and immediately restore these mutations one at a time:

1. Pass `progressState: nil` in `MapDownloadProgressToast`; the download test must fail on missing `42%` value.
2. Replace the location action’s material style with a 16pt fixed frame; the location test must fail its height assertion.
3. Remove the nearby dismiss callback; the existing prompt-dismiss path must fail when exercised.

After restoring each mutation, rerun the affected focused test and confirm green.

---

### Task 5: Produce the four-state visual evidence

**Files:**
- Create: `docs/design/design-system/t1.7-contextual-chrome.html`
- Create: `docs/design/design-system/t1.7-contextual-chrome.png`
- Create: `docs/design/design-system/t1.7-contextual-chrome-ax.html`
- Create: `docs/design/design-system/t1.7-contextual-chrome-ax.png`
- Modify: `docs/design/design-system/README.md`

**Interfaces:**
- Consumes: the exact Snow tokens, 16pt toast radius, hairline stroke, 3pt progress bar, button hierarchy, and copy from production.
- Produces: reviewable 390×844 default and AX evidence covering download, location-off, nearby, and undo states.

- [ ] **Step 1: Author the default render**

Build a 390×844 proof sheet over the Snow map treatment with four labeled contextual states:

- Offline maps with arrow icon, `42%`, thin accent progress, and whole-surface affordance;
- Location is off with quiet Settings action;
- nearby prompt with filled Seen it and 44pt dismiss;
- Hidden — Undo with tonal Undo.

Mark the fold and use exact production spacing, shape, and token values.

- [ ] **Step 2: Author the AX render**

Keep the 390×844 canvas, use accessibility-sized text and long representative copy, and show the `ViewThatFits` stacked fallback. Controls remain at least 44pt and no text clips.

- [ ] **Step 3: Render both PNGs**

Use headless Chrome with dedicated `/private/tmp/chrome-t1-7-*` profiles, `--force-device-scale-factor=1`, `--hide-scrollbars`, `--window-size=390,844`, and the worktree’s `file://` URLs.

- [ ] **Step 4: Inspect both images**

Open both PNGs at original resolution. Verify exact 390×844 dimensions, all four states visible, fold marked, no clipping, and clear filled/tonal/quiet hierarchy.

- [ ] **Step 5: Link the evidence**

Add both renders and sources to `docs/design/design-system/README.md` under the Phase 1 implementation evidence.

---

### Task 6: Full verification, adversarial review, and handoff

**Files:**
- Modify: `docs/superpowers/phases/phase-1/tasks.md`
- Modify: the T1.7 PR body on GitHub.

**Interfaces:**
- Consumes: the complete branch.
- Produces: verified counts, clean review accounting, a pushed PR into `ios`, and dual-channel checkpoints.

- [ ] **Step 1: Re-ground**

Run:

```bash
git fetch origin ios
git merge-base --is-ancestor origin/ios HEAD
```

If the ancestry check fails, merge `origin/ios` as a bare mutation, rerun all affected gates, and re-check the diff.

- [ ] **Step 2: Run host tests**

Run:

```bash
swift test --package-path ios
```

Record the executed count and zero failures.

- [ ] **Step 3: Run the full gate**

Run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Record Release build status plus app-unit and UI-test counts. Extract counts, then remove the `.xcresult` bundle immediately.

- [ ] **Step 4: Run adversarial critics**

Run independent read-only critics for spec fidelity, internal coherence/correctness, accessibility/test quality, and threat-model-calibrated security. Cross-examine each finding, fix every surviving Critical/Important issue, and prove teeth for each fix.

- [ ] **Step 5: Review scope**

Run:

```bash
git diff --check
git diff --stat origin/ios..HEAD
git status --short --branch
```

The two-dot diff must contain only T1.7 source, tests, plan, renders, generated project entry, and task-ledger changes.

- [ ] **Step 6: Commit and push**

Use imperative, signed commits. Push with:

```bash
git push origin HEAD
```

Verify the remote head matches local HEAD.

- [ ] **Step 7: Open the draft PR**

Open a draft PR into `ios` serving issue #468 and T1.7. Include:

- exact test counts;
- adversarial findings raised/survived/fixed;
- all four render links;
- explicit confirmation of preserved identifiers and auto-dismiss semantics;
- `## Taste guesses` naming tonal Undo versus the rejected quiet alternative.

Apply `sourcery-review`, `track-b-ios`, and `wp` immediately. Do not apply `greptile-review`.

- [ ] **Step 8: Request design review and process feedback**

Request Opus review through AMQ, process Sourcery and Opus findings with technical rigor, and resolve every thread. Apply the per-PR Sourcery error evidence protocol only if the service actually fails.

- [ ] **Step 9: Deliver dual-channel checkpoints**

At `tests green`, `PR open`, `review clean`, and `ready-to-merge`, update the T1.7 Status line and send the same transition to fable via AMQ. Fable owns merge execution.
