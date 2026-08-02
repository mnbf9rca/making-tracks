# UI-Test Concurrency Seams Implementation Plan

**Goal:** Remove the UI-test harness races and sibling blind waits that block trustworthy simulator-concurrency measurement.

**Architecture:** Keep the harness policies in `MakingTracksCoreLoopUITests.swift` as pure helpers with thin XCUI/environment adapters. Scope all artifacts by simulator identity when available, and route list acquisition and fixture opening through bounded condition-driven observations with diagnostic state.

## Constraints

- UI-test code only; no app-source or product-behaviour changes.
- No filename allowlist, sleeps, unbounded retries, or raw simulator commands.
- Every simulator action runs through `./scripts/sim-lock.sh --seat codex3`.
- #600 remains paused until this prerequisite merges; its matrix restarts at cap-2 repetition 1.

### Task 1: Prove helper contracts RED

- Add artifact-selector tests for distinct simulator IDs, nil/empty/whitespace fallback, and environment precedence.
- Add scroll-policy tests for zero-action success, bounded success, and exact exhaustion with final state.
- Run only those tests through the codex3 simulator wrapper and record the expected missing-symbol build failure.

### Task 2: Implement helpers GREEN

- Add `UITestArtifactDirectorySelector` with the simulator-scoped and fallback paths.
- Add the scroll observation/result types and bounded closure-driven acquirer.
- Re-run the helper tests and commit the completed RED/GREEN cycle.

### Task 3: Integrate the runtime seams

- Replace `uiTestArtifactDirectory(for:)` prefix policy with the selector and environment identity precedence.
- Route the custom-list root row through the bounded helper with a ten-scroll limit.
- Route generic existence scrolling through the same bounded helper while preserving its five-scroll contract.
- On exhaustion, report the row predicate, bound, final observation, and #600 cap-2 context.
- Make the primary fixture opener wait for reset state and its stable accessibility pin, then boundedly reposition the map only while AX fixture chrome obscures that pin; retain one repeated pre-fix morphology result as RED evidence.
- Run focused custom-list and place-card morphology tests.

### Task 4: Verify teeth and full behavior

- Neuter simulator scoping, observe the selector regression test fail, then restore and pass.
- Neuter bounded scrolling or accept a non-hittable state, observe the scroll regression test fail, then restore and pass.
- Run `swift test`, `git diff --check`, and the complete solo Release gate on codex3.
- Record exact build/test counts and remove task result bundles under repository disk-hygiene rules.

### Task 5: Review and publish

- Request independent AMQ review of the exact code head and address surviving findings.
- Open a draft PR into `ios`, apply `sourcery-review`, `track-b-ios`, and `wp`, and disposition Sourcery feedback.
- Update the issue and task ledger with exact evidence; planner retains merge ownership.
