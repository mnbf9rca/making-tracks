# Phase-Cycle Workflow Implementation Plan

> **For agentic workers:** This plan produces **documentation artifacts only** — no application code. Steps use checkbox (`- [ ]`) syntax for tracking. Because the deliverables are prose/process docs, the per-task "test" is a **spec-coverage checklist** (does the artifact contain every element the spec section requires, with cross-references that resolve), not an automated test suite. Use superpowers:subagent-driven-development or superpowers:executing-plans to work task-by-task.

**Goal:** Create the standing artifacts the phase-cycle workflow spec requires to exist (`coordination.md`, the phase-spec / tasks / builder-brief templates, and the proposed AGENTS.md amendment text), so that the workflow can be switched on the moment Rob ratifies it — without changing any current process before then.

**Architecture:** Five Markdown artifacts, each derived faithfully from the ratified spec `docs/superpowers/specs/2026-07-24-dev-workflow-phase-cycle.md`. `coordination.md` is the standing fleet reference; three templates make the phase-cycle deliverables reproducible; one amendment-text doc holds the exact AGENTS.md edits Rob will ratify. Nothing edits `AGENTS.md` or any live process doc — the amendment text is a *proposal*, inert until ratified.

**Tech Stack:** Markdown. Repo tree is the source of truth. No build, no tests to run; verification is spec-coverage review per artifact.

## Global Constraints

Every task's requirements implicitly include these:

- **Docs-only.** No application code, no edits to `AGENTS.md`, `PRINCIPLES.md`, or any live process doc. Only the five new files below are created.
- **Nothing takes effect until Rob ratifies the §10 amendments.** The amendment-text artifact is explicitly labelled *proposed / pending Rob's ratification*; it does not modify the documents it amends.
- **Current build scope (epic #335) continues under the existing process** meanwhile. Do not remove or supersede any existing process doc.
- **Branch:** `workflow-phase-cycle-spec` (cut from `ios`). Plan and all artifacts commit here; PR target is decided at merge time by fable, not by this plan.
- **The spec is authoritative and immutable.** Copy its values verbatim (roster, budgets, thresholds). Where this plan and the tree disagree, the tree wins — re-read the spec section before drafting each artifact.
- **No unowned deferrals** (AGENTS.md law): any gap is either filled here, a named step with an owner, or an explicit Open Flag to Rob. No bare "TBD".

**Verbatim values from the spec (do not paraphrase):**
- Stall threshold: **45 minutes** without status change on a claimed task; **two unanswered nudges** → released to graph + incident line (§2.3).
- Supervision loop cadence: **~every 30 min** (§2.3).
- Greptile: **50 reviews/month**, allocated at decomposition to highest-risk tasks; not ad hoc (§7).
- Sourcery: label **`sourcery-review`** on every PR; no cap tracking; on weekly-cap exhaustion it comments that the limit was hit and skips, PR proceeds on remaining gates (§7).
- XHIGH budget: **one spec attack + one acceptance pass per phase**; any extra needs Rob's per-run ok with a cost rationale (§5).
- Build-status line values: `claimed → branch → tests green → PR open → review clean → ready-to-merge` (§2.3).
- Roster/models: Rob (human), fable (Fable 5), opus (Opus), codex-r (GPT-5.6-Sol, xhigh), codex1–4 (GPT-5.6-Sol, high) (§3).
- Wireframe canvas: **390×844 plus an accessibility variant** (§2.1).

---

## File Structure

Decomposition is locked here. Five new files, each one responsibility:

- **Create:** `docs/process/coordination.md` — standing fleet reference (§8, §10.5). The content that today lives only in fable's private memory, made durable so restarting fable costs nothing.
- **Create:** `docs/superpowers/templates/phase-spec-template.md` — the skeleton of a Phase Spec (§2.1).
- **Create:** `docs/superpowers/templates/tasks-template.md` — the skeleton of a phase task graph (`tasks.md`) (§2.2).
- **Create:** `docs/superpowers/templates/builder-brief-template.md` — the self-contained builder brief embedded per task in `tasks.md` (§2.2).
- **Create:** `docs/process/2026-07-24-phase-cycle-agents-amendments.md` — the exact proposed AGENTS.md amendment text for the five §10 items, *pending Rob's ratification* (§10).

Ordering follows dependency: `coordination.md` and the templates first (the amendment text references them), amendment text last, a short phases/README to wire the convention.

---

### Task 1: `coordination.md` — standing fleet reference

**Files:**
- Create: `docs/process/coordination.md`
- Source of truth: spec §8 (contents list), §3 (roster), §4 (taste-call), §7 (review budgets), §2.3 (supervision-loop contract), plus current `AGENTS.md` merge law (Branch discipline / Review gates) for the merge-law pointer.

**Interfaces:**
- Produces: a stable doc other artifacts point to — the §10.5 amendment adds it to the grounding chain; the builder-brief template's "operating rules" section links to it. Anchor the fleet-roster table and the merge-law section with predictable headings (`## Fleet roster`, `## Merge law`) so links resolve.
- Consumes: nothing from other tasks (foundational).

- [ ] **Step 1: Write the coverage checklist for this artifact**

`coordination.md` must contain, per §8, every one of: (a) fleet roster and handles; (b) AMQ conventions; (c) merge law (or a pointer to it in AGENTS.md); (d) supervision-loop contract; (e) taste-call protocol; (f) review-budget numbers; (g) pointer to the current phase directory. Write this 7-item checklist at the top of your scratch notes; the artifact is done only when all 7 are present.

- [ ] **Step 2: Draft the artifact with these exact sections**

Create `docs/process/coordination.md` with this structure and content (fill each from the cited source, verbatim where numeric):

```markdown
# Fleet Coordination

Standing reference for the phase-cycle workflow. A fresh fable session boots by reading `AGENTS.md`, this file, and the current phase's `tasks.md` (spec §8). Nothing load-bearing lives only in a session.

## Fleet roster
<table from spec §3: Seat | Model / effort | Does — Rob, fable, opus, codex-r, codex1–4, verbatim>

## AMQ conventions
<how agents message: handles above; threads p2p/<a>__<b>; kinds; priority; the "announce merges as first act (PR + SHA)" rule; drain-and-act. Populate from fable's standing practice — see the owned step below.>

## Merge law
Pointer to `AGENTS.md` → "Branch discipline" and "Review gates": PR-only onto `develop`/`ios`; no self-merge; fable reviews and merges with human-sanctioned authority; `main` is Rob-only; announce each merge as the first act with PR number + merged SHA.

## Supervision-loop contract (spec §2.3)
fable reads `tasks.md` + PR/CI states ~every 30 min; merges ready PRs per merge law (announce PR + SHA); assigns next tasks; nudges stalls. Stall = a claimed task with no status change for **45 minutes** (tunable per phase in the `tasks.md` header). Nudge = AMQ quoting the last status + the brief pointer. **Two unanswered nudges → task released to the graph + an incident line logged.** Builders write status to `tasks.md`; fable reads it; builders talk to the tree, not to fable.

## Taste-call protocol (spec §4)
<the 4 numbered rules verbatim: default best-guess + `## Taste guesses` PR heading; ping Rob only when a wrong guess is expensive to rework AND waiting blocks nothing; if waiting blocks downstream, best-guess and flag regardless; never stall the pipeline.>

## Review budgets (spec §7)
Greptile **50/month**, allocated at decomposition to highest-risk tasks (state machines, migrations, security-adjacent), not ad hoc. Sourcery: label `sourcery-review` on every PR, no cap tracking; on weekly-cap exhaustion Sourcery comments the limit was hit and skips, the PR proceeds on remaining gates. Docs-only PRs consume neither.

## Current phase
Pointer to the active `docs/superpowers/phases/phase-<n>/` directory and its `tasks.md`. (No active phase yet — the cycle starts with the first design session after epic #335 reaches the MVP bar, spec §9.)
```

- [ ] **Step 3: Owned fill-in — fable supplies the memory-held content**

Sections **AMQ conventions** and any **standing items** currently living only in fable's memory are fable's to supply (spec §8/§9: "the content that today exists only in fable's private memory"; "fable's memory-held standing items move into it or are retired"). Post an AMQ to fable requesting: the AMQ conventions text and the list of standing items to fold-in-or-retire. Paste fable's response into the marked sections. **Owner: fable.** This is a cutover prerequisite for Phase 1 (§9), not a blocker for committing the rest of the artifact.

- [ ] **Step 4: Verify against the checklist**

Confirm all 7 §8 elements are present and every numeric value matches the spec verbatim (45 min, two nudges, 30 min, 50/month). Confirm the merge-law pointer resolves to real `AGENTS.md` headings. Confirm no live process doc was edited.

- [ ] **Step 5: Commit**

```bash
git add docs/process/coordination.md
git commit -m "Add fleet coordination reference for phase-cycle workflow"
```

---

### Task 2: `phase-spec-template.md` — Phase Spec skeleton

**Files:**
- Create: `docs/superpowers/templates/phase-spec-template.md`
- Source of truth: spec §2.1 (Design session) + §6 (standing judgment rules) + §2.1's contract reference (PRINCIPLES.md Engineering 18).

**Interfaces:**
- Produces: the structure a design session fills to create `docs/superpowers/specs/YYYY-MM-DD-phase-<n>.md`. The tasks template (Task 3) references "spec section" links into a doc of this shape.
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the coverage checklist**

Per §2.1, a Phase Spec must carry: (a) Goal narrative + explicit non-goals; (b) Acceptance criteria — testable, behaviour-level "done" statements (vague ones are rejected in-session); (c) Wireframes — HTML sources + rendered PNG at 390×844 + accessibility variant, ruled by Rob in-session; (d) Contracts — cross-track interfaces fixed before dependent tasks (PRINCIPLES.md Engineering 18); (e) Judgment rules for the phase (the §6 standing ones included). Plus the process note that a ratified spec is immutable and one adversarial XHIGH attack (codex-r, §5) runs before ratification.

- [ ] **Step 2: Draft the template with this exact skeleton**

Create `docs/superpowers/templates/phase-spec-template.md`:

```markdown
# Phase <n> Spec — <title>

Date: YYYY-MM-DD. Status: draft → ratified in-session by Rob. **A ratified spec is immutable for the phase; changing it means another design session.**
Adversarial gate: codex-r runs one XHIGH attack on this draft before ratification (spec §5).

## 1. Goal
<Narrative of what this phase delivers.>

## 2. Non-goals
<Explicit out-of-scope statements.>

## 3. Acceptance criteria
Testable, behaviour-level statements of "done" — each gradable pass/fail by the acceptance pass. No vague criteria.
- [ ] AC1: <behaviour-level statement>
- [ ] AC2: ...

## 4. Wireframes
For each user-facing surface: HTML source path, rendered PNG at **390×844**, and an **accessibility-size variant**. Opus specifies the layout; a build agent authors the HTML and renders; opus validates; Rob rules in-session. No new wireframes are authored mid-build — the build implements against ruled wireframes only.
- Surface: <name> — source `docs/design/<area>/wf-<name>.html`; renders `<name>-default.png`, `<name>-ax.png`; ruled: <yes/date>.

## 5. Contracts
Cross-track interfaces fixed before dependent tasks start (PRINCIPLES.md Engineering 18).
- Contract: <name> — <signature / shape>.

## 6. Judgment rules for this phase
The standing spirit rules (spec §6: fold-or-file) apply. Phase-specific judgment calls:
- <rule>.
```

- [ ] **Step 3: Verify against the checklist**

All 5 §2.1 elements present; the immutability + adversarial-attack notes present; the 390×844 + accessibility-variant values verbatim; PRINCIPLES.md Engineering 18 cited for contracts.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/templates/phase-spec-template.md
git commit -m "Add phase-spec template for phase-cycle workflow"
```

---

### Task 3: `tasks-template.md` + `builder-brief-template.md` — decomposition skeletons

These two are coupled: `tasks.md` embeds a builder brief per task, so they are one reviewable unit.

**Files:**
- Create: `docs/superpowers/templates/tasks-template.md`
- Create: `docs/superpowers/templates/builder-brief-template.md`
- Source of truth: spec §2.2 (Decomposition) + §2.3 (build-status values, stall header) + §7 (review tiers) + §4 (taste-call, referenced by the brief).

**Interfaces:**
- Consumes: the Phase Spec shape from Task 2 (tasks link to spec sections and inherit their acceptance-criteria subset).
- Produces: the `tasks.md` structure fable reads in its supervision loop; the builder-brief structure each builder self-serves. Anchor the per-task status line with the exact §2.3 values so fable's loop can parse them.

- [ ] **Step 1: Write the coverage checklist**

`tasks.md` per §2.2 must give each task: link to its spec section; its subset of acceptance criteria; dependencies; owner; review tier (Sourcery always; tier adds Greptile and/or opus); and a self-contained builder brief. Plus a **header** carrying the per-phase stall threshold (§2.3). The **builder brief** per §2.2 must be self-contained enough that "a builder should never need to ask fable a content question mid-run": spec context, operating rules, checkpoint protocol, taste-call protocol.

- [ ] **Step 2: Draft `tasks-template.md`**

Create `docs/superpowers/templates/tasks-template.md`:

```markdown
# Phase <n> — Task Graph

Phase spec: `docs/superpowers/specs/YYYY-MM-DD-phase-<n>.md`
Stall threshold: **45 min** without status change (spec §2.3 default; tune here per phase).
Status vocabulary: `claimed → branch → tests green → PR open → review clean → ready-to-merge`.
Greptile allocation (spec §7, 50/month): tasks flagged `review: +greptile` below are the highest-risk (state machines, migrations, security-adjacent).

## Tasks

### T<n>.<k> — <task title>
- **Spec section:** §<x> of the phase spec
- **Acceptance criteria:** AC<i>, AC<j> (subset owned by this task)
- **Depends on:** <task ids or "none">
- **Owner:** <unassigned | codexN>
- **Review tier:** sourcery (always)[ + greptile][ + opus]  <!-- opus tier required for any user-facing surface -->
- **Status:** unclaimed
- **Builder brief:** see the embedded brief below (from `builder-brief-template.md`)

<builder brief block per template>
```

- [ ] **Step 3: Draft `builder-brief-template.md`**

Create `docs/superpowers/templates/builder-brief-template.md`:

```markdown
## Builder brief — T<n>.<k>

**Spec context.** What this task delivers, in the phase's terms, and the exact acceptance criteria it owns (copied, not linked — the builder reads this alone). Ruled wireframe(s) to implement against, if any: <paths>. Contracts consumed/produced: <names + shapes>.

**Operating rules.** Branch `wp-<id>-impl` (or the phase's naming) cut from the phase base; PR-only onto the target; label `sourcery-review` + track + wp; existing gates unchanged (adversarial self-review, tests green with pasted counts, zero new warnings, Release build under fleet lock). Fleet reference: `docs/process/coordination.md`.

**Checkpoint protocol.** Update this task's status line in `tasks.md` at each transition: `claimed → branch → tests green → PR open → review clean → ready-to-merge`. Write state to the tree, not to fable.

**Taste-call protocol (spec §4).** If the spec doesn't settle a judgment call: build the most defensible interpretation and flag it in the PR body under `## Taste guesses`, stating the alternative. Ping Rob (push) only when a wrong guess is expensive to rework (schema/data migration, system-wide visual change) AND waiting blocks nothing downstream. If waiting would block downstream, best-guess and flag regardless, noting the risk. Never stall the pipeline on a taste question.

**Fold-or-file (spec §6).** On finding a defect in a pre-existing component: always log a tracker issue at discovery. If the fix is small and cleanly encapsulated in this PR, fix it here and note it in the PR body, close the issue on merge. Otherwise file and continue; never expand PR scope to chase it.
```

- [ ] **Step 4: Verify against the checklist**

Every §2.2 per-task field present in `tasks-template.md`; the stall-threshold header present; the status vocabulary verbatim. The builder brief covers spec context + operating rules + checkpoint protocol + taste-call protocol (the four §2.2 requirements) and is self-contained (no "ask fable"). Taste-call (§4) and fold-or-file (§6) reproduced accurately.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/templates/tasks-template.md docs/superpowers/templates/builder-brief-template.md
git commit -m "Add tasks and builder-brief templates for phase-cycle workflow"
```

---

### Task 4: `2026-07-24-phase-cycle-agents-amendments.md` — proposed AGENTS.md amendment text

**Files:**
- Create: `docs/process/2026-07-24-phase-cycle-agents-amendments.md`
- Source of truth: spec §10 (the five amendments) + current `develop:AGENTS.md` sections being amended (line anchors below, verified 2026-07-24).

**Interfaces:**
- Consumes: `coordination.md` (Task 1) and the templates (Tasks 2–3) — the amendment text references them by path.
- Produces: the exact text Rob ratifies. After ratification (out of this docs-only scope), a separate PR applies it to `develop:AGENTS.md`.

Current AGENTS.md anchors on `develop` (each amendment must quote the current text it changes):
- Grounding chain: the "Grounding — read before doing anything" list, item 4 ("The design doc for your assigned WP, in `docs/superpowers/plans/`"). — §10.2, §10.5 targets.
- Build-agent law: "Work packages (spec §8) are designed one at a time … built one at a time … on feature branches." — §10.2, §10.3 targets.
- Fold-or-file: the "**Fold or file.**" paragraph. — §10.4 target.
- Authoring law: "**UI design ships with mockups.**" paragraph + "the build agent renders, the design agent validates … Rob rules on taste." — §10.1 target (timing only, not authorship).

- [ ] **Step 1: Write the coverage checklist**

Per §10, the artifact must contain proposed text for **all five** amendments: (1) wireframes move to design time — amends the *timing* of "UI design ships with mockups", not its authorship; (2) WP-at-a-time flow replaced by the phase cycle (§2), grounding chain gains the Phase Spec and `tasks.md`; (3) taste-call protocol (§4) added to build-agent law; (4) fold-or-file refined per §6; (5) `coordination.md` created and added to the grounding chain. Each amendment must quote the **current** AGENTS.md text and give the **proposed** replacement, and the whole doc must be labelled *pending Rob's ratification*.

- [ ] **Step 2: Draft the amendment doc**

Create `docs/process/2026-07-24-phase-cycle-agents-amendments.md`:

```markdown
# Proposed AGENTS.md Amendments — Phase-Cycle Workflow

Status: **PROPOSED — pending Rob's ratification.** Inert until ratified; do not apply to `AGENTS.md` before then. Source: `docs/superpowers/specs/2026-07-24-dev-workflow-phase-cycle.md` §10. Target: `AGENTS.md` on `develop`.

Each item gives the CURRENT text and the PROPOSED replacement.

## Amendment 1 — Wireframes move to design time (§10.1)
Amends the *timing* of "UI design ships with mockups", not its authorship.
- CURRENT: <quote the authoring-law paragraph>.
- PROPOSED: add that wireframes are authored and ruled **in the design session** (opus specifies, a build agent authors HTML/renders, opus validates, Rob rules before ratification); the build phase implements against ruled wireframes only; no new wireframes mid-build. Authorship split unchanged.

## Amendment 2 — Phase cycle replaces WP-at-a-time (§10.2)
- CURRENT: <quote "Work packages … one at a time … built one at a time …"> and the grounding-chain item 4.
- PROPOSED: replace the WP-at-a-time framing with the phase cycle (spec §2). Grounding chain gains the **Phase Spec** (`docs/superpowers/specs/…-phase-<n>.md`) and the phase **`tasks.md`** (`docs/superpowers/phases/phase-<n>/tasks.md`).

## Amendment 3 — Taste-call protocol added to build-agent law (§10.3)
- CURRENT: <quote the build-agent-law paragraph>.
- PROPOSED: append the taste-call protocol (spec §4): default best-guess + `## Taste guesses` PR heading; ping Rob only for expensive-to-rework guesses that block nothing; best-guess-and-flag when waiting blocks downstream; never stall the pipeline.

## Amendment 4 — Fold-or-file refined (§10.4)
- CURRENT: <quote the "Fold or file." paragraph>.
- PROPOSED: refine per spec §6 — always log a tracker issue at discovery; fix in the same PR only when small and cleanly encapsulated (note in PR body, close on merge); otherwise file and continue, never expand PR scope; the acceptance pass grades these as "spirit".

## Amendment 5 — coordination.md added to grounding chain (§10.5)
- CURRENT: the grounding-chain list (no `coordination.md`).
- PROPOSED: add `docs/process/coordination.md` to the grounding chain; note that a fresh fable session boots on AGENTS.md + coordination.md + the current phase's tasks.md.
```

Fill each `<quote …>` with the exact current text (read from `develop:AGENTS.md` at draft time; do not paraphrase).

- [ ] **Step 3: Verify against the checklist**

All five amendments present, each with a real current-text quote and a concrete proposed replacement; the doc is clearly labelled *proposed / pending ratification*; no actual `AGENTS.md` edit was made. Amendment 1 changes timing only (authorship untouched). Paths to `coordination.md`, the phase spec, and `tasks.md` resolve.

- [ ] **Step 4: Commit**

```bash
git add docs/process/2026-07-24-phase-cycle-agents-amendments.md
git commit -m "Draft proposed AGENTS.md amendments for phase-cycle workflow (pending ratification)"
```

---

### Task 5: `phases/README.md` — directory convention wiring

**Files:**
- Create: `docs/superpowers/phases/README.md`
- Source of truth: spec §2.2 (phase directory), §2.1 (spec naming), §9 (cutover).

**Interfaces:**
- Consumes: the templates (Tasks 2–3) and `coordination.md` (Task 1) — links to them.
- Produces: the convention that makes `docs/superpowers/phases/phase-<n>/` discoverable.

- [ ] **Step 1: Draft the README**

Create `docs/superpowers/phases/README.md`:

```markdown
# Phases

Each development phase (spec `docs/superpowers/specs/2026-07-24-dev-workflow-phase-cycle.md`) gets a directory `phase-<n>/` containing its `tasks.md` task graph. The phase's spec lives in `docs/superpowers/specs/YYYY-MM-DD-phase-<n>.md`.

Templates: `docs/superpowers/templates/` (phase-spec, tasks, builder-brief). Standing fleet reference: `docs/process/coordination.md`.

No phase exists yet: the cycle starts with the first design session after epic #335 reaches the MVP bar (spec §9). Phase 1 is whatever that session scopes.
```

- [ ] **Step 2: Verify + commit**

Confirm all links resolve to files created in Tasks 1–3. Then:

```bash
git add docs/superpowers/phases/README.md
git commit -m "Add phases directory convention README for phase-cycle workflow"
```

---

## Self-Review (run after drafting all artifacts)

**1. Spec coverage** — every spec section maps to a task:
- §2.1 Design session → Task 2 (phase-spec template) + Amendment 1.
- §2.2 Decomposition → Task 3 (tasks + builder-brief templates) + Amendment 2.
- §2.3 Autonomous build → coordination.md supervision-loop section (Task 1) + tasks status vocabulary (Task 3).
- §2.4 Acceptance pass → graded process; no new artifact required (codex-r + phase spec drive it). Noted, no task.
- §3 Roles → coordination.md roster (Task 1).
- §4 Taste-call → coordination.md (Task 1) + builder brief (Task 3) + Amendment 3.
- §5 XHIGH budget → phase-spec template note + coordination.md (recorded as a standing constraint). Covered.
- §6 Spirit rules → builder brief fold-or-file (Task 3) + Amendment 4.
- §7 Review budget → coordination.md (Task 1) + tasks Greptile allocation (Task 3).
- §8 Session hygiene → coordination.md (Task 1).
- §9 Cutover → Task 1 owned fable step + phases/README (Task 5); no process change now (Global Constraints).
- §10 Amendments → Task 4 (all five).
- §11 Open inputs → informational (codex billing shape); no artifact. Noted, no task.

**2. Placeholder scan** — the only intentional fill-ins are the `<quote …>` current-text captures in Task 4 (the builder reads them live from `develop:AGENTS.md`) and the fable-owned AMQ-conventions/standing-items content in Task 1 Step 3 (explicitly owned, a §9 cutover prerequisite). Both are owned, not bare TBDs.

**3. Cross-reference consistency** — status vocabulary is identical in coordination.md (Task 1), tasks-template (Task 3), and builder-brief (Task 3): `claimed → branch → tests green → PR open → review clean → ready-to-merge`. Stall threshold 45 min and cadence ~30 min appear only in coordination.md + tasks header, matching. Paths used across tasks (`docs/process/coordination.md`, `docs/superpowers/templates/*`, `docs/superpowers/phases/`) are consistent.

## Open questions for fable (do not block committing the plan)

- **Template location:** placed at `docs/superpowers/templates/`. If you prefer `docs/process/templates/`, say so.
- **Amendment-text location:** placed at `docs/process/2026-07-24-phase-cycle-agents-amendments.md`. Confirm, or prefer it inside the plans/ tree.
- **coordination.md AMQ-conventions + standing-items content** is yours to supply (Task 1 Step 3) — it cannot be authored from the spec alone. Flag if you'd rather I draft a strawman from observed practice for you to correct.
