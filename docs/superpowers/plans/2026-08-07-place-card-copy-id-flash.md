# Place-card Copy ID Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native place-card menu action that copies the exact place ID, visibly confirms `Copied` in the still-present menu for one second, announces success to VoiceOver, then dismisses and resets.

**Architecture:** Keep `PlaceCardMoreIconGlyph` as the visible SwiftUI label and replace only the interaction owner with a transparent `UIViewRepresentable`-backed `UIButton`. A main-actor confirmation controller owns the cancellable idle/confirming state machine through injected effects; the UIKit coordinator builds and updates the real `UIMenu`, then dismisses through the public `contextMenuInteraction` API.

**Tech Stack:** Swift 6, SwiftUI, UIKit `UIButton`/`UIMenu`/`UIAction`, XCTest/XCUITest, iOS 18+

## Global Constraints

- Copy the exact supplied `placeID`, including the `mt1_` prefix, with no wrapper, label, whitespace, or newline.
- Preserve `Add to list` first and preserve its current dismissal/navigation behavior.
- Keep the native menu presented after Copy activation; show disabled `Copied` plus a checkmark for one second; then dismiss and reset the next presentation to `Copy ID`.
- Post `Place ID copied.` before disabling the row so VoiceOver confirmation does not depend on focusability of a disabled menu item.
- Preserve the visible `PlaceCardMoreIconGlyph`, the at-least-44×44 target, the `More` label, and identifiers `place-card.more` / `place-card.add-to-list`; add `place-card.copy-id` and prove the live routes.
- Inject delay and side effects for deterministic unit tests; test code contains no sleeps.
- Add no toast, inline identifier, persistence, analytics, networking, model, detent, card-layout, or action-bar changes.
- UIKit uses only public API: `keepsMenuPresented`, `updateVisibleMenu`, and `dismissMenu`.

---

### Task 1: Deterministic confirmation controller

**Files:**
- Create: `ios/App/Sources/PlaceCard/PlaceCardMoreMenuButton.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify after production file exists: `ios/App/MakingTracks.xcodeproj/project.pbxproj` by running `xcodegen generate --spec ios/App/project.yml`

**Interfaces:**
- Produces: `@MainActor final class PlaceCardCopyIDConfirmationController`
- Produces: `enum PlaceCardCopyIDConfirmationState: Equatable { case idle, copied }`
- Consumes injected effects: `copy(String)`, `announce(String)`, `setState(State)`, `delay() async`, and `dismiss()`
- Produces methods: `activate(placeID:)` and `cancel()`

- [ ] **Step 1: Write failing controller tests**

Add main-actor XCTest cases that construct the wished-for controller with an `AsyncStream<Void>` gate. Independently assert these consumer-visible behaviors:

```swift
@MainActor
func testCopyIDConfirmationCopiesAndAnnouncesBeforeShowingCopiedState() async {
    var events: [String] = []
    let (delay, continuation) = AsyncStream<Void>.makeStream()
    let controller = PlaceCardCopyIDConfirmationController(
        copy: { events.append("copy:\($0)") },
        announce: { events.append("announce:\($0)") },
        setState: { events.append("state:\($0)") },
        delay: { for await _ in delay { return } },
        dismiss: { events.append("dismiss") }
    )

    controller.activate(placeID: "mt1_01RAW")

    XCTAssertEqual(events, [
        "copy:mt1_01RAW",
        "announce:Place ID copied.",
        "state:copied",
    ])
    continuation.finish()
}
```

Add separate tests that the menu is not dismissed before the fake delay completes, completion dismisses once and restores idle, `cancel()` prevents a stale completion from dismissing, a second activation while confirming cannot copy twice, and a long raw identifier remains byte-for-byte unchanged.

- [ ] **Step 2: Run the focused tests and verify RED**

Run the new `AppShellTests` selectors through:

```bash
./scripts/sim-lock.sh --seat codex3 xcodebuild test -project ios/App/MakingTracks.xcodeproj -scheme MakingTracks -configuration Debug -only-testing:MakingTracksTests/AppShellTests -derivedDataPath "$HOME/Library/Caches/making-tracks-gates/codex3"
```

Expected: compile failure because `PlaceCardCopyIDConfirmationController` and its state do not exist. Fix only test syntax until that is the sole failure.

- [ ] **Step 3: Implement the minimal controller**

Create the two-state main-actor controller. `activate(placeID:)` must synchronously call copy, announcement, and `setState(.copied)` in that order, then start one cancellable task awaiting the injected delay. On a still-current completion it calls dismiss, emits `.idle`, and clears the task. `cancel()` invalidates the generation, cancels the task, clears it, and emits `.idle` only when confirmation was active. Use a monotonically increasing integer generation, not randomness or wall-clock identity.

- [ ] **Step 4: Generate the Xcode project and verify GREEN**

Run `xcodegen generate --spec ios/App/project.yml`, then rerun the focused command. Expected: every new controller test passes with no warning.

- [ ] **Step 5: Commit**

```bash
git add ios/App/Sources/PlaceCard/PlaceCardMoreMenuButton.swift ios/App/Tests/AppShellTests.swift ios/App/MakingTracks.xcodeproj/project.pbxproj
git commit -m "feat(#375): add deterministic copy confirmation state"
```

---

### Task 2: Real native menu composition and interaction owner

**Files:**
- Modify: `ios/App/Sources/PlaceCard/PlaceCardMoreMenuButton.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Consumes: `PlaceCardCopyIDConfirmationController` and `PlaceCardCopyIDConfirmationState`
- Produces: `@MainActor struct PlaceCardMoreMenuContent` with `menu(state:onAddToList:onCopyID:) -> UIMenu`
- Produces: `struct PlaceCardMoreMenuButton: View`
- Produces: private `UIViewRepresentable` interaction view and main-actor UIKit coordinator

- [ ] **Step 1: Write failing native-menu tests**

Use real `UIMenu`/`UIAction` objects, not source scans or mocks. Assert the idle menu has exactly two children in literal order, titles `Add to list` then `Copy ID`, action identifiers `place-card.add-to-list` and `place-card.copy-id`, and only Copy carries `.keepsMenuPresented`. Assert the copied menu keeps Add unchanged and first, while the second row has title `Copied`, a checkmark image, `.disabled`, and `.keepsMenuPresented`.

Add a mounted-view structure test proving `PlaceCardMoreMenuButton` still contains exactly one `PlaceCardMoreIconGlyph`.

- [ ] **Step 2: Run focused tests and verify RED**

Run the Task 1 focused command. Expected: compile failures only for the missing menu builder and SwiftUI wrapper.

- [ ] **Step 3: Implement real menu composition**

Build the two `UIMenu` states with `.displayInline` and fixed ordering. Give `Add to list` ordinary dismissal. Give Copy `.keepsMenuPresented`. Give Copied `[.disabled, .keepsMenuPresented]` and `UIImage(systemName: "checkmark")`. Use `UIAction.Identifier("place-card.add-to-list")` and `UIAction.Identifier("place-card.copy-id")`.

Implement the transparent button representable. Configure `showsMenuAsPrimaryAction = true`, `preferredMenuElementOrder = .fixed`, clear visuals, `accessibilityLabel = "More"`, `accessibilityHint = "Shows place actions"`, and `accessibilityIdentifier = "place-card.more"`. The coordinator owns the controller, writes `UIPasteboard.general.string`, posts `UIAccessibility.post(notification: .announcement, argument: "Place ID copied.")`, updates the visible menu through `contextMenuInteraction?.updateVisibleMenu`, waits one production second with cancellable `Task.sleep(for:)`, and dismisses with `contextMenuInteraction?.dismissMenu()`.

Compose that transparent owner under the unchanged glyph in a 44×44 `ZStack`; the glyph uses `.allowsHitTesting(false)` so the UIKit button receives the tap.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Task 1 focused command. Expected: all controller, real-menu, and mounted-glyph tests pass with no warning.

- [ ] **Step 5: Commit**

```bash
git add ios/App/Sources/PlaceCard/PlaceCardMoreMenuButton.swift ios/App/Tests/AppShellTests.swift
git commit -m "feat(#375): build the native Copy ID menu"
```

---

### Task 3: Place-card integration and live-route proof

**Files:**
- Modify: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift:454-473`
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1790-1840`

**Interfaces:**
- Consumes: `PlaceCardMoreMenuButton(placeID:onAddToList:)`
- Preserves: `showListPicker = true`, `place-card.more`, `place-card.add-to-list`, and `PlaceCardMoreIconGlyph`
- Adds live route: `place-card.copy-id`

- [ ] **Step 1: Write failing mounted and UI tests**

Change the mounted structure test to require one `PlaceCardMoreMenuButton` inside `PlaceCardSheet.header`. Extend the existing fixture-card UI test without deleting its Add-to-list assertions:

1. Tap `place-card.more`; require both `place-card.add-to-list` and `place-card.copy-id` to exist.
2. Run the existing Add-to-list route and return.
3. Reopen More and tap `place-card.copy-id`.
4. Require the menu to remain presented with disabled `Copied` plus a checkmark, then use condition-based `waitForNonExistence` to require dismissal; do not call `sleep`.
5. Reopen and require `place-card.copy-id` again, proving reset.

Exact pasteboard payload remains a controller/unit boundary assertion; the UI test proves the real interaction owner and live menu route rather than depending on cross-process pasteboard behavior.

- [ ] **Step 2: Run focused tests and verify RED**

Run the Task 1 command plus the selected UI test through a repository-local only-testing file and `MT_RELEASE_GATE_ONLY_TESTING_FILE` under `sim-lock.sh`. Expected: mounted test fails because the header still contains SwiftUI `Menu`; UI test fails because `place-card.copy-id` does not exist.

- [ ] **Step 3: Integrate the wrapper**

Replace the header's SwiftUI `Menu` with:

```swift
PlaceCardMoreMenuButton(placeID: placeID) {
    showListPicker = true
}
```

Keep the existing `HStack`/`Spacer` shape. Do not duplicate external accessibility modifiers because the UIKit button owns the public label and identifier.

- [ ] **Step 4: Verify focused GREEN and identifier exposure**

Rerun the mounted and selected UI tests. Expected: More resolves as a button labelled `More`; both action identifiers resolve; Add to list still navigates; Copy visibly confirms before dismissing and resets. If UIKit does not expose `UIAction.Identifier` to XCTest, stop and add a tested public accessibility route before continuing—do not weaken or delete assertions.

- [ ] **Step 5: Run host and full iOS gates**

Run `swift test --package-path ios`, then `./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh`. Record exact Release/Debug build and test counts, zero failures/skips, zero warnings, result ownership, cleanup, and final two-way seat status.

- [ ] **Step 6: Commit**

```bash
git add ios/App/Sources/PlaceCard/PlaceCardSheet.swift ios/App/Tests/AppShellTests.swift ios/App/UITests/MakingTracksCoreLoopUITests.swift docs/superpowers/phases/pre-phase/tasks.md
git commit -m "feat(#375): wire Copy ID into the place card"
```

---

### Task 4: Review, evidence, and branch handoff

**Files:**
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Modify: issue #375 body
- Create or modify only if live evidence policy requires it: `docs/design/design-system/375-copy-id-implementation-evidence.md`

**Interfaces:**
- Consumes: ruled design hashes and exact gate-tested code head
- Produces: adversarial-review accounting, gate counts, and PR handoff to `ios`

- [ ] **Step 1: Run adversarial review**

Use the required independent critics across spec fidelity, UIKit lifecycle/concurrency correctness, accessibility/visual contract, privacy/untrusted-data posture, and test teeth. Cross-examine findings, fix survivors TDD, and mutation-check every behavioral fix.

- [ ] **Step 2: Verify completion evidence**

Run `git diff --check`, `python3 scripts/lint_agent_law.py`, and the full verification-before-completion checklist. Re-fetch `origin/ios`, verify ancestry, and review the two-dot stat for stale-base deletions.

- [ ] **Step 3: Publish and open the draft PR**

Push the signed exact head. Open a draft PR into `ios` naming #375, with `sourcery-review`, `track-b-ios`, and `wp`. Include actual test counts, review accounting, design hashes, feasibility path, and a `## Taste guesses` section stating that the reviewer-validated one-second interval is the ruled packet value and no alternative remains open.

- [ ] **Step 4: Process reviews and hand off**

Process all Sourcery and human/reviewer threads with technical verification. Update the pre-phase ledger and issue outcome, then AMQ planner with exact head, PR number, subtree hash, gates, and remaining merge ownership. Do not self-merge.
