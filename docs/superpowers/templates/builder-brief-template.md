## Builder brief — T&lt;n&gt;.&lt;k&gt;

Self-contained: a builder should be able to run this task from the brief alone, without asking fable a content question mid-run.

**Spec context.** What this task delivers, in the phase's terms, and the exact acceptance criteria it owns (copied here, not just linked — the builder reads this alone). Ruled wireframe(s) to implement against, if any: &lt;paths&gt;. Contracts consumed / produced: &lt;names + shapes&gt;.

**Operating rules.** Branch `wp-&lt;id&gt;-impl` (or the phase's naming) cut from the phase base; PR-only onto the target; label `sourcery-review` + track + `wp`. Existing gates unchanged: adversarial self-review, tests green with pasted counts, zero new warnings, Release build under fleet lock. Fleet reference: `docs/process/coordination.md`.

**Checkpoint protocol.** Update this task's status line in `tasks.md` at each transition: `claimed → branch → tests green → PR open → review clean → ready-to-merge`. Write state to the tree, not to fable.

**Taste-call protocol (spec §4).** If the spec doesn't settle a judgment call: build the most defensible interpretation and flag it in the PR body under `## Taste guesses`, stating the alternative. Ping Rob (push) only when a wrong guess would be expensive to rework (schema/data migration, system-wide visual change) **and** waiting blocks nothing downstream. If waiting would block downstream, best-guess and flag regardless, noting the risk. Never stall the pipeline on a taste question.

**Fold-or-file (spec §6).** On finding a defect in a pre-existing component while building or testing: **always log a tracker issue at the moment of discovery.** If the fix is small and cleanly encapsulated within this PR, fix it here and note it in the PR body, close the issue on merge. Otherwise file and continue; never expand PR scope to chase it.
