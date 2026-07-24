# Fleet Coordination

Standing reference for the phase-cycle workflow (`docs/superpowers/specs/2026-07-24-dev-workflow-phase-cycle.md`). This is the fleet's **boot document**: a fresh session — including a full fleet restart — comes up by reading `AGENTS.md`, this file, and the current phase's `tasks.md`. Nothing load-bearing lives only in a session, so restarting any seat costs nothing.

## Fleet roster

| Seat | Model / effort | Does |
|---|---|---|
| Rob | human | Design sessions, taste rulings, ratifies amendments, promotes `develop` → `main` |
| fable | Fable 5 | Coordination, budget/dependency checks, merges, the supervision loop, verification. Session is disposable |
| opus | Opus | Drafts phase specs, wireframe layouts, decomposition; per-PR design review where a task's review tier calls for it; spawns clean-context read-only subagents where fresh eyes are needed |
| codex-r | GPT-5.6-Sol, xhigh | Reviewer seat: bounded adversarial passes only (one spec attack + one acceptance pass per phase). Context persists — cannot be remotely cleared. Joins at the fleet restart |
| codex1–4 | GPT-5.6-Sol, high | Build, one uniform pool (app, pipeline, VPS — work items are work items). Effort stays at high until two phases of defect data exist under this workflow, then revisit |

Legacy handles `codex` (bare) and `claude` are **dead** — do not route to them.

## AMQ conventions

- **Root:** `.agent-mail`. **Fleet session: `collab`.** The base tree is *not* drained by agents, so every send must use `--session collab` (`amq send --to <handle> --session collab …`). The inline `<handle>@<project>:<session>` form is cross-**project** routing only — do not use it for same-project session sends.
- **Handles:** `fable`, `opus`, `codex1`–`codex4`, `user` (Rob), `codex-r` (from the restart).
- **Threads:** `p2p/<a>__<b>` for a pair (e.g. `p2p/fable__opus`); `gate/<topic>` addressed to `user` for human-action gates (a decision or promotion only Rob can make).
- **Kinds** (amq defaults): `review_request`, `question`, `todo`, `status`, `decision`, plus `answer`/`review_response`. Set `priority` (`urgent`/`normal`/`low`) to match.
- **Drain-and-act:** drain with `amq drain --include-body`, act on the message, then reply on its thread.
- **Seat rule** (spec §8): a fresh session boots on `AGENTS.md` + this file + the current `tasks.md`; nothing load-bearing lives only in a session.

## Merge law (Rob, 2026-07-21)

- Merges **execute from fable's seat** unless delegated per-merge.
- A reviewer's "cleared to merge" is **gate input, not authorization** — clearance and execution are separate.
- The executor **announces every merge as their first act**: a `p2p` message to fable carrying the **PR number + merged SHA**.
- GitHub's `mergedBy` is a shared token and proves nothing about who authorized the merge — the announcement is the record.
- Branch/PR mechanics live in `AGENTS.md` → **Branch discipline** and **Review gates**: PR-only onto `develop`/`ios` (never push directly); no agent self-merges its own PR; `main` is Rob-only; promotions to `main` are merge commits, feature PRs squash into `develop`/`ios`.

## Supervision-loop contract (spec §2.3)

fable runs a loop **~every 30 minutes**: read `tasks.md` and the PR/CI states; merge ready PRs per the merge law (announce PR + SHA first); assign next tasks; nudge stalls.

- **Dual channel** (Rob, 2026-07-24; supersedes "builders talk to the tree, not to fable"): all agents — builders included — announce events to fable via AMQ (completion, blockers, handoffs), **and** write status to `tasks.md`. AMQ is the event channel so fable learns of completions without waiting for the next loop pass; `tasks.md` is the durable record the loop reads to catch a stuck agent — no progress, or a reply that never came. An event announced only on AMQ or only in `tasks.md` is half-delivered.
- **No active phase** (fable ruling, 2026-07-24, pending Rob's ratification): when no phase `tasks.md` exists, issue-routed work uses its **tracker issue** as the durable record — post the same status vocabulary as issue comments. The dual-channel obligation is unchanged; only the ledger location moves.
- **Stall** = a claimed task with **no status change for 45 minutes** (tunable per phase in the `tasks.md` header).
- **Nudge** = an AMQ message quoting the last status line and the builder-brief pointer.
- **Two unanswered nudges** → the task is released back to the graph and an **incident line** is logged.
- Status vocabulary: `claimed → branch → tests green → PR open → review clean → ready-to-merge`.

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

## Standing items

Durable facts the fleet operates under (moved here from fable's session memory so a restart preserves them).

1. **Signing** (ruleset, verified 2026-07-23): long-lived branches require signed commits. Agents sign via the 1Password socket, biometric on first use per session; tree-preserving re-sign amends carry gate evidence forward.
2. **Pre-auth "flip at 2"** (Rob, 2026-07-22): at 2 consecutive counting greens, fable executes the ruleset change (`ios-release-gate` required) + the CI-merge-authority amendment without further ask. **Currently PARKED** pending the self-hosted-runner decision (new MacBook ~2026-07-29). Count state lives in `docs/ios-gate-ledger.md`.
3. **Standing goal** (Rob, 2026-07-20): drain epic #335 and its sub-issues to the MVP bar before new design threads. Per spec §9, **Phase 1 begins after this completes**.
4. **CI-gate amendment candidates** pending Rob's ruling: build-hash assertion as gate provenance; `Package.resolved` lint (swift test rewrites the MapLibre pin); "pin to the environment you do not control".
5. **Rob's device artifacts** sync to `.mt-data/screenshots/` and `.mt-data/diagnostics/` in the repo root — check there before asking Rob for files.

## Current phase

No phase is active yet. The cycle starts with the first design session after epic #335 reaches the MVP bar (spec §9); Phase 1 is whatever that session scopes. When a phase is live, this section points to its `docs/superpowers/phases/phase-<n>/tasks.md`.
