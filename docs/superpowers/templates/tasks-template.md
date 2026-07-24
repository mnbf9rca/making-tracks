# Phase &lt;n&gt; — Task Graph

Phase spec: `docs/superpowers/specs/YYYY-MM-DD-phase-&lt;n&gt;.md`
Stall threshold: **45 min** without status change (spec §2.3 default; tune here per phase).
Status vocabulary: `claimed → branch → tests green → PR open → review clean → ready-to-merge`.
Greptile allocation (spec §7, 50/month): tasks marked `review: +greptile` below are the highest-risk (state machines, migrations, security-adjacent).

Builders write their own status line; fable reads this file in the supervision loop (spec §2.3). Talk to the tree, not to fable.

## Tasks

### T&lt;n&gt;.&lt;k&gt; — &lt;task title&gt;

- **Spec section:** §&lt;x&gt; of the phase spec
- **Acceptance criteria:** AC&lt;i&gt;, AC&lt;j&gt; (the subset this task owns)
- **Depends on:** &lt;task ids | none&gt;
- **Owner:** &lt;unclaimed | codexN&gt;
- **Review tier:** `sourcery` (always)`[ + greptile][ + opus]`  — opus tier is required for any user-facing surface
- **Status:** unclaimed
- **Builder brief:** embedded below (from `builder-brief-template.md`)

&lt;paste the filled builder brief here — self-contained; a builder must never need to ask fable a content question mid-run&gt;
