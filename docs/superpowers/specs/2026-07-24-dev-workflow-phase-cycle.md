# Development Workflow — Phase Cycle

Date: 2026-07-24. Status: draft, awaiting Rob's review.
Scope: replaces the spec→plan front half of the current process; amendments it forces are listed in §10 and take effect only when Rob ratifies them.

## 1. Goal

A high-quality app, where quality means behaviour and appearance. Rob's time goes to interactive design and taste rulings; agents own all mechanics. The main quality lever is prevention: a defect caught in the design session costs minutes, the same defect caught after merge costs a repair cycle. The pipeline never waits on Rob.

## 2. The phase cycle

A repeating cycle. Each phase is a large package of work defined in one sitting and built autonomously over multiple hours or days.

### 2.1 Design session (interactive, Rob present)

One sitting produces the **Phase Spec** (`docs/superpowers/specs/YYYY-MM-DD-phase-<n>.md`):

- Goal narrative and explicit non-goals.
- **Acceptance criteria**: testable, behaviour-level statements of "done". These are what the acceptance pass grades against, so vague criteria are rejected in-session.
- **Wireframes**: authored during the session (HTML sources, rendered PNG at 390×844 plus accessibility variant), ruled on by Rob before the session ends. Build agents implement against ruled wireframes; they no longer author them.
- **Contracts**: cross-track interfaces fixed before dependent tasks start (PRINCIPLES.md Engineering 18).
- Judgment rules for the phase (see §6 for the standing ones).

Drafted live by opus. Before ratification, codex at XHIGH effort runs one adversarial attack on the draft (§5). Rob ratifies. A ratified spec is immutable for the phase; changing it means another session.

### 2.2 Decomposition

The ratified spec is decomposed into a **task graph**: `docs/superpowers/phases/phase-<n>/tasks.md`.

- Each task is one PR-sized unit, sized at planning time against the review budget (§8) — PR size is a planning decision, not a review-time discovery.
- Each task carries: link to its spec section, its subset of acceptance criteria, dependencies, owner, review tier (Sourcery-only / +Greptile / +opus), and a **self-contained builder brief** — spec context, operating rules, checkpoint protocol, taste-call protocol. A builder should never need to ask fable a content question mid-run.
- Decomposition drafted by opus; fable checks budget arithmetic and dependency order only.

### 2.3 Autonomous build

- Builders (codex1–3) claim tasks from the graph and update their task's checkbox and status line as they progress: `claimed → branch → tests green → PR open → review clean → ready-to-merge`.
- All progress state lives in `tasks.md`. Builders write it; fable reads it. Builders talk to the tree, not to fable.
- Ambiguity is handled by the taste-call protocol (§4). The pipeline never stalls on a question.
- fable runs a supervision loop (~every 30 min): read `tasks.md` and PR/CI states; merge ready PRs per merge law (announce as first act, PR + SHA); assign next tasks; nudge stalls. **Stall** = a claimed task with no status change for 45 minutes (tunable per phase in the tasks.md header). Nudge = AMQ message quoting the last status and the brief pointer. Two unanswered nudges → task released back to the graph and an incident line logged.

### 2.4 Acceptance pass

When the graph drains (or at the phase deadline), a fresh-context codex XHIGH run grades the built phase against the Phase Spec — letter and spirit (§6 judgments included). Output: pass/fail per acceptance criterion, the list of taste-flags awaiting Rob, and the list of logged findings.

Failures + taste-flags + parked items = the agenda for the next design session. Nothing else queues for Rob.

## 3. Roles and models

| Seat | Model / effort | Does |
|---|---|---|
| Rob | human | Design sessions, taste rulings, ratifies amendments, promotes to main |
| fable | Fable 5 | Coordination, budget/dependency checks, merges, supervision loop, verification. Session is disposable (§9) |
| opus | Opus | Drafts phase specs, wireframes, decomposition; per-PR design review where a task's review tier says so |
| codex XHIGH | GPT-5.6-Sol, xhigh | Bounded adversarial passes only (§5) |
| codex1–3 | GPT-5.6-Sol, high | Build. Effort stays at high until two phases of defect data exist under this workflow; then revisit |
| codex4 | GPT-5.6-Sol, high | Pipeline/VPS, as today |

## 4. Taste-call protocol (Rob, 2026-07-24)

When the spec doesn't settle a judgment call:

1. **Default: best-guess.** Build the most defensible interpretation and flag it in the PR body under a `## Taste guesses` heading, stating the alternative considered.
2. **Ping Rob** (push notification) only when a wrong guess would be expensive to rework (schema/data migration, system-wide visual change) **and** waiting blocks nothing downstream.
3. If waiting would block downstream work, best-guess and flag regardless of rework cost, noting the risk in the flag.
4. Never stall the pipeline on a taste question.

## 5. XHIGH budget

XHIGH effort is expensive and hard-bounded: **one spec attack per phase** (design session) and **one acceptance pass per phase**. Any additional XHIGH run needs Rob's explicit per-run ok, requested inline with a cost rationale.

## 6. Spirit rules (fold-or-file, refined — Rob, 2026-07-24)

On finding a defect in a pre-existing component while building or testing:

- **Always log it** as a tracker issue at the moment of discovery.
- If the fix is small and cleanly encapsulated within the current PR: **fix it in the same PR**, note it in the PR body, close the issue on merge.
- Otherwise file and continue; never expand PR scope to chase it.
- The acceptance pass grades these judgments as part of "spirit".

## 7. Review budget

- **Greptile**: 50 reviews/month. Allocated at decomposition to the highest-risk tasks (state machines, migrations, security-adjacent). Not spent ad hoc.
- **Sourcery**: weekly diff-character cap (number recorded in `docs/process/coordination.md` when Rob supplies it). Decomposition sizes PRs so the phase fits the cap; overflow tasks schedule into the next week rather than merging unreviewed.
- Docs-only PRs consume neither.
- Existing gates (adversarial self-review, tests green with pasted counts, zero new warnings, Release build under fleet lock) are unchanged.

## 8. Session hygiene

New repo doc: `docs/process/coordination.md` — fleet roster and handles, AMQ conventions, merge law, supervision-loop contract, taste-call protocol, review-budget numbers, pointer to the current phase directory. This is the content that today exists only in fable's private memory.

A fresh fable session boots by reading AGENTS.md, `coordination.md`, and the current phase's `tasks.md` — nothing load-bearing lives only in a session, so restarting fable costs nothing.

## 9. Migration

- **Phase 1 = the remainder of epic #335** drained to the MVP bar (per the standing goal). The first design session scopes that remainder into a Phase Spec; wireframes only where UI is touched.
- fable's memory-held standing items move into `coordination.md` or are retired.

## 10. Amendments this forces (Rob to ratify; AGENTS.md on develop unless noted)

1. Wireframe authorship moves to design time: design side authors, build agents implement, Rob rules in-session. (Reverses "UI design ships with mockups" build-agent authorship.)
2. WP-at-a-time flow replaced by the phase cycle (§2); grounding chain gains the Phase Spec and `tasks.md`.
3. Taste-call protocol (§4) added to build-agent law.
4. Fold-or-file refined per §6.
5. `docs/process/coordination.md` created and added to the grounding chain.

## 11. Open inputs

- Sourcery weekly diff-character cap — needed from Rob before the first decomposition.
- Codex billing shape (flat-rate vs metered) — affects whether build effort should shift after the two-phase defect-data checkpoint (§3).
