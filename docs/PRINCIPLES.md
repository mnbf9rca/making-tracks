# Making Tracks — Principles

These are the project's non-negotiables. Every design and every PR is checked against them. If a change conflicts with one of these, the change is wrong or the principle needs an explicit, argued amendment to this file — never a silent exception.

## Product

1. **The map is fresh snow.** Discovery is subtractive: the map starts full of possibility and your life gradually consumes it. Every design decision is checked against this emotional engine. Fading accumulates as *progress*, never as loss or shame.
2. **Fame is not the product.** Pageview-style popularity ranks Big Ben top; the app's joy is the overlooked-but-verified — the ghost sign, the plaque, the folly. Ranking must deliberately boost low-fame places with independent evidence of substance.
3. **One tap, no ceremony, nothing destroyed.** Marking seen is one tap in the place card, reversible, unconfirmed. Any feature that adds friction to this loop, or makes an action feel like a commitment, kills the core mechanic.
4. **Seen is a fact about the world, not about a document.** Seen-state is global per user, stored as a visit-event log. Presentation varies per context (discovery fades; lists show progress); the stored fact never fragments.
5. **Nothing is consumed silently.** No auto-marking from geolocation. Location may prompt; the user decides.
6. **The app must never look like a route recorder.** "Tracks" invites that misreading; every screenshot, subtitle, and screen must correct it.

## Data

7. **`place_id` is forever.** Once a place ID ships, it is never reassigned. Places that vanish upstream are tombstoned, not deleted. User history hangs off these IDs; breaking this contract corrupts user data.
8. **User history must never depend on someone else's database.** The first user interaction with a place snapshots it locally (`place_snapshots`). Tracks and lists render forever, regardless of upstream churn.
9. **False merge is worse than false split.** Reconciliation is tuned conservatively: two places wrongly merged corrupts user data attached to the ID; one place appearing twice is merely ugly.
10. **All source data is polluted until proven otherwise.** Wikipedia can be vandalized, OSM malformed, any string hostile. Defensive parsing everywhere; source content never interpolated unescaped into shell, SQL, or LLM prompts; LLM output is itself untrusted. The app treats even our own published tiles as untrusted input (defence in depth).
11. **Everything that crosses a boundary is versioned.** Manifests, tile formats, DB schemas, pipeline artefacts, LLM prompt versions. Readers know their maximum understood version and refuse or degrade gracefully — never silently misread newer or older data.
12. **The pipeline is deterministic and re-runnable.** Re-running never shuffles IDs or flip-flops outputs. LLM outputs are cached by (model, prompt_version, input_hash). No partial publishes — the manifest is written last, atomically.

## Ranking

13. **"Interesting" is measured, not asserted.** No one can know the ranking weights a priori. The eval harness (golden areas, hand labels, precision@k) is the arbiter; every ranking change is judged empirically against it. This includes LLM signals — they earn weight by beating the harness, not by sounding clever.

## Privacy

14. **Unable, not unwilling.** The developer must be *incapable* of tracking users: no analytics SDKs, no identifiers, no accounts in v1. User data stays on-device.
15. **Unlinkability is the bar, not anonymity.** A linkable sequence of place-events is a movement trace even with no user ID. Any telemetry is opt-in (default off), identifier-free, date-coarsened, and submitted as independent randomly-delayed events. Collectors never log IPs or request metadata.

## Engineering

16. **Local-first, static-first.** No runtime compute in v1; the app consumes static files. Servers (Workers) are added deliberately, per-feature, never by default.
17. **Region modularity.** No source or region is load-bearing. Region-specific enrichments (Historic England) are optional per-region config. Adding a region is additive.
18. **Contracts before parallelism.** Cross-track interfaces (tile format, manifest schema, place JSON, `place_id` format) are fixed in design docs before dependent work packages start.
