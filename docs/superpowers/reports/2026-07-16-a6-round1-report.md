# A6 Round-1 Report — LLM Curiosity Signal Evaluation

Date: 2026-07-16 · Author: fable (coordinator) · Pre-registration: `docs/superpowers/decisions/2026-07-16-a6-bakeoff-preregistration.md` (#87, corrected #105, grid §11 #111)
Eval spend: **$3.94 of the $20 cap** (measured from API `usage.cost`; ledger on the VPS).

## Verdict (phase-closing)

**v1 ships heuristics-only.** A real LLM ranking signal exists (multiple models at strict AUC 0.66–0.72 against a below-chance heuristic baseline), but **no candidate passes the pre-registered two-sided injection floor**, so nothing is promotable to production. Per the pre-registration, this is a valid closing answer for Phase A; the pre-registered v2 prompt grid (§11) is the upgrade path and runs as background work alongside the app track.

## The two questions Rob asked, answered

**Which model for a 600k-place production sweep?** At the v1 (thin) prompt — all costs measured, per full 600k sweep at hosted per-token rates:

| Candidate | strict AUC (llm-research labels) | ~cost/600k | Notes |
|---|---|---|---|
| deepseek-v4-pro (thinking disabled) | 0.716 | ~$48 | leader, statistical tie with hermes at n=158 |
| hermes-4-70b | 0.682 | ~$23 | |
| nex-n2-mini (no thinking) | 0.670 | ~$5 | value pick |
| glm-5.2 (thinking disabled) | (partial — one injection probe errored) | — | recorded, not chased |
| llama-3.1-8b | 0.459 | — | fails beat-0.5 gate |
| hy3:free | admission-failed | — | portal rejects all six request shapes ("missing user tag"), probe evidence committed |
| muse-spark-1.1 | admission-failed | — | mandatory reasoning (ignores disable; 253/256 tokens burned thinking); also priced out of class |

Baseline for context: the 7-signal heuristic composite scores **strict AUC 0.441 — below chance** — on the sparse-signal KL corpus. The heuristics carry no rank signal there; the LLM supplies one.

**Is reasoning effort worth paying for?** **No.** nex-n2-mini effort matrix: none 0.670 / low 0.644 / high 0.654 — differences inside measurement noise, cost and latency only rise. The task is a snap assessment; models should run with thinking disabled. (Corollary discovered en route: several models *reason by default* and bill it as output — reasoning must be explicitly disabled per model, verified by probe; shapes and evidence in `scripts/probe_*.py` + committed outputs.)

## Injection (why nothing promotes)

On the corrected model-relative metric (#102/#105; the first-generation metric had a geometry artifact — see the postmortem in the decision doc §4):

| | inflation | deflation | honest-suppression | two-sided | floor (0.95/0.80) |
|---|---|---|---|---|---|
| hermes-4-70b | 0.433 | 0.194 | 0.417 | 0.345 | fail |
| nex-n2-mini | 0.667 | 0.303 | 0.182 | 0.523 | fail |

**Deflation is the dominant vulnerability** (metric-generation-independent): both models obey embedded "this place is dull" instructions most of the time — the product-relevant attack (bury a rival by editing its description). hermes additionally suppresses 41.7% of honest adversarial-*looking* content. Prompt-hardening v2 (structural fencing, attribute-justified scores — §4 note) is the pre-registered mitigation; whether it clears the floor is a measured question in the grid round.

## Label provenance (the caveat that got fixed)

All original labels were `llm-research` (machine). Rob performed a boundary-stratum editorial pass (30 places at the yes/meh frontier): **19 changes, 11 confirmations** — the machine labeler was systematically yes-inflated where LLM tastes overlap (bundle members counted as standalone destinations). Distribution moved 84/56/18 → 69/61/28 (#112). AUCs against Rob-corrected labels: see addendum below. London-300 remains quarantined (its labels are still 100% machine — a broader human hold-out is pre-registered as blocking for any strong quality claim, §9/§11).

## Production economics frame

- Budget class per Rob: **$40–60 per 600k sweep** → models ≲$0.25–0.38/M input at the v1 token profile. The leaders above all fit.
- Extract-bearing records are 3.46% of the corpus → richer prompts are a **quality axis, not a cost axis** (blended cost stays thin-dominated).
- The hosted-vs-Modal **cutover** (per the trader precedent: the cheapest venue differs by task) is round-2's measured deliverable for whichever open-weight candidate leads after the grid; no venue conclusion is asserted before that measurement.
- Production call volume is further reduced by the pre-registered sparsity-gated call policy (§5): curiosity calls go to buried places, not all places.

## Process notes (for the record)

- Serial-bottleneck lesson (three registry quadratics, each unmasked by fixing the previous) and the instrument lesson (the injection metric's geometry artifact caught by a skeptic pass on a too-round number) are recorded in the decision doc and memory.
- The harness now enforces: measured-costs-only, eval-scoped budget cap ($20, Rob-raised from $10 mid-round with provenance), per-candidate fault isolation, fail-closed empty fixtures, live telemetry, concurrency 8.

## What runs next (background to the app track)

1. v2 prompt grid (§11, 20 cells, ~$15): extract-length swept (the 300-char cap was an inherited untested constant), rationale-then-score form, budget-class models — tests Rob's 0.85-within-$40–60 hypothesis.
2. Injection-hardening v2 prompt, re-run of the floor.
3. Round 2 (conditional): Modal batch measurement → hosted/self-host cutover table.
4. London reveal: once, on the overall winner, Holm-corrected, only if a candidate passes the floor.

## Addendum — AUCs against Rob-corrected labels (#112)

Recomputed after Rob's boundary relabel. **The ranking holds and every candidate's AUC rose** — on the 30 disputed rows the models tracked Rob's corrections better than the machine labels, a direct (small-sample) rebuttal of the labeler-correlation worry for these candidates:

| Candidate | AUC (llm-research) | AUC (Rob-corrected) |
|---|---|---|
| deepseek-v4-pro (none) | 0.716 | **0.724** |
| hermes-4-70b | 0.682 | **0.697** |
| nex-n2-mini (none) | 0.670 | **0.683** |
| nex-n2-mini (high) | 0.654 | 0.670 |
| nex-n2-mini (low) | 0.644 | 0.663 |
| llama-3.1-8b | 0.459 | 0.511 |
| heuristic baseline | 0.441 | 0.490 |

Effort ordering unchanged (none > high > low; differences in noise). Caveat: 30 of 158 rows changed; London's machine-labeled quarantine and the broader human hold-out remain the pre-registered guards for any promotion-grade claim.
