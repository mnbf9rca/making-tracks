# Making Tracks — Design

**Date:** 2026-07-14
**Status:** approved design, pre-implementation
**App name:** Making Tracks · **Domain:** making-tracks.app (tiles served from tiles.making-tracks.app)
**Platform:** iOS (SwiftUI), solo developer
**Repo layout:** monorepo — `/pipeline` (Python), `/ios` (Swift), `/docs`

---

## 1. Product summary

A map app that surfaces interesting things around you — history, architecture, oddities, landmarks — from open databases (Wikipedia/Wikidata, OpenStreetMap, regional heritage registers). The map is fresh snow: moving through the world marks it. Discovery is subtractive — the map starts full of possibility and your life gradually consumes it.

Two views over the same data:

- **Discovery** — seen places are faded, not hidden. Low opacity, still tappable. A hide-seen toggle exists for those who want the clean version.
- **Tracks** — the chronological, place-anchored record of where you've been. First-class screen: it is the shareable artefact and the retention mechanism.

**Naming risk (drives App Store packaging):** "tracks" reads as GPX/route recording. The subtitle and first screenshot must immediately establish this is *discovery*, not route logging.

## 2. Scope

**v1 (the solo loop):** map discovery, save-to-list, mark seen, Tracks history, local lists, category filters, offline region packs. Regions: **UK and Malaysia**.

**v2 (deliberately deferred, schema-ready):** list sharing (see §9 for the privacy/permission requirements captured now), CloudKit sync, background nearby notifications, more regions.

**v1.5 (after first TestFlight):** opt-in anonymised aggregate stats (§9).

Geographic modularity is a day-one constraint: region-specific sources (e.g. Historic England) are optional per-region enrichments, never load-bearing columns. Malaysia deliberately stress-tests ranking where enrichment is thin.

## 3. Core model decisions (settled)

### 3.1 Seen is global per user, stored as an event log

`seen` attaches to the **place**, globally per user — never to a (place, list) pair. The map is itself a list (the universal one); per-list seen-state would let the map and a list disagree about the same place, making "have I seen this?" unanswerable and breaking the snow metaphor.

Storage is a **visit-event log**, not a boolean: `visits(id, place_id, visited_at, verdict, note)`. "Seen" = derived: place has ≥1 visit. This buys:

- Tracks is the event log rendered chronologically — no separate history model.
- Re-visits are representable.
- Un-marking seen = deleting an event (reversible, nothing destroyed).
- Per-list freshness ("visited since joining this list") is a future *query*, not stored state — visit timestamps vs list-join timestamps.

**The gift problem is presentation, not state.** A received list never renders seen places as pre-faded/consumed; it renders progress: "you've been to 3 of these · 7 to go", seen items checked, not ghosted. One stored fact, context-appropriate rendering. Discovery map fades; lists show progress.

### 3.2 Bookmarks are a list

One mechanism: **lists**. The app ships with a system list "Want to go"; the quick-save tap adds to it. Custom lists ("Date nights", "KL trip") are the same mechanism — this is the Google/Apple Maps saved-places pattern users already know.

- Marking seen never mutates list membership. Every list renders visit-progress the same way ("3 of 12 visited"), which is exactly how shared lists will render in v2.
- Pin states: **unseen** · **saved** (on ≥1 list) · **visited** (≥1 visit event). Saved and visited coexist freely — bookmark is intent, visit is history; they are orthogonal, not a state machine.

### 3.3 Verdict: "worth going again"

`visits.verdict` is a nullable field (v1 values: `loved` or null). Offered as an optional one-tap heart at the mark-seen moment; skippable, editable later. Powers a "Loved" filter in Tracks and a distinct map marker: visited pins fade to the standard seen treatment; loved pins fade but keep a heart-badged marker so favourites stay findable on the snow.

### 3.4 Marking seen: one tap once the place is in front of you

No confirmation, fully reversible. "One tap" means one tap *in the place card/callout* — two physical taps from the map, zero ceremony — not literally one tap on a pin (which would mis-mark constantly in dense areas). No auto-marking from geolocation. Nearby prompts ("You're near X — seen it?") are **foreground-only in v1**; background nudges are a deliberate v2 decision (always-on location permission, battery, review friction).

## 4. "What counts as interesting" (the make-or-break problem)

Nobody can know the ranking at design time; "interesting" is a taste function that must be measured, not asserted. The design deliverable is **machinery to iterate cheaply** plus a defensible first guess.

**Recall (candidate set).** Union of: Wikipedia-geotagged articles (English both regions; Malay for Malaysia); Wikidata items with coordinates whose class (P31) passes a curated allowlist; OSM features with candidate tags (`historic=*`, `tourism=attraction|artwork|viewpoint`, `memorial=*`, …); regional heritage registers (Historic England for UK; for Malaysia, a source feasibility check is part of WP-A1 — the national heritage register is included only if machine-readable, and nothing depends on it); Open Plaques. The decisive unglamorous work is the Wikidata class allowlist/blocklist — excluding parishes, companies, events, admin boundaries.

**Precision (the score).** A composite computed per place in the pipeline:

- *Heuristic signals:* article existence/length, sitelink count, median pageviews, heritage designation/grade, plaque presence, image availability, OSM tag-value rarity, class-based penalties.
- *LLM curiosity signal:* an LLM reads name + summary + tags and judges "would a curious person detour for this?" This attacks the gap heuristics can't: they measure fame and documentation, not interestingness. **Fame is not the product** — pageviews rank Big Ben top, but the app's joy is the overlooked-but-verified: low pageviews plus independent evidence of substance gets a deliberate boost.
- Formula and weights live in **pipeline config**; retuning = re-running the pipeline, never an app release. The LLM score is one weighted signal, never the sole gate.

**The tuning loop (the real answer).** A golden-set eval harness: 3–4 areas the developer knows intimately (London patch, KL area), ranked candidates dumped for hand-labelling (*yes / meh / no*), any weight config scored against the labels (precision@k). "What counts as interesting" becomes an empirical loop runnable in an afternoon. Built immediately after the pipeline skeleton.

**Presentation (density).** Scores bucket into tiers **T1 (landmark) → T4 (oddity)**; zoom gates tiers (city zoom shows T1–T2, street zoom shows all). Central London density is handled by tiering plus light clustering as a safety net, not a dedicated subsystem.

**Categories.** Filter chips ship in v1, but the taxonomy is a **pipeline deliverable, not a design-time invention**: the first extract run dumps the real distribution of Wikidata classes and OSM tags across both regions; 5–7 categories are derived from that audit, then chips are named from evidence.

## 5. Architecture

```
┌────────────────────────── Pipeline (Python CLI) ─────────────────────────┐
│ extract → reconcile → score (heuristics + LLM) → categorize → publish    │
│ laptop-first; later GHA on cron. State (ID registry, LLM cache) in R2.   │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │ static files, versioned
                     ┌─────────────▼──────────────┐
                     │ R2 · tiles.making-tracks.app│
                     │  place tiles + manifests    │
                     │  region basemap .pmtiles    │
                     └─────────────┬──────────────┘
                                   │ HTTPS / range requests
                     ┌─────────────▼──────────────┐
                     │ iOS app (SwiftUI)           │
                     │ MapLibre Native + PMTiles   │
                     │ GRDB (SQLite) user data     │
                     │ all user data on-device     │
                     └─────────────────────────────┘
```

No runtime compute anywhere in v1. Workers enter only in v2 (share links). Privacy posture: user data (visits, lists, snapshots) never leaves the device in v1.

### 5.1 Map layer: MapLibre Native + PMTiles (verified 2026-07)

- MapLibre Native iOS: healthy, active releases (ios-v6.27.0, June 2026). The official SwiftUI wrapper is pre-1.0 — **wrap `MLNMapView` ourselves** rather than depend on unstable API.
- PMTiles `pmtiles://` URLs supported natively since ios-v6.10.0 (remote HTTPS and local files) — no shim needed.
- **Offline gotcha:** MapLibre's OfflinePack API does not work with PMTiles sources. Region packs are therefore **whole-file downloads**: the pipeline pre-cuts a `.pmtiles` basemap per region (`pmtiles extract` against Protomaps hosted builds — no planet download); the app downloads the file and points the style at the local path.
- Serve from R2 behind the custom domain (not Cloudflare Pages, which drops range requests).
- MapKit rejected: no developer offline API, ToS forbid tile caching, minimal styling. Basemap style: muted/paper-like, authored as style JSON — the pins are the only saturated colour; the map's look carries the snow metaphor.

### 5.2 Pipeline (Python)

Plain CLI, region-parameterised (`uk`, `malaysia`), SQLite as working store between stages, deterministic and re-runnable. Zero coupling to any runner; GHA later is just cron + `concurrency` group (single writer to the registry).

1. **Extract** — per-source, per-region extractors producing normalized source records. OSM via `pyosmium` on Geofabrik extracts.
2. **Reconcile** — cluster source records into places. Anchor on Wikidata QID (OSM `wikidata=*` tags are a free join); fallback name-similarity + distance matching tuned **conservatively** — a false merge corrupts user data attached to the ID; a false split is merely ugly. Ambiguous middle cases can be LLM-adjudicated.
   **ID contract:** each cluster mints a stable `place_id` derived from its anchor ref. A persistent **ID registry** (in R2) guarantees: once shipped, a `place_id` is never reassigned; places vanishing upstream are tombstoned, never deleted.
3. **Score** — heuristic signals + LLM curiosity score → composite → tier. Config-driven weights.
4. **Categorize** — Wikidata classes + OSM tags → derived taxonomy; LLM for the long tail.
5. **Publish** — place tiles (geographically partitioned JSON, ~z10 cells, gzipped) + per-region manifest (tile index, version, counts, checksums) + region basemap `.pmtiles`, uploaded to R2 under a versioned path. **Manifest written last, atomically** — the app only ever sees complete versions.

**LLM usage (curiosity score, blurbs, category long-tail, reconciliation adjudication)** reuses the developer's existing batch pattern (Modal + open-weight models, or OpenRouter). Every LLM output is cached in R2 keyed by `(model, prompt_version, input_hash)` — re-runs touch only new/changed places; deterministic and cost-bounded. The eval harness decides empirically whether the LLM signal earns its weight.

**Eval harness** — golden-area candidate dumps, hand-label flow, precision@k scoring of any config; doubles as the ranking regression suite.

### 5.3 iOS app

- **Stack:** SwiftUI, iOS 17+, GRDB (SQLite) — chosen over SwiftData for R-tree spatial indexing and predictable migrations under a schema user history depends on.
- **Screens:** Map (Discovery) · Place card · Lists · Tracks · Region/settings.
- **Tile client:** manifest fetch → viewport tile fetch → local cache with versioned invalidation. Offline region pack = basemap `.pmtiles` + all region place tiles, checksum-verified, resumable.
- **Backup:** user DB in iCloud device backup by default (no CloudKit sync in v1).

### 5.4 User data schema (GRDB)

```sql
visits          (id, place_id, visited_at, verdict NULL, note NULL, created_at)
lists           (id, name, is_system, created_at)      -- ships with 'Want to go'
list_items      (list_id, place_id, added_at)
place_snapshots (place_id, name, lat, lon, category, tier, snapshot_json, fetched_at)
```

`place_snapshots` is written the first time a user visits or saves a place. It guarantees Tracks and lists render forever, independent of upstream data churn or tile eviction. **User history must never depend on someone else's database.**

Place data itself is read-only, delivered via tiles: `place_id`, names, lat/lon, category, tier, score, blurb, image URL, source refs (QID, OSM id, heritage entry), Wikipedia title.

## 6. Error handling

- **Pipeline:** a source being down fails that source's extract loudly; the run aborts — no partial publishes. Upstream changes never break the ID contract (tombstones). Registry updated only on successful publish.
- **App:** tiles unreachable → serve cache, quiet staleness indicator, never block the map. `place_id` missing from current tiles → render from `place_snapshots`. Downloads resumable + checksum-verified. LLM/blurb absence degrades gracefully (fall back to source description).

## 7. Testing

- **Pipeline:** golden-fixture tests per stage (small hand-built extracts → assert reconciliation outcomes, ID stability across re-runs, deterministic scores). Eval harness = ranking regression suite.
- **App:** unit tests on GRDB layer and derivations (seen, list progress); snapshot tests for pin states (unseen/saved/visited/loved × fade); one UI test for the core loop (find → save → mark seen → appears in Tracks).

## 8. Work packages

Each package is sized for one Opus agent to design in detail and one Codex agent to build. Contracts between packages (tile format, manifest schema, place JSON schema, `place_id` format) are fixed in the WP-A1/WP-B2 designs so tracks can proceed in parallel.

### Track A — Pipeline (Python)

| WP | Name | Contents | Depends on |
|---|---|---|---|
| A1 | Skeleton + extractors | CLI scaffold, region config, source-record model, SQLite working store; extractors: Wikidata, Wikipedia, OSM (pyosmium), Historic England, Open Plaques | — |
| A2 | Reconcile + ID registry | QID-anchored clustering, conservative fuzzy fallback, stable `place_id` minting, tombstones, R2-persisted registry | A1 |
| A3 | Data audit + taxonomy | Class/tag distribution dump over both regions; derive 5–7 categories; categorization rules | A1 |
| A4 | Heuristic scoring + tiers | Signal computation, config-driven composite, T1–T4 tiering | A2 |
| A5 | Eval harness | Golden-area dumps, hand-label flow, precision@k report for any config | A4 |
| A6 | LLM enrichment | Batch provider (reuse Modal/OpenRouter pattern), curiosity score, blurbs, category long-tail, reconciliation adjudication; R2 cache keyed (model, prompt_version, input_hash) | A2, A3 |
| A7 | Publisher | Place-tile emission, manifest, versioned atomic R2 publish, `pmtiles extract` region basemaps | A4 |

### Track B — iOS app (Swift)

| WP | Name | Contents | Depends on |
|---|---|---|---|
| B1 | App skeleton + user DB | Xcode project, GRDB schema + migrations, derivations (seen, progress), snapshot writes | — |
| B2 | Map screen | MLNMapView wrapper, PMTiles basemap, paper-style JSON, pin rendering for all states, fade treatment | B1 |
| B3 | Tile client | Manifest fetch, viewport tile loading, local cache + invalidation | B1 (contract from A7 design) |
| B4 | Place card + core loop | Detail card, one-tap mark seen, verdict heart, save-to-list | B2, B3 |
| B5 | Lists | 'Want to go' system list, create/manage, progress rendering | B4 |
| B6 | Tracks | Chronological visit log, loved filter, place-anchored rendering via snapshots | B4 |
| B7 | Offline region packs | Region download UI, whole-file pmtiles + place tiles, checksums, resumable | B3 |
| B8 | Discovery polish | Tier/zoom gating, clustering, category filter chips, hide-seen toggle, foreground nearby prompt | B4 |

### Track C — Services (post-v1)

| WP | Name | Contents | Depends on |
|---|---|---|---|
| C1 | Anonymised stats (v1.5) | Collector Worker (per-place counters, no IP/metadata logging), app opt-in screen + event scheduler (random-delay independent submission per §9) | B4 shipped |

**Suggested order:** A1 → A2 → A3/A4 (parallel) → A5 → A7, with A6 after A5 proves signal value cheaply. B1/B2 can start immediately (B2 against public Protomaps demo tiles); B3 once A7's contract is designed. First end-to-end milestone: A1–A4 + A7 producing real UK tiles, B1–B4 rendering them — the core loop on real data.

## 9. Privacy

**Principles (non-negotiable):** the developer must be *unable* to track users, not merely unwilling. No third-party analytics SDKs, no advertising identifiers, no accounts in v1. All user data (visits, lists, snapshots) stays on-device; tile fetches are anonymous static-file GETs.

**Opt-in anonymised stats (v1.5).** Default off. When enabled, the app submits aggregate-only events — (place_id, event_type ∈ {visited, bookmarked, loved}, date) — under these rules, which target *unlinkability*, the actual threat (a linkable event sequence is a movement trace even without a user ID):

- No user, device, or session identifiers of any kind.
- Timestamps coarsened to date only.
- Each event submitted independently, delayed by a random interval (hours-scale) — never at the moment of the visit, never batched with other events.
- Collector is a Cloudflare Worker that increments per-place counters and never logs IPs or request metadata.
- The opt-in screen states in plain language exactly what leaves the device.
- If scale ever warrants stronger guarantees, client-side randomized response can be layered on without changing the collection surface.

Aggregate counts may later feed ranking ("quietly loved by users") — an opt-in community signal, better than fame metrics.

**Sharing privacy & permissions (v2 requirements, captured now).** Per-list visibility is an explicit choice: **private** (only explicitly invited recipients can see it; requires an identity mechanism — deferred design) or **public link**. Permission tiers per share: **viewer** (read-only), **contributor** (add items, cannot remove), **editor** (full edit). Contributor/editor tiers imply server-mediated list state in v2; v1 schema needs no change (`list_items.added_by` arrives with sharing).

## 10. Out of scope for v1 (explicit)

Sharing/links, accounts, CloudKit sync, background location, Android/web, user-submitted places, reviews beyond the loved verdict, route planning (also: the app must never *look* like a route recorder — see naming risk).
