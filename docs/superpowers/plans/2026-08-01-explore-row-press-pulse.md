# Explore destination-row press pulse implementation plan

**Goal:** Enroll Explore Settings/About destination glyphs in A5's ratified press pulse without
changing their resting rows, and publish live default/AX pressed evidence.

**Architecture:** A label-preserving `MaterialQuietRowButtonStyle` delegates to the same extracted
feedback modifier as `MaterialButtonStyleBody`. The DEBUG fixture renders the actual production row;
its production style body latches only from a real configuration press edge. A handshaken capture
loop and fail-closed analyzer produce measured rest/pressed evidence.

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
- [x] Run the unchanged focused AppShell test as the baseline and record its count.

## Task 2 — invert the deadness contract (RED)

**Files:**
- Modify `ios/App/Tests/AppShellTests.swift`
- Modify `ios/Tests/DesignSystemTests/ControlStylesTests.swift`

- [x] Rename/invert the fixed-medium test to require one mounted quiet-row pulse style.
- [x] Require standard/rest rendering to equal the fixed-medium reference at default and AX5.
- [x] Require emphasized rendering to differ from rest and increase measured glyph ink.
- [x] Require the complete row content with resting feedback to equal the unmodified content.
- [x] Add a DesignSystem assertion that the row adapter resolves `.symbolWeightPulse`.
- [x] Run focused tests and record the expected compile/assertion RED before production changes.

## Task 3 — delegate the production press path (GREEN)

**Files:**
- Modify `ios/Sources/DesignSystem/ControlStyles.swift`
- Modify `ios/App/Sources/Map/MapDoorShell.swift`

- [x] Extract the existing environment/scale/offset application into one internal modifier without
      changing `MaterialButtonStyleBody` ordering or output.
- [x] Add `MaterialQuietRowButtonStyle` as a label-preserving adapter over
      `.symbolWeightPulse`.
- [x] Extract `ExploreQuietDestinationRowContent`, mount the row adapter, and remove the expired
      fixed-medium override/comment.
- [x] Run focused DesignSystem and AppShell tests to GREEN.
- [x] Prove mutation teeth for plain style, wrong strategy, medium emphasized weight, and resting
      geometry; restore production after each RED.
- [x] Run `swift test --package-path ios` before evidence work.

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

- [x] Add unique DEBUG fixture flags for Settings/About and markers outside the measured glyph
      crop; the fixture renders the actual production row and its real prominence.
- [x] Add default/AX UI tests that export exact row frames, handshake a resting capture, issue
      repeated real taps, and require at least one real configuration press edge.
- [x] Add an analyzer with hermetic end-to-end self-tests, exact state-marker classification,
      bounded input validation, glyph ink/bounds measurements, and identical-crop rejection.
- [x] Add a seat-only regeneration script with lock/destination validation, boot-on-demand,
      deterministic status bar, scoped task directories, focused test count extraction, atomic
      staged installation, and cleanup.
- [x] Capture Settings/About rest/pressed frames at default and AX through seat `codex1`.
- [x] Record measurements beside frames, SHA-256 values, exact head/toolchain/destination, evidence
      class, and one-command regeneration.
- [x] Re-run regeneration and require identical outputs or explain the evidence class honestly.

## Task 5 — full gate and adversarial review

- [x] Run Bash syntax, ShellCheck, `git diff --check`, and analyzer self-tests.
- [x] Run `swift test --package-path ios` and record exact counts.
- [x] Run `./scripts/sim-lock.sh --seat codex1 ./scripts/release-gate.sh`; at gate-tested head
      `e2df6a87c99520a9613ce208972d48e63da27f86`, Release and Debug build-for-testing passed,
      app unit passed 251/251, UI passed 112/112, and the result passed 363/363 with zero
      failures, skips, expected failures, retries, or warnings-as-errors. The test phase took
      3,020s; the #602 Snow path passed in 63.911s. The Release binary contained none of
      `materialQuietRowPressEvidenceLatch`, `PressEvidence`, or `EvidenceLatch`; the task result
      bundle was removed after count extraction and seat `codex1` was verified FREE.
- [x] Run the required independent script/evidence, test-quality, and integration reviews. The
      three lenses raised 7 unique findings (4 Important, 3 Minor); all 7 were fixed, 0 survived,
      and all three re-reviews found 0 new Critical or Important issues. Cross-examination rejected
      only an attempted whole-raster semibold oracle because the ratified press family also scales;
      the exact medium-to-semibold mapping remains pinned directly.
- [x] Rebase on `origin/ios` `429e51f50a9dbed2221f6fa366ada9dba4e7c18f`; preserve #575's
      fixture and #602's focus/appearance hardening while reconciling the shared fixture routing,
      regenerate all #595 evidence, and rerun the package and host gates. The refreshed packet's
      eight PNGs and four measurement reports remained byte-identical; only provenance metadata
      changed to the rebased source head and capture interval.

## Task 6 — publish and hand off

- [ ] Commit signed, push, and open a draft PR targeting `ios` with labels `sourcery-review`,
      `track-b-ios`, and `wp`.
- [ ] State the flipped assertion, label-preserving adapter ruling, exact evidence, full-gate counts,
      adversarial accounting, and any taste guesses in the PR body.
- [ ] Process every Sourcery/reviewer comment, resolve threads, and verify the live head/checks.
- [ ] Mark ready and send the exact merge-ready SHA to planner; planner retains merge ownership.
- [ ] After planner merge announcement, rewrite #595 body first, close it, and verify final state.
