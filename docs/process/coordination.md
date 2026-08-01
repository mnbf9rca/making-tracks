# Fleet Coordination

Standing reference for the phase-cycle workflow (`docs/superpowers/specs/2026-07-24-dev-workflow-phase-cycle.md`). This is the fleet's **boot document**: a fresh session — including a full fleet restart — comes up by reading `AGENTS.md`, this file, and the current phase's `tasks.md`. Nothing load-bearing lives only in a session, so restarting any seat costs nothing.

## Fleet roster

| Seat | Model / effort | Does |
|---|---|---|
| Rob | human | Design sessions, taste rulings, ratifies amendments, promotes `develop` → `main` |
| planner | Fable 5 | Coordination, budget/dependency checks, merges, the supervision loop, verification. Session is disposable |
| reviewer | Opus | Drafts phase specs, wireframe layouts, decomposition; per-PR design review where a task's review tier calls for it; spawns clean-context read-only subagents where fresh eyes are needed |
| codex-r | GPT-5.6-Sol, xhigh | Adversarial seat: bounded attack passes only (one spec attack + one acceptance pass per phase). Context persists — cannot be remotely cleared. Joins at the fleet restart |
| fable-design | (design-facilitation role, not an AMQ seat) | Facilitates design sessions with Rob and the external designer; named in session-batch items and the design-system README since 2026-07-25. Routes through Rob; has no inbox |
| codex1–4 | GPT-5.6-Sol, high | Build, one uniform pool (app, pipeline, VPS — work items are work items). Effort stays at high until two phases of defect data exist under this workflow, then revisit |

Legacy handles `codex` (bare) and `claude` are **dead** — do not route to them.

## AMQ conventions

- **Root:** `.agent-mail`. **Fleet session: `collab`.** The base tree is *not* drained by agents, so every send must use `--session collab` (`amq send --to <handle> --session collab …`). The inline `<handle>@<project>:<session>` form is cross-**project** routing only — do not use it for same-project session sends.
- **Handles:** `planner`, `reviewer`, `codex1`–`codex4`, `codex-r` (from the restart). **Rob has no mailbox** — the `user` handle was removed from AMQ (Rob, 2026-07-31).
- **Threads:** `p2p/<a>__<b>` for a pair (e.g. `p2p/planner__reviewer`). **Human-action gates go to Rob in planner's session chat, never AMQ** (Rob, 2026-07-31): planner asks inline, and because chat scrolls past him, carries every open ask in a standing recap re-stated whole whenever Rob checks in ("status"). Any other seat with a question for Rob routes it through planner.
- **Kinds** (amq defaults): `review_request`, `question`, `todo`, `status`, `decision`, plus `answer`/`review_response`. Set `priority` (`urgent`/`normal`/`low`) to match.
- **Drain-and-act:** drain with `amq drain --include-body`, act on the message, then reply on its thread.
- **Seat rule** (spec §8): a fresh session boots on `AGENTS.md` + this file + the current `tasks.md`; nothing load-bearing lives only in a session.

## Merge law (Rob, 2026-07-21)

- Merges **execute from planner's seat** unless delegated per-merge.
- A reviewer's "cleared to merge" is **gate input, not authorization** — clearance and execution are separate.
- The executor **announces every merge as their first act**: a `p2p` message to planner carrying the **PR number + merged SHA**.
- **Tree hashes, not ancestry or SHAs, answer content questions.** Under squash-merge, "did the reviewed head land?" is answered by comparing tree hashes (`git rev-parse <commit>^{tree}` or `<commit>:ios`) — ancestry checks false-alarm on every squashed PR. Review clearances anchor to the `ios/` subtree hash: any later head with a matching subtree hash carries the clearance forward without re-review; any mismatch (even whitespace) sends it back.
- **A clearance anchors to the content it examined, whatever that content is.** Code review anchors to the `ios/` subtree hash; a docs review anchors to the **blob hashes** of the files it read; a design-packet validation anchors to the **SHA-256 of each image**. The rule is the same in all three — matching content carries the verdict forward, any mismatch returns it — and naming the right granularity is what makes a re-review proportionate: when one file of a two-file PR changes, the surviving anchor limits the second pass to the file that moved.
- **Immediately before merging, re-read the live PR head against the head the gate evidence anchors to. A moved head re-gates.** "This PR was mergeable when I took it" and "this branch was ahead one commit when I pushed" can both be true at the same instant, and **neither side sees an error** — the merge captures a prefix of the work and the rest is silently orphaned on the branch. It happened once here and cost a second PR to recover; the check costs one `gh pr view --json headRefOid`.
- GitHub's `mergedBy` is a shared token and proves nothing about who authorized the merge — the announcement is the record.
- **Planner-authored docs/process PRs: planner self-merges once gates are clean** (Rob, 2026-07-31: stop routing these merges to him). The no-self-merge rule continues to bind builders' PRs; coordination artifacts are the coordinator's to land.
- Branch/PR mechanics live in `AGENTS.md` → **Branch discipline** and **Review gates**: PR-only onto `develop`/`ios` (never push directly); no agent self-merges its own PR; `main` is Rob-only; promotions to `main` are merge commits, feature PRs squash into `develop`/`ios`.

## Supervision-loop contract (spec §2.3)

planner runs a loop **~every 30 minutes**: read `tasks.md` and the PR/CI states; merge ready PRs per the merge law (announce PR + SHA first); assign next tasks; nudge stalls.

- **Dual channel** (Rob, 2026-07-24; supersedes "builders talk to the tree, not to planner"): all agents — builders included — announce events to planner via AMQ (completion, blockers, handoffs), **and** write status to `tasks.md`. AMQ is the event channel so planner learns of completions without waiting for the next loop pass; `tasks.md` is the durable record the loop reads to catch a stuck agent — no progress, or a reply that never came. An event announced only on AMQ or only in `tasks.md` is half-delivered.
- **Claim state is authoritative only with planner, never from the tree.** A builder's status line rides their own branch until their PR merges, so the `tasks.md` on a long-lived branch **structurally lags** every claim made since the last merge: a task reading `unclaimed` there may already be claimed and branched. The AMQ event channel carries claims in real time and terminates at planner, so planner is the only place that knows. Ask; do not infer. This is the one question where reading the tree is the wrong instinct — it is otherwise the right one, which is exactly what makes the trap easy to walk into.
- **No active phase** (Rob, 2026-07-25): when no phase `tasks.md` exists, status goes to `docs/superpowers/phases/pre-phase/tasks.md` — same format, same stall rules. The ledger must be an **in-worktree file**: agents recover from crashes by reading it, and the supervision loop reads it to spot stuck work; neither works from GitHub comments. **Tracker issues stay clean** — an issue records the work item and its outcome, not running status; do not post status essays or progress commentary as issue comments.
- **Stall** = a claimed task with **no status change for 45 minutes** (tunable per phase in the `tasks.md` header).
- **Nudge** = an AMQ message quoting the last status line and the builder-brief pointer.
- **Two unanswered nudges** → the task is released back to the graph and an **incident line** is logged.
- Status vocabulary: `claimed → branch → tests green → PR open → review clean → ready-to-merge` (plus `blocked: <reason>` / `released`).

## Fleet economy

How the fleet operates. These are standing practice, not concessions to circumstance.

- **A builder is woken when work is claimable for them, and stands down when none is.** An idle seat costs nothing; a woken seat with nothing to claim costs a context and produces a nudge cycle. Availability is not a reason to assign.
- **Briefs are lean and self-contained.** A builder should never need to ask a content question mid-run, and should never have to read past what their task requires to find it. Both failures cost the same thing twice — once in the asking, once in the waiting.
- **Sequencing avoids known conflict pairs, even at the cost of parallelism.** Two agents editing the same region of a large file will conflict, and the rework costs more than the serialisation saved. Order the work so the conflict cannot arise rather than resolving it afterwards.
- **A base advance that carries no code is verified by diff, not re-gated.** Confirm the delta touches no reviewed file — at file level, since a directory legitimately differs when a sibling task lands in the same module — and the prior gate evidence stands. **A code-bearing advance re-gates**, without argument.
- **Handoffs name an exact head.** A clearance, a gate result and a merge all refer to one SHA, and whoever receives one verifies it matches before relying on it. A verdict attached to "the branch" is worthless the moment the branch moves.
- **One checkout per seat.** The primary worktree (`/Users/rob/git/making-tracks`) belongs to Rob's own use and planner's coordination; every other seat works in `.worktrees/<branch>` for anything that touches the tree. Two agents sharing a checkout collide on `git checkout`, not on edits — the victim sees a phantom "my file vanished", not a git error (surfaced by reviewer, 2026-07-31).

## Taste-call protocol (spec §4)

When the spec doesn't settle a judgment call:

1. **Default: best-guess.** Build the most defensible interpretation and flag it in the PR body under a `## Taste guesses` heading, stating the alternative considered.
2. **Ping Rob** (push notification) only when a wrong guess would be expensive to rework (schema/data migration, system-wide visual change) **and** waiting blocks nothing downstream.
3. If waiting would block downstream work, best-guess and flag regardless of rework cost, noting the risk in the flag.
4. **Never stall the pipeline** on a taste question.

## Review budgets (spec §7)

- **Greptile: 50 reviews/month.** Allocated at decomposition to the highest-risk tasks (state machines, migrations, security-adjacent). Not spent ad hoc.
- **Sourcery:** label every PR `sourcery-review`; no cap tracking. If the weekly diff cap runs out, Sourcery comments that the limit was hit and skips the review; the PR proceeds on the remaining gates — progress beats full coverage.
- **Docs-only PRs consume neither.**
- Existing gates are unchanged: adversarial self-review, tests green with pasted counts, zero new warnings, Release build under fleet lock.
- **XHIGH budget** (spec §5): codex-r gets **one spec attack + one acceptance pass per phase**. Any additional XHIGH run needs Rob's explicit per-run ok, requested inline with a cost rationale.

## Evidence and review law (graduated from Phase 1)

- **A render asserting a state or change carries its measurement beside the image** (ink counts, bounding boxes, contrast ratios). A render is not self-evidencing; the number is what makes it evidence.
- **A render packet carries what makes it reproducible, not just what makes it readable.** Per-image **SHA-256**; the capture tool and its version; a **deterministic regeneration script committed beside the images**; assets resolved **repo-locally** (fonts included) so the artifact reproduces offline rather than depending on a CDN that will answer differently later; and, while a packet is pre-ruling, an explicit statement that it is. Established by W-2 and W-1's packets (#568, #570) before any rule required it — the law is catching up to the practice, which is the direction that produces rules worth keeping.
- **A render packet declares its evidence CLASS and carries the oracle that class can honour — a digest that cannot hold must not be presented as one that can.** The clause above required per-image SHA-256 flatly; the first four-script regeneration run (#584) showed a digest is a *reproduction* oracle only for one of three classes, so this **narrows** it:
  - **Deterministic fixture** — SHA-256 reproduces; regeneration must match it, byte for byte.
  - **Head-anchored** (the frame renders build metadata or any other property of its own source) — the digest pins the reviewed bytes only, the record names the source head, and regeneration is *expected* to differ. Such a frame can never reproduce, by construction.
  - **Nondeterministic content** (a live map) — the paired **measurement record** is the reproduction oracle; the digest pins the reviewed session. #584 re-captured eight such frames byte-different and geometry-identical to 0.01pt.
  The failure this prevents is not a mismatch, it is the habit a mismatch teaches: **a reader who watches digests fail twice stops checking them**, and digest-checking is what caught a shipped defect no assertion could see (below).
- **Verify a record's digests against its images rather than reading the record.** A hash record is worth exactly the one command nobody runs; both Phase 2 packets were checked this way at validation and again after merge, and a digest set that survives a squash is proof the ruled artifact is the reviewed artifact.
  - **The instance that earned this rule its place.** T2.9 (#580) was held because its brief required committed renders and none were present; the images existed only as `.xcresult` attachments the disk-hygiene rule deletes. Twenty-two minutes after the frames were committed, one of them showed the Offline-maps row drawing **no icon** — an unresolvable SF Symbol name renders an empty image with no crash, no warning and no test failure, and row icons are accessibility-hidden, so every label, summary, row-height and hit-target assertion passed with the glyph missing. **No oracle in the repo could see it; only a render could.** Had it merged, the surface would have shipped a blank column and the acceptance pass would have graded it green against instruments structurally blind to icons.
- **Absorb review notes into a validated packet's record without re-rendering.** A re-render to fix an annotation moves every digest and voids a validation for no design gain; record-only edits keep the anchor alive. If the images genuinely must change, say which and to what digest **before** the reviewer looks.
- **Enumerate the full constraint structure before adopting or validating any figure** — ink, wash composite, both states, sibling pairs. No numeric floors by fiat (designer ruling). A constraint set is checked for satisfiability before anything is built to it.
- **A general bound states its qualifier.** A ceiling computed for a free pair does not apply to a pinned one; quoting a bound into a case it wasn't computed for is the misattribution class the metrics table exists to stop.
- **A clearance is only as wide as what was examined, and says so.** "Cleared" without scope reads as broader than the review; state the boundary in the verdict.
- **Silence is not a ruling.** Authority claims trace to explicit spoken rulings; provenance for everything else states what actually happened (measured / validated / awaiting ruling).
- **A body's check claims are re-read against live checks immediately before handoff** (three stale-claim instances in one night; the check runs async, so the window is structural).
- **Assert that every input was classified, not merely that the known classes were handled.** A test that branches over its inputs must prove the branches covered them all — count the matches and assert the count equals the input set. Three findings in one phase had this shape and each fix left room for one more: `simctl erase` was validated and `delete` was not, then `delete` was fixed and `boot` was not (#578); a scope-row assertion was guarded by a prefix that would silently stop matching, then guarded by a counter that a *third* prefix would still slip past (#587). The specific fixes were all correct; the shape kept regenerating the defect. **An allowlist is default-open until something asserts its completeness.**
- **A retirement criterion says "zero occurrences outside assertions whose purpose is to prove absence."** A retired identifier survives, correctly, inside the negative assertions that prove it is gone — deleting them would destroy the regression guard. Written as a flat "greps zero", the criterion fails a correct implementation for containing its own proof; this happened twice in one afternoon in unrelated subsystems (`map.layers` in #582, `MT_RELEASE_GATE_DESTINATION` in #578). Standard form, not per-row wording.
- **A regeneration script boots its seat or states the booted-seat precondition in its header.** #584's first cold seat failed with CoreSimulator 405 while three warm ones passed — a trap that hides behind ordinary fleet activity and surfaces months later, to whoever regenerates evidence on a machine nobody warmed. Boot-on-demand is preferred; existing scripts take it when next touched.
- **At closeout, rows born from rulings sweep the backlog** for issues they satisfy (a delivered feature left its requesting issue open once).
- **Builders choose their own execution mode** (inline vs subagent-driven) within the fixed rails; routing that choice upward is noise.

## Standing items

Durable facts the fleet operates under (moved here from planner's session memory so a restart preserves them).

1. **Signing** (ruleset, verified 2026-07-23): long-lived branches require signed commits. Agents sign via the 1Password socket, biometric on first use per session; tree-preserving re-sign amends carry gate evidence forward.
2. **Pre-auth "flip at 2"** (Rob, 2026-07-22): at 2 consecutive counting greens, planner executes the ruleset change (`ios-release-gate` required) + the CI-merge-authority amendment without further ask. **Currently PARKED** pending the self-hosted-runner decision (new MacBook ~2026-07-29). Count state lives in `docs/ios-gate-ledger.md`.
3. **Standing goal** (Rob, 2026-07-20): drain epic #335 and its sub-issues to the MVP bar before new design threads. Per spec §9, **Phase 1 begins after this completes**.
4. **CI-gate amendment candidates** pending Rob's ruling: build-hash assertion as gate provenance; `Package.resolved` lint (swift test rewrites the MapLibre pin); "pin to the environment you do not control".
5. **Rob's device artifacts** sync to `.mt-data/screenshots/` and `.mt-data/diagnostics/` in the repo root — check there before asking Rob for files.

## Current phase

**Phase 2 — the World door: DS-3 (#469) + DS-6 (#472).** Epic #466. Spec: `docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md` (ratified #465, amended #524 + the amendment wave). Session rulings: [`docs/superpowers/phases/phase-2/design-session-rulings.md`](../superpowers/phases/phase-2/design-session-rulings.md) (P2R-1…P2R-10, W-1/W-2, merged #563). Task graph and status ledger: [`docs/superpowers/phases/phase-2/tasks.md`](../superpowers/phases/phase-2/tasks.md) — builders write their status lines there and the supervision loop reads it.

Nothing else from epic #466 this phase. The builder pool is **codex1–codex4**, and the stall threshold is the 45-minute default. Wireframe rows carry the extended status vocabulary (`… → awaiting ruling → ruled`) and unblock their dependants at **ruled**, not merge. Phase 1 closed at 34/35 with the remainder parked in #520; T2.3 completes it at 35/35.

Pre-phase and issue-routed work continues to use `docs/superpowers/phases/pre-phase/tasks.md`.
