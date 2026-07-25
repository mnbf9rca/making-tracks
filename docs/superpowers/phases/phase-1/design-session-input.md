# Phase 1 — design-session input

**Status:** input for Rob's Phase 1 design session (phase-cycle spec §2.1). This is *not* the Phase Spec — the spec is drafted live in-session and ratified by Rob. This document exists so the session opens with the backlog already synthesised into a small number of coherent, differently-shaped candidate scopes. **Rob rules what Phase 1 is.** The candidates below are strategic bets to choose between or recombine, not a recommendation.

Prepared by opus, 2026-07-25. Grounded in a read of every pivotal open issue (bodies + comments + landed rulings), not recall. Board at time of writing: **42 open issues** (the 2026-07-24→25 wave closed the MVP-bar epic #335 and #146/#221/#257/#319/#324/#334 among others).

## Constraints that shape every candidate

Carried forward from the last epic (still in force):
- **One simulator.** UI-build tasks that both need the simulator serialise — a phase concentrated in one subsystem parallelises better than one scattered across many.
- **Mockups before UI builds.** Any design-gated item needs ruled wireframes (authored + rendered + Rob-ruled) *before* the build task starts. In the phase cycle those wireframes are produced *in the design session itself* (§2.1), so a design-gated scope front-loads session time.
- **Review budgets.** codex-r XHIGH effort is hard-bounded to one spec attack + one acceptance pass per phase.

Each candidate is tagged with how much **design-session wireframe time** it demands, because that is the scarce in-session resource.

---

## Candidate A — Onboarding & the Tracks/Lists spine
*The "make the core coherent before layering more on" bet.*

| Issue | What it is | Size | Design-gated |
|---|---|---|---|
| **#378** Welcome flow | 5-screen first-run journey; **order already ruled** (2026-07-23), per-screen copy/layout still owed | L | Yes — per-screen wireframes |
| **#266** Unify menu>Tracks & Lists>My tracks | Two nav doors render the same track; unify on the protected My-tracks surface. **Mockups ratified & merged (#295, `68d1b38`)**; app-side unbuilt | XL | No (mockups ratified) — but huge |

**Rationale:** these are the surfaces a new user hits first and the core navigation spine. #266 removes *active drift* (two doors to the same thing) before more features attach to either. Highest strategic value.
**Cost / risk:** heaviest option (L + XL). #378 needs a full per-screen wireframe pass in-session; #266 is multi-subsystem (routing unify + verdict-edit fold + retrace-map + slider/autoplay physics + old-screen aliasing). **Likely too big for one phase as-is** — natural split: take #266's routing/aliasing unification only, defer the retrace-map + verdict-edit folds.
**Wireframe time:** high (all of #378).

## Candidate B — Map legibility & interaction
*The "make the map read and behave right" bet — single subsystem, one-simulator-friendly.*

| Issue | What it is | Size | Design-gated |
|---|---|---|---|
| **#360** Coverage-boundary affordance | Distinguish covered-but-empty vs no-data-here. **Ruled** (2026-07-23), reuses shipped PaperStyle shading | M | No — build-time knobs only |
| **#359** Online loading affordance | Top progress hairline + pin shimmer for in-flight CDN fetches. **Ruled** (2026-07-23) | M | Yes — wireframe |
| **#460** Pinch over dense pins | Pinch-zoom unreliable in dense clusters (device 2026-07-25); **root-cause first**, then gesture-priority fix | M | No |

**Rationale:** one coherent subsystem (map / PaperStyle), so the single simulator isn't a bottleneck. Two of three already have rulings; #360 can go straight to build. Fixes felt device-pass pains.
**Cost / risk:** #359 needs a wireframe + fetch-layer plumbing for real byte progress; #460 has an unknown root cause (must reproduce/instrument before a fix is scoped).
**Wireframe time:** low–moderate (only #359).

## Candidate C — Device-pass polish sweep
*The "fast felt wins, validate the new phase machinery on low risk" bet.*

| Issue | What it is | Size | Design-gated |
|---|---|---|---|
| **#454** Visit editor allows future dates | Constrain picker to today-or-earlier (device 2026-07-25) | S | No |
| **#456** Hide already-saved filter | Filter toggle reusing landed Saved-state (#438) + filter chrome (#427) | S | No |
| **#349** Download progress honesty (items 1–2) | Real "preparing" + install progress on the download flow | M | No |
| **#460** Pinch over dense pins | (as above) could live here instead of B | M | No |

**Rationale:** small, self-contained, non-design-gated, reuses already-landed infrastructure; directly clears Rob's fresh device feedback. Lowest risk, quickest to green — a good first exercise of the phase cycle itself.
**Cost / risk:** lower strategic value (polish, not foundation). #349 item 3 (backgroundable downloads) is an architectural change to the download lifecycle — **split it out**, keep only progress honesty here.
**Wireframe time:** near-zero.

---

## Cross-cutting riders (cheap; can attach to any scope — mostly no simulator contention)

- **#130** Accessibility — **codify the standing rule into AGENTS.md** (Dynamic Type / VoiceOver / never color-alone). Cheap early win; the contrast audit + "Places on screen" VoiceOver surface can come later.
- **#448** Model diagnostic sharing in the threat model / privacy.md — docs-only governance closeout, keeps privacy claims honest against the shipped export flow. No UI.
- **#447** Redact tile coords from diagnostic paths — **code already merged via #449**; this is verify-and-close, not a build.
- **#403** iOS CI-gate-law amendment — process-law PR, not product; governs how iOS merges gate. Land independently of Phase 1 feature choice.

## Explicitly *not* Phase 1 material (surfaced so they're not mistaken for candidates)

- **#350** App-wide theming coherence — XL umbrella epic across ~15 surfaces, **flagged post-MVP unless Rob pulls it forward**; each surface needs its own mockups. Could carve out onboarding/settings if Candidate A is chosen.
- **#455** Tidy diagnostics export screen — explicitly parked to fold into the later IA / look-and-feel revamp thread; poor fit unless that thread opens in Phase 1.

## Questions for Rob to rule in-session

1. **Strategic axis:** foundation (A), a subsystem (B), or momentum/polish (C) — or a recombination (e.g. B + the two device bugs from C)?
2. If A: do we take **#266 whole**, or **routing-unify only** and defer the retrace/verdict folds?
3. Does **#349 backgroundable downloads** belong in Phase 1, or split to a later phase?
4. Which **cross-cutting riders** ride along (#130 rule codification and #448 privacy docs are the cheapest)?
5. Is **dense-pin map usability (#460)** a Phase 1 priority, and if so under B (map) or C (polish)?

*Appendix: the full ~30-issue keep-list from the 2026-07-24 closure audit remains the backlog these candidates were drawn from; pipeline (track-a) WPs — #345/#368/#303/#297/#316/#309/#322 — and services (track-c) WPs — #59/#24/#23/#142 — are separate tracks not synthesised here, as Phase 1 framing is Track-B/app-first.*
