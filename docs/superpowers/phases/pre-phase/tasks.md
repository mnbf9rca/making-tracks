# Pre-phase task ledger

Status ledger for issue-routed work while no phase is active (coordination.md → Supervision-loop contract → *No active phase*). Same rules as a phase `tasks.md`: builders append a status line per transition; fable reads it on the supervision loop. Stall threshold: 45 minutes.

Status vocabulary: `claimed → branch → tests green → PR open → review clean → ready-to-merge` (plus `blocked: <reason>` / `released`).

Format: one line per transition, newest last:
`- <UTC timestamp> <handle> #<issue> <status> [note]`

## Active

- 2026-07-29T13:35Z codex3 #497 claimed — rewrite `sim-lock.sh` for per-simulator locking plus a two-gate global cap; fold #544's new-host process-fixture repair into the same row
- 2026-07-29T13:40Z codex3 #497 branch — `wp-infra-sim-concurrency` at `bde9c0a21beaa90ab2e358b2da2e966567ea9fac`; #497 inode-swap evidence grounded and baseline harness recorded at 8 passed / 3 failed after installing Homebrew `flock`
- 2026-07-29T13:44Z codex3 #497 branch — baseline correction: sandboxed `pgrep` cannot enumerate host processes; unchanged harness passes 11 passed / 0 failed with host access, so #544 is not a repository defect and is queued for not-planned closure
- 2026-07-29T14:01Z codex3 #497 tests green — host harness 16 passed / 0 failed on three consecutive runs; Bash syntax, ShellCheck and agent-law lint clean; teeth proven for same-sim serialization, two-slot cap, stable inode, fail-closed process inspection (#545), required destination and per-UDID DerivedData
- 2026-07-29T14:35Z codex3 #497 tests green — adversarial fixes at `c13e6e3` plus follow-up working tree: host harness 33 passed / 0 failed and established release-gate suite 23 passed / 0 failed; exact lock identity, fresh-seat status, CI result ownership, Bash 3.2, fleet-exclusive cap-1 admission, flock/lsof failures and concurrency-test readiness are pinned; syntax, ShellCheck, agent-law lint and diff check clean
- 2026-07-29T15:50Z codex3 #497 tests green — gate-tested code head `e51ad6a`: host lock harness 38 passed / 0 failed on three consecutive runs, release-gate script suite 23 passed / 0 failed, and the host simulator gate passed 220 unit tests plus 81 UI tests with 0 failures; independent review cleared scripts, tests, docs and contracts at `e51ad6a` (full-gate evidence recorded here separately)
- 2026-07-29T15:54Z codex3 #497 PR open — draft PR #547 targets `ios` from `wp-infra-sim-concurrency`; required labels `sourcery-review`, `track-b-ios` and `wp` applied; planner retains merge ownership
- 2026-07-29T16:27Z codex3 #497 review clean — Sourcery passed on `a21f2d6`; its typo finding was fixed, both inline threads were answered and resolved, and the remaining parser/harness notes were documented as non-blocking maintainability follow-ups
- 2026-07-29T16:27Z codex3 #497 ready-to-merge — PR #547 host gate is green (220 unit + 81 UI, 0 failures), CI Release/build-for-testing and unit jobs plus `ios-release-gate` passed on `a21f2d6`, and all required labels are present; final ledger-only head pending planner handoff
- 2026-08-01T04:44Z codex2 #589 claimed — urgent Rob-device dark-mode contrast defect; root-cause and spec-grounded scene-level Snow appearance pin under investigation
- 2026-08-01T04:45Z codex2 #589 branch — `wp-589-dark-mode-fix` from `origin/ios` `04e4201`; worktree `.worktrees/wp-589-dark-mode-fix`; seat `codex2`
- 2026-08-01T05:09Z codex2 #589 focused gate green — rendered oracle failed pre-fix at 26,066 Appearance-card pixels, then passed 1/1 with exact zero Light/Dark differences across Appearance, Map & data, and Location after the scene-level Snow mode pin
- 2026-08-01T05:15Z codex2 #589 evidence captured — focused Release gate passed 1/1; six 1206×2622 Light/Dark captures and measured card-region ledger recorded under `docs/design/design-system/snow-theme-lock-*`
- 2026-08-01T05:51Z codex2 #589 adversarial proof fixes green — focused Release gate passed 1/1; legacy/fixed Light diff is 0 on all three surfaces, legacy/fixed Dark teeth are 26,066 / 36,157 / 4,242 pixels, every contrast sample contains local raised-surface pixels, and exports are simulator-scoped before validate-then-install
- 2026-08-01T06:49Z codex2 #589 final host gate green — final head `f8e7df2`; `swift test` 516/516; Release and Debug build-for-testing passed; app unit 245/245 and UI 97/97 (342 total, 0 failed/skipped); test phase 2,686s; exact result counts extracted, task xcresults deleted, reusable `/private/tmp/dd-codex2` retained, seat FREE

## Done (pre-phase)

- 2026-07-25T14:30Z opus #466 PR open (PR #479) — Phase 1 task graph authored (T1.1–T1.10) at `docs/superpowers/phases/phase-1/tasks.md`; coordination.md *Current phase* repointed at it; adversarial review 30 raised / 25 survived / 25 fixed
- 2026-07-25T09:50Z fable #465 merged as 42c556f3 — design-system & IA spec ratified in the 2026-07-25 design session; **Phase 1 opened** on epic #466 (scope: DS-1 #467, DS-2 #468, DS-4 #470; DS-5 #471 stretch)
- 2026-07-25T09:50Z opus #462 merged as 246006cc — phase-1 design-session input: candidate scopes synthesised from the backlog for Rob's design session

## Done (pre-phase, 2026-07-24 wave — recorded retroactively)

- 2026-07-25T09:45Z fable #146 closed — device validation passed: 25m11s continuous session on 13452386, no kill (evidence bundle on the issue)
- 2026-07-25T01:37Z codex3 #221 merged as PR #453 (13452386); device-passed and closed 2026-07-25
- 2026-07-25T00:47Z codex2 #257 merged as PR #452 (fbf215f2); device-passed and closed 2026-07-25
- 2026-07-24T23:56Z codex1 #319 merged as PR #451 (2763aed5); closed
- 2026-07-24T21:23Z codex1 #324 merged as PR #449 (8bfdc5e9); device-passed and closed 2026-07-25
- 2026-07-24T20:49Z codex4 #446 merged as PR #450 (ce4888de); closed
- 2026-07-24T15:22Z opus #351 closed — issue audit; Rob device sign-off "looks good" (6 fixes, last #439)
- 2026-07-24T15:22Z opus #372 closed — issue audit; Rob device sign-off "confirmed" (PRs #383/#422/#425/#438)
- 2026-07-24T15:22Z opus #306 closed — issue audit; WP delivered by merged PR #313 (3ae2257)
- 2026-07-24T15:22Z opus #317 closed — issue audit; AX agency clause restored (#397 dcbef0a4 / #355 214760a6)


## Fix-now dispatch queue (2026-08-01 backlog sweep; law: coordination.md → fix-now beats carry)

Source: reviewer's closure sweep (p2p/planner__reviewer, 2026-08-01 08:06). Open count 57 → 50 at
sweep; this queue exists to keep it falling. Claim protocol: standard dual-channel, own worktree,
seat CLI; claim the topmost unclaimed item your size-budget fits; status lines here.

**In flight (pre-sweep dispatch):** #591 codex2 · #584 codex1 · #579 codex3 · #575 codex4.

**XS (single-file):** #513 retire source-text assertion · #464 head-repository guard · #546
success-only artifact cleanup.
**S (focused session):** #523 gate honours committed resolution · #454 future-date validation ·
#375 Copy ID action · #447 tile-coordinate redaction · #417 validate-ax-waits scope · #549 store
xcarchive · #94 label-survival flag · #388 pipeline heartbeats · #435 visit-edit context.
**M (full row):** #316+#322 pipeline audit pair · #489 tile-client flake (timeboxed) · #541
autoplay flake (timeboxed) · #152 watchdog kill (device loop) · #460 pinch-over-clusters (device
loop) · #361 same-day reorder block (requires-mockups label dropped as stale — ordering
semantics, not a surface).

**Parked-item owner convention:** a parked issue's owner is planner-at-trigger — when a parked
issue's named trigger fires, planner dispatches it to the pool in that wave. Parked without a
named trigger is not a state; reviewer's sweep wrote triggers into every bucket-3 body.

**Needs Rob (relayed 2026-08-01):** #477 Search scope · #378 welcome-flow order · #448 privacy
policy/diagnostics · #360 coverage-boundary affordance.

- 2026-08-01T08:25Z codex3 #594 claimed — `fix-594-door-pill-spec`; docs-only door-pill metric/provenance amendment resolving Phase 2 OF3
