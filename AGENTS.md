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

## Workflow

Work packages (spec §8) are designed one at a time (design agent) and built one at a time (build agent) on feature branches. Keep to your package's scope; if you discover a cross-package contract problem, surface it in your report rather than unilaterally changing the contract. Commit messages: imperative, plain, no attribution boilerplate.
