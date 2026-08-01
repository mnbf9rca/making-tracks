# Explore destination-row press pulse implementation plan

**Goal:** Enroll Explore Settings/About destination glyphs in A5's ratified press pulse without
changing their resting rows, and publish live default/AX pressed evidence.

**Architecture:** A label-preserving `MaterialQuietRowButtonStyle` delegates to the same extracted
feedback modifier as `MaterialButtonStyleBody`. The production row and DEBUG evidence fixture share
the exact row content. A state-marked real-tap capture loop and fail-closed analyzer produce measured
rest/pressed evidence.

**Tech stack:** Swift 6, SwiftUI, XCTest/XCUITest, Bash, CoreGraphics/ImageIO, iOS Simulator seat CLI.

## Task 1 — claim, design, and baseline

**Files:**
- Modify `docs/superpowers/phases/pre-phase/tasks.md`
- Add `docs/superpowers/specs/2026-08-01-explore-row-press-pulse-design.md`
- Add this plan

- [x] Record the AMQ and ledger claim from fresh `origin/ios` `6b1d7b3`.
- [x] Ground the fixed-weight glyph, plain button style, A5 mechanism, T2.3 carried question, and
      A5 false-pressed evidence lesson.
- [x] Record the planner ruling for a label-preserving delegating adapter.
- [ ] Run the unchanged focused AppShell test as the baseline and record its count.

## Task 2 — invert the deadness contract (RED)

**Files:**
- Modify `ios/App/Tests/AppShellTests.swift`
- Modify `ios/Tests/DesignSystemTests/ControlStylesTests.swift`

- [ ] Rename/invert the fixed-medium test to require one mounted quiet-row pulse style.
- [ ] Require standard/rest rendering to equal the fixed-medium reference at default and AX5.
- [ ] Require emphasized rendering to differ from rest and increase measured glyph ink.
- [ ] Require the complete row content with resting feedback to equal the unmodified content.
- [ ] Add a DesignSystem assertion that the row adapter resolves `.symbolWeightPulse`.
- [ ] Run focused tests and record the expected compile/assertion RED before production changes.

## Task 3 — delegate the production press path (GREEN)

**Files:**
- Modify `ios/Sources/DesignSystem/ControlStyles.swift`
- Modify `ios/App/Sources/Map/MapDoorShell.swift`

- [ ] Extract the existing environment/scale/offset application into one internal modifier without
      changing `MaterialButtonStyleBody` ordering or output.
- [ ] Add `MaterialQuietRowButtonStyle` as a label-preserving adapter over
      `.symbolWeightPulse`.
- [ ] Extract `ExploreQuietDestinationRowContent`, mount the row adapter, and remove the expired
      fixed-medium override/comment.
- [ ] Run focused DesignSystem and AppShell tests to GREEN.
- [ ] Prove mutation teeth for plain style, wrong strategy, medium emphasized weight, and resting
      geometry; restore production after each RED.
- [ ] Run `swift test --package-path ios` before evidence work.

## Task 4 — add reproducible live-configuration evidence

**Files:**
- Modify `ios/App/Sources/MakingTracksApp.swift`
- Modify `ios/App/Sources/Map/MapDoorShell.swift`
- Modify `ios/App/Tests/AppShellTests.swift`
- Modify `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Add `docs/design/design-system/regenerate-explore-row-press-pulse.sh`
- Add `docs/design/design-system/measure-explore-row-press.swift`
- Add `docs/design/design-system/explore-row-press-pulse-evidence.md`
- Modify `docs/design/design-system/README.md`

- [ ] Add unique DEBUG fixture flags for Settings/About and a state marker outside the measured
      glyph crop; the fixture delegates to the production row style and shares production content.
- [ ] Add default/AX UI tests that export exact row frames and issue repeated real taps.
- [ ] Add an analyzer with hermetic self-tests, exact state-marker classification, bounded input
      validation, glyph ink/bounds measurements, and identical-crop rejection.
- [ ] Add a seat-only regeneration script with lock/destination validation, boot-on-demand,
      deterministic status bar, scoped task directories, focused test count extraction, atomic
      staged installation, and cleanup.
- [ ] Capture Settings/About rest/pressed frames at default and AX through seat `codex1`.
- [ ] Record measurements beside frames, SHA-256 values, exact head/toolchain/destination, evidence
      class, and one-command regeneration.
- [ ] Re-run regeneration and require identical outputs or explain the evidence class honestly.

## Task 5 — full gate and adversarial review

- [ ] Run Bash syntax, ShellCheck, agent-law lint, `git diff --check`, and analyzer self-tests.
- [ ] Run `swift test --package-path ios` and record exact counts.
- [ ] Run `./scripts/sim-lock.sh --seat codex1 ./scripts/release-gate.sh`; record Release/Debug,
      app-unit, and UI counts with zero warnings/failures; delete task xcresults and leave the seat
      FREE.
- [ ] Run the required independent script/evidence, test-quality, and integration reviews; count
      all raised/survived/fixed findings and cross-examine false positives.
- [ ] Rebase on the latest `origin/ios`; manually reconcile unique #575 fixture changes if present;
      rerun affected gates.

## Task 6 — publish and hand off

- [ ] Commit signed, push, and open a draft PR targeting `ios` with labels `sourcery-review`,
      `track-b-ios`, and `wp`.
- [ ] State the flipped assertion, label-preserving adapter ruling, exact evidence, full-gate counts,
      adversarial accounting, and any taste guesses in the PR body.
- [ ] Process every Sourcery/reviewer comment, resolve threads, and verify the live head/checks.
- [ ] Mark ready and send the exact merge-ready SHA to planner; planner retains merge ownership.
- [ ] After planner merge announcement, rewrite #595 body first, close it, and verify final state.
