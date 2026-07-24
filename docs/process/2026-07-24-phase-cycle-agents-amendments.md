# Proposed AGENTS.md Amendments — Phase-Cycle Workflow

**Status: PROPOSED — pending Rob's ratification.** Inert until ratified; do not apply to `AGENTS.md` before then. After ratification, a separate PR applies these to `AGENTS.md` on `develop`.

Source: `docs/superpowers/specs/2026-07-24-dev-workflow-phase-cycle.md` §10. Current text quoted from `AGENTS.md` on `develop` (verified 2026-07-24). Each item gives the CURRENT text and the PROPOSED change.

---

## Amendment 1 — Wireframes move to design time (§10.1)

Amends the **timing** of "UI design ships with mockups", not its authorship.

**CURRENT** (Authoring law):
> **UI design ships with mockups.** This is a visual app; a UI design doc is not complete as prose. Every work package with a user-facing surface carries **rendered mockups**, and they are authored by a **build agent**, not by the designer.

**PROPOSED** — add, in the same section:
> Under the phase cycle, wireframes are authored and ruled **in the design session**, not during the build. Opus specifies the layout; a build agent authors the HTML and renders (390×844 plus an accessibility variant); opus validates; **Rob rules on them before the spec is ratified.** The build phase implements against ruled wireframes only — **no new wireframes are authored mid-build.** The authorship split (build agent renders, design agent validates, Rob rules on taste) is unchanged; only the timing moves forward.

---

## Amendment 2 — Phase cycle replaces WP-at-a-time (§10.2)

**CURRENT** (Build-agent law, first sentence):
> Work packages (spec §8) are designed one at a time (design agent) and built one at a time (build agent) on feature branches.

**CURRENT** (Grounding chain, item 4):
> 4. The design doc for your assigned WP, in `docs/superpowers/plans/`. Do not improvise scope beyond your WP.

**PROPOSED:**
- Replace the WP-at-a-time framing with the **phase cycle** (spec §2): each phase is a large package defined in one design session (the **Phase Spec**), decomposed into a **task graph** (`tasks.md`), and built autonomously by the builder pool.
- Extend the grounding chain so item 4 reads: the **current Phase Spec** (`docs/superpowers/specs/YYYY-MM-DD-phase-<n>.md`) and the phase **task graph** (`docs/superpowers/phases/phase-<n>/tasks.md`) — the task's builder brief is the scope; do not improvise beyond it.

---

## Amendment 3 — Taste-call protocol added to build-agent law (§10.3)

**CURRENT** (Build-agent law paragraph — append to it):
> Work packages (spec §8) are designed one at a time … Keep to your package's scope; if you discover a cross-package contract problem, surface it in your report rather than unilaterally changing the contract. Commit messages: imperative, plain, no attribution boilerplate.

**PROPOSED** — append the taste-call protocol (spec §4):
> **Taste-call protocol.** When the spec doesn't settle a judgment call: build the most defensible interpretation and flag it in the PR body under a `## Taste guesses` heading, stating the alternative. Ping Rob (push) only when a wrong guess would be expensive to rework (schema/data migration, system-wide visual change) **and** waiting blocks nothing downstream. If waiting would block downstream work, best-guess and flag regardless, noting the risk. **Never stall the pipeline on a taste question.**

---

## Amendment 4 — Fold-or-file refined (§10.4)

**CURRENT** (Fold or file):
> **Fold or file.** A new finding may be folded into an in-flight work package only if all of these hold: same surface and same owner; the WP is not yet in review; it introduces no design fork, no schema or contract change, and no new dependency; at most one addition has already been absorbed (a third means file it); it is recorded as an explicit scope addition in the PR body. Otherwise file an issue first, then route it to its own PR if it is an urgent live bug, or to the next planned WP. Regardless of route, anything not fixed the same day gets a tracker issue — routing messages are not project memory. (Incidents → *Three riders on one work package*.)

**PROPOSED** — replace with the refined rule (spec §6):
> **Fold or file.** On finding a defect in a pre-existing component while building or testing: **always log a tracker issue at the moment of discovery.** If the fix is small and cleanly encapsulated within the current PR, **fix it in the same PR**, note it in the PR body, and close the issue on merge. Otherwise **file and continue — never expand PR scope to chase it.** The acceptance pass grades these judgments as part of "spirit". (Incidents → *Three riders on one work package*.)

---

## Amendment 5 — `coordination.md` added to the grounding chain (§10.5)

**CURRENT** (Grounding chain): the list has no `coordination.md` entry.

**PROPOSED:**
- Add `docs/process/coordination.md` to the grounding chain — the standing fleet reference (roster, AMQ conventions, merge law, supervision-loop contract, taste-call protocol, review budgets, standing items, current-phase pointer).
- Note that a fresh session — including a full fleet restart — boots by reading `AGENTS.md`, `docs/process/coordination.md`, and the current phase's `tasks.md`; nothing load-bearing lives only in a session.
