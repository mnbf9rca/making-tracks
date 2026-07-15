# Agent instructions — Making Tracks

You are working on **Making Tracks** (making-tracks.app), an iOS map app for discovering interesting places — history, architecture, oddities — built from open data. The map is fresh snow; moving through the world marks it.

## Grounding — read before doing anything

1. `docs/PRINCIPLES.md` — the project's non-negotiables. Every change is checked against these.
2. `docs/superpowers/specs/2026-07-14-making-tracks-design.md` — the approved design: architecture, data model, decisions and their rationale, work-package decomposition.
3. `brief.md` — the original product brief (context for *why*; the spec supersedes it where they differ).
4. The work-package design doc for your assigned WP (in `docs/superpowers/plans/` once written). Do not improvise scope beyond your WP.

## Repo layout

- `/pipeline` — Python data pipeline (extract → reconcile → score → categorize → publish). Plain CLI, laptop-first, deterministic, SQLite between stages, publishes static files to Cloudflare R2 (`tiles.making-tracks.app`).
- `/ios` — SwiftUI app. iOS 18+ minimum, Swift 6 language mode with strict concurrency. GRDB for user data. MapLibre Native + PMTiles for the map.
- `/docs` — principles, specs, plans.

## Hard rules

- **Never break the `place_id` contract.** IDs are never reassigned; upstream disappearances are tombstoned. If your change could reassign or reformat shipped IDs, stop and flag it.
- **All external data is untrusted** — sources, LLM outputs, and even our own published tiles. Validate schemas, bound sizes, sanitize strings, https-only URLs. Never interpolate source content unescaped into shell, SQL, or LLM prompts.
- **Version everything that crosses a boundary** (manifest, tile format, DB migrations, prompt versions). Readers must detect data newer than they understand and degrade gracefully, never misread.
- **Determinism:** pipeline re-runs must not shuffle IDs or flip outputs. No wall-clock or randomness in outputs except via cached, versioned LLM calls.
- **Privacy is structural:** no identifiers, no analytics SDKs, no accounts, user data on-device. Any network write of user-derived data must satisfy the unlinkability rules in the spec's §9.
- **Ranking changes are judged by the eval harness**, not by argument.
- **Test-first** where a behaviour can be expressed as a test; the ID-stability and reconciliation invariants must have regression tests.

## Secrets

All secrets via 1Password: `op run --env-file=.env.tpl -- <command>` (masking stays ON; never `--no-masking`, never render secrets to disk). See `docs/SECRETS.md`. STANDING RULE: any compromised secret (logged, printed unmasked, read into context, committed) gets IMMEDIATELY appended to `TO-ROTATE.log` — reference/name + timestamp + vector, never the value. Logging an exposure is mandatory and blame-free.

## Workflow

Work packages (spec §8) are designed one at a time (design agent) and built one at a time (build agent) on feature branches. Keep to your package's scope; if you discover a cross-package contract problem, surface it in your report rather than unilaterally changing the contract. Commit messages: imperative, plain, no attribution boilerplate.

Branch discipline: feature branches (`wp-<id>-plan` / `wp-<id>-impl`) are cut from `develop` and PR back to `develop` — a PR is the only path onto `develop`; never push to it directly. `main` is human-gated — only Rob promotes `develop` to `main`. No agent self-merges its own PR; the design lead (fable) reviews, and merges happen only with human-sanctioned authority (overnight, PRs queue for Rob's morning review).

Worktree discipline: **one git worktree per agent, always.** Never work in the repo root checkout and never switch its branch — multiple agents share this machine, and an uncommitted edit in a shared checkout gets stranded (or destroyed) when another agent switches branches. Start every assignment by setting up your isolated workspace — use the `superpowers:using-git-worktrees` skill if your harness has it (the project-standard mechanism), otherwise fall back per that skill's convention: `git worktree add .worktrees/<branch> -b <branch>` inside the repo (the `.worktrees/` directory is gitignored; verify with `git check-ignore .worktrees` before creating) — and do all work there. Do not create sibling directories outside the repo.

## Review gates (mandatory before declaring anything complete)

Nothing is "done" on the author's say-so. Before you declare a plan complete, open a PR, or report a build finished:

1. **Adversarial self-review by subagents.** If your harness can spawn subagents or workflows, you MUST run an adversarial review pass over your own output before declaring it complete: several independent critics with distinct lenses (spec fidelity; internal coherence; feasibility/correctness; security + untrusted-data posture per §5.5; test quality — do the tests actually pin the invariants?). Have findings cross-examined (a critic's claim must survive a genuine refutation attempt), fix what survives, and include a short review summary (findings raised / survived / fixed) in your completion message.
2. **No subagent capability?** Then request the review explicitly: message fable on AMQ (kind: review_request) with the artifact path and wait for the response before declaring completion.
3. **Builders additionally:** full test suite green is a precondition, not evidence of review. Paste the actual test output (counts, not adjectives) in the PR description. A PR whose description says "tests pass" without output is incomplete.
4. **Automated review comments are part of the gate.** Sourcery reviews a PR only when the `sourcery-review` label is applied — apply it yourself the moment you open the PR (`gh pr edit <n> --add-label sourcery-review`); an unlabelled PR is silently skipped, and absence of comments then means nothing. Before a PR is merge-eligible, its author processes every review comment — use the `pr-tools:process-review` skill where available, otherwise apply the same discipline manually: triage each comment with technical rigor (verify against plan/spec — neither performative agreement nor reflexive dismissal), fix-and-reply or rebut-with-evidence, and resolve the thread. **Nothing merges with unresolved review comments — and the automated review can take time to arrive, so its absence is not cleanliness.** A PR is merge-eligible only after the automated reviewer has actually posted its review (check the PR's reviews list for it) AND every resulting thread is resolved.
5. **Independent review still happens.** The self-review pass does not replace the design lead's review of plans and PRs; it raises the floor so that review isn't the first pair of critical eyes.

The one standing exception: trivial mechanical changes (typo fixes, comment corrections) need tests green but not the adversarial pass. When unsure whether something is trivial, it isn't.
