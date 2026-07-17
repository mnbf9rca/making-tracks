# Making Tracks — Design

**Date:** 2026-07-14
**Status:** approved design, pre-implementation
**App name:** Making Tracks · **Domain:** making-tracks.app (tiles served from tiles.making-tracks.app)
**Platform:** iOS (SwiftUI), solo developer
**Repo layout:** monorepo — `/pipeline` (Python), `/ios` (Swift), `/docs` (principles, specs, plans), `AGENTS.md` at root (agent ground rules; see `docs/PRINCIPLES.md`)

---

## 1. Product summary

A map app that surfaces interesting things around you — history, architecture, oddities, landmarks — from open databases (Wikipedia/Wikidata, OpenStreetMap, regional heritage registers). The map is fresh snow: moving through the world marks it. Discovery is subtractive — the map starts full of possibility and your life gradually consumes it.

Two views over the same data:

- **Discovery** — seen places are faded, not hidden. Low opacity, still tappable. An on-map **"Fresh snow"** toggle hides seen places entirely for those who want the clean version — active: only untrodden ground; inactive: everything, tracks and all. A first-class map control that teaches the metaphor in two words (if a two-pole control wins in design, the poles are **"Fresh snow" / "My tracks"**), working identically when viewing a list on the map.
- **Tracks** — the chronological, place-anchored record of where you've been. First-class screen: it is the shareable artefact and the retention mechanism.

**Naming risk (drives App Store packaging):** "tracks" reads as GPX/route recording. The subtitle and first screenshot must immediately establish this is *discovery*, not route logging.

## 2. Scope

**v1 (the solo loop):** map discovery, search/jump-to-location, save-to-list, mark seen, Tracks history, local lists, category filters, offline region packs, onboarding/first-run. Regions: **UK and Malaysia**.

**v2 (deliberately deferred, schema-ready):** list sharing (see §9 for the privacy/permission requirements captured now), CloudKit sync, background nearby notifications, more regions.

**v1.5 (after first TestFlight):** opt-in anonymised aggregate stats and place feedback (§9, WP-C1/C2).

Geographic modularity is a day-one constraint: region-specific sources (e.g. Historic England) are optional per-region enrichments, never load-bearing columns. Malaysia deliberately stress-tests ranking where enrichment is thin.

## 3. Core model decisions (settled)

### 3.1 Seen is global per user, stored as an event log

`seen` attaches to the **place**, globally per user — never to a (place, list) pair. The map is itself a list (the universal one); per-list seen-state would let the map and a list disagree about the same place, making "have I seen this?" unanswerable and breaking the snow metaphor.

Storage is a **visit-event log**, not a boolean: `visits(id, place_id, visited_at, verdict)`. "Seen" = derived: place has ≥1 visit. This buys:

- Tracks is the event log rendered chronologically — no separate history model.
- Re-visits are representable.
- Un-marking seen = deleting an event (reversible, nothing destroyed).
- Per-list freshness ("visited since joining this list") is a future *query*, not stored state — visit timestamps vs list-join timestamps.

**The gift problem is presentation, not state.** One stored fact, context-appropriate rendering. A list's *item view* leads with progress — "you've been to 3 of these · 7 to go", visited items checked. A list's *map view* fades visited pins exactly like discovery does: fading is what makes it easy to work your way through the remainder of a list. The anti-goal is only the framing — a received list opens on recognition and progress, never on "30% consumed".

### 3.2 Bookmarks are a list

One mechanism: **lists**. The app ships with a system list "Want to go"; the quick-save tap adds to it. Custom lists ("Date nights", "KL trip") are the same mechanism — this is the Google/Apple Maps saved-places pattern users already know.

- Marking seen never mutates list membership. Every list renders visit-progress the same way ("3 of 12 visited"), which is exactly how shared lists will render in v2.
- Pin states are **two orthogonal axes**, and every cell of the matrix is defined: saved ∈ {no, yes} × visit ∈ {none, visited, loved}. Precedence rule: the **visit axis drives fade** (visited and loved pins fade; loved additionally keeps a heart badge); the **saved axis contributes an independent bookmark badge that persists through fading**. So saved+visited = faded pin with bookmark badge; saved+loved = faded pin with bookmark and heart badges. This matters because saved-then-visited is the *guaranteed end state of the core loop*, not an edge case. Bookmark is intent, visit is history; orthogonal, not a state machine.
- The "Fresh snow" toggle lives on the map screen itself (discovery and list-map views alike).

### 3.3 Verdict: "worth going again"

`visits.verdict` is a nullable field (v1 values: `loved` or null). Offered as an optional one-tap heart at the mark-seen moment; skippable, editable or removable later from the place card or the visit's row in Tracks. Powers a "Loved" filter in Tracks and a distinct map marker: visited pins fade to the standard seen treatment; loved pins fade but keep a heart-badged marker so favourites stay findable on the snow.

### 3.4 Marking seen: one tap once the place is in front of you

No confirmation, fully reversible. "One tap" means one tap *in the place card/callout* — two physical taps from the map, zero ceremony — not literally one tap on a pin (which would mis-mark constantly in dense areas). No auto-marking from geolocation. Nearby prompts ("You're near X — seen it?") are **foreground-only in v1**; background nudges are a deliberate v2 decision (always-on location permission, battery, review friction).

## 4. "What counts as interesting" (the make-or-break problem)

Nobody can know the ranking at design time; "interesting" is a taste function that must be measured, not asserted. The design deliverable is **machinery to iterate cheaply** plus a defensible first guess.

**Recall (candidate set).** Union of: Wikipedia-geotagged articles (**English-only for now**; language is a per-region config option in the extractor so Malay and others can be enabled later without structural change); Wikidata items with coordinates whose class (P31) passes a curated allowlist; OSM features with candidate tags (`historic=*`, `tourism=attraction|artwork|viewpoint`, `memorial=*`, …); regional heritage registers (Historic England for UK; for Malaysia, a source feasibility check is a separate small spike under WP-A1d — the national heritage register is included only if machine-readable, and nothing depends on it); Open Plaques. The decisive unglamorous work is the Wikidata class allowlist/blocklist — excluding parishes, companies, events, admin boundaries.

**Precision (the score).** A composite computed per place in the pipeline:

- *Heuristic signals:* article existence/length, sitelink count, median pageviews, heritage designation/grade, plaque presence, image availability, OSM tag-value rarity, class-based penalties.
- *LLM curiosity signal:* an LLM reads name + summary + tags and judges "would a curious person detour for this?" This attacks the gap heuristics can't: they measure fame and documentation, not interestingness. **Fame is not the product** — pageviews rank Big Ben top, but the app's joy is the overlooked-but-verified: low pageviews plus independent evidence of substance gets a deliberate boost.
- Formula and weights live in **pipeline config**; retuning = re-running the pipeline, never an app release. The LLM score is one weighted signal, never the sole gate.

**The tuning loop (the real answer).** A golden-set eval harness: 3–4 areas the developer knows intimately (London patch, KL area), ranked candidates dumped for hand-labelling (*yes / meh / no*), any weight config scored against the labels (precision@k). "What counts as interesting" becomes an empirical loop runnable in an afternoon. Built immediately after the pipeline skeleton.

**User feedback closes the loop (v1.5, WP-C2).** The place card gains "report a problem" — *not there any more / closed / wrong location / not interesting / inappropriate* + optional text. Submitted with no identifiers (same privacy rules as §9 stats). Feedback lands in R2 and the pipeline consumes it — but **strictly as advisory input: feedback never auto-suppresses a place**. An identifier-free public endpoint is Sybil-abusable (one scripted actor could otherwise bury a rival's site or vandalise a town's map), so suppression or the "inappropriate" flag takes effect only after N independent, IP/time-diverse reports *and* human review. Free text is length-capped and scrubbed, and is explicitly on §5.5's untrusted-input list — it is the one input authored by arbitrary internet actors with intent. Within those gates, it's the first quality signal that comes from the street rather than a database.

**Malaysia sanity floor.** With English-only recall and no reliable pageview signal, Malaysia's scoring must not collapse to LLM-only (the LLM is never the sole gate): heritage designations, OSM tag rarity, article existence/length, and image availability all exist without pageviews, and WP-A5's eval explicitly checks that a KL golden area ranks acceptably with the LLM signal switched off.

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
- **Region pack budget:** packs have a fixed max basemap zoom and a stated per-region size budget; WP-A0 must include **measured** sizes for the UK and Malaysia extracts before B7 is designed. If a country-granularity blob exceeds a usable budget (guideline: low single-digit GB on WiFi), sub-region packs (nations/metros) are cut instead — a pipeline knob, not an app change. Downloads are WiFi-preferred, background `URLSession`, storage-headroom-checked. Refresh follows §5.6: a pack records its manifest version; the app offers refresh when the manifest moves on, and an old pack keeps working meanwhile.
- **Pin rendering architecture (mandated):** place pins are runtime features from the tile client, not part of the basemap, and they use **GeoJSON `MLNShapeSource` + symbol/circle style layers** — never `MLNAnnotation`/`MLNAnnotationView`, which is rejected for the same density reason MapKit was (collapses in Central London, no clustering). Consequences, fixed here so B2/B4/B8 share one substrate: fade is a **data-driven opacity expression**; loved/bookmark badges are additional symbol layers; clustering uses `MLNShapeSourceOptionClustered`; tap is feature hit-testing (`visibleFeatures(at:)`).
- Serve from R2 behind the custom domain (not Cloudflare Pages, which drops range requests).
- MapKit rejected: no developer offline API, ToS forbid tile caching, minimal styling. Basemap style: muted/paper-like, authored as style JSON — the pins are the only saturated colour; the map's look carries the snow metaphor.

### 5.2 Pipeline (Python)

Plain CLI, region-parameterised (`uk`, `malaysia`), SQLite as working store between stages, deterministic and re-runnable. Zero coupling to any runner; GHA later is just cron + `concurrency` group (single writer to the registry).

1. **Extract** — per-source, per-region extractors producing normalized source records. OSM via `pyosmium` on Geofabrik extracts.
2. **Reconcile** — cluster source records into places. Anchor on Wikidata QID (OSM `wikidata=*` tags are a free join); fallback name-similarity + distance matching tuned **conservatively** — a false merge corrupts user data attached to the ID; a false split is merely ugly. Ambiguous middle cases can be LLM-adjudicated.
   **ID contract:** each cluster mints a stable `place_id` derived from its anchor ref. A persistent **ID registry** (in R2) guarantees: once shipped, a `place_id` is never reassigned; places vanishing upstream are tombstoned, never deleted.
   **Upstream churn does not break the contract.** Wikidata merges QIDs routinely (the loser becomes a redirect); OSM features gain and lose `wikidata=*` tags. The registry is therefore keyed on the **union of every source ref ever clustered** into a place (all QIDs, OSM ids, register entries), with explicit merge/split rules; every run resolves Wikidata redirects and maps merged QIDs onto the **existing** `place_id` — never minting a new one for a place we've shipped. §7 carries a dedicated regression test: *QID A merged into B keeps `place_id` stable.*
3. **Score** — heuristic signals + LLM curiosity score → composite → tier. Config-driven weights.
4. **Categorize** — Wikidata classes + OSM tags → derived taxonomy; LLM for the long tail.
5. **Publish** — place tiles (geographically partitioned JSON, ~z10 cells, gzipped) + per-region manifest (tile index, version, counts, checksums) + region basemap `.pmtiles`, uploaded to R2 under a versioned path. **Manifest written last, atomically** — the app only ever sees complete versions.

**LLM usage (curiosity score, blurbs, category long-tail, reconciliation adjudication)** reuses the developer's existing batch pattern (Modal + open-weight models, or OpenRouter). Every LLM output is cached in R2 keyed by `(task_id, model, prompt_version, input_hash)` — the `task_id` component is load-bearing: curiosity, blurb, and category tasks consume near-identical input, so without it same-shape outputs collide silently (a category label shipping in the blurb field would pass schema validation). Cached outputs are schema-validated against their task's expected shape **on read**. The manifest records the prompt-version set that produced each published tiering, so eval labels stay tied to the config that generated them. Re-runs touch only new/changed places; deterministic and cost-bounded. The eval harness decides empirically whether the LLM signal earns its weight.

**Eval harness** — golden-area candidate dumps, hand-label flow, precision@k scoring of any config; doubles as the ranking regression suite.

### 5.3 iOS app

- **Stack:** SwiftUI, **iOS 18+** minimum (revisit at ship time — by launch iOS 18 will be ~3 majors old; nothing in this stack needs iOS 26 APIs, and MapLibre supports far older). **Swift 6 language mode with strict concurrency from day one** — a toolchain setting independent of deployment target, and vastly cheaper than retrofitting. Containment: the MapLibre wrapper is a `@MainActor`-isolated boundary using `@preconcurrency import` (MLN types are un-Sendable ObjC); all map mutations happen on the main actor, and the tile client hands the wrapper plain `Sendable` value types, never MLN objects — the concurrency cost stays inside the wrapper instead of leaking across B2/B3/B4. GRDB (SQLite) — chosen over SwiftData for **predictable, testable migrations and raw-SQL control** under a schema user history depends on. (v1 uses no R-tree: the fade render is a keyed membership lookup, not a spatial query — see §5.4; the nearby prompt scans the already-loaded viewport places in memory.)
- **Screens:** Map (Discovery) · Search · Place card · Lists · Tracks · Onboarding/first-run · Region/settings.
- **Search (v1):** name lookup over region place data + geocoding to jump the map ("Edinburgh next month" must have an entry point that isn't panning across the planet). Simple is fine; absent is not.
- **Tile client:** manifest fetch → viewport tile fetch (padded prefetch around the viewport, aggressive caching — also a privacy property, §9) → local cache with versioned invalidation. Offline region pack = basemap `.pmtiles` + all region place tiles, checksum-verified, resumable.
- **Backup:** user DB in iCloud device backup by default (no CloudKit sync in v1).

### 5.4 User data schema (GRDB)

```sql
visits          (id, place_id, visited_at, verdict NULL, created_at)
lists           (id, name, is_system, created_at)      -- ships with 'Want to go'
list_items      (list_id REFERENCES lists ON DELETE CASCADE, place_id, added_at, PRIMARY KEY (list_id, place_id))
place_snapshots (place_id, name, lat, lon, category, tier, snapshot_json, fetched_at)

CREATE INDEX idx_visits_place ON visits(place_id);
CREATE INDEX idx_list_items_place ON list_items(place_id);
```

The hot query is the **viewport state resolve**: for each render, the tile client supplies the visible `place_id`s (hundreds at street zoom) and the app answers saved?/visited?/loved? per place — a batched keyed lookup against the two indexes above (or an in-memory `Set` cache maintained from them), *not* a spatial query. A per-visit note field is deliberately absent from v1 (it edges into reviews, which §10 excludes); like `list_items.added_by`, it arrives by migration if a note feature is ever designed.

`place_snapshots` is written the first time a user visits or saves a place. It guarantees Tracks and lists render forever, independent of upstream data churn or tile eviction. **User history must never depend on someone else's database.**

Place data itself is read-only, delivered via tiles: `place_id`, names, lat/lon, category, tier, score, blurb, image URL, source refs (QID, OSM id, heritage entry), Wikipedia title.

### 5.5 Untrusted data posture

Source data is open-world and must be assumed polluted — vandalized Wikipedia text, malformed OSM geometry, hostile strings anywhere.

- **Pipeline:** defensive parsing at every extractor (schema-validate, coordinate bounds-check, string length caps, control-character stripping); URLs validated (https-only, expected hosts for images); nothing from a source is ever interpolated into a shell command, SQL string, or LLM prompt without escaping/delimiting; LLM outputs are themselves untrusted (schema-validate before use). **User-submitted feedback (WP-C2) is the most hostile input of all** — authored by arbitrary internet actors with intent: length-capped, scrubbed, advisory-only (§4), moderated before any effect, and never placed in an LLM prompt without the same delimiting as source text.
- **App:** tile content is untrusted input even though we published it (defence in depth — the bucket could be compromised, or the pipeline fooled). Strict typed decoding with length/size caps; malformed tiles are skipped, never crash the map; place text rendered as plain text only (no HTML/attributed rendering of source content); image URLs fetched only over https from the expected host.

### 5.6 Versioning contract

Everything that crosses a boundary is explicitly versioned, and every reader knows what it understands:

- **Manifest and tile format** carry a `schema_version`. The app declares its maximum understood version: *newer* data → app keeps serving its cached older version and surfaces "update the app to get new data"; a **fresh install** with no cache on a too-old app shows an explicit "update required" state rather than an empty map; *older* data (mid-transition) → tolerated within a documented window. Never silently misread.
- **User DB** migrations are monotonic and numbered (GRDB migrations); the app refuses to open a DB from a newer app version rather than corrupt it (relevant to backup restore across app versions).
- **Pipeline artefacts** — ID registry, LLM cache entries (already keyed by `prompt_version`), scoring config — all carry versions so a run knows exactly what it's reading.
- Publishes are versioned paths (§5.2); rollback = repointing the manifest.

## 6. Error handling

- **Pipeline:** a source being down fails that source's extract loudly; the run aborts — no partial publishes. Upstream changes never break the ID contract (tombstones). Registry updated only on successful publish.
- **App:** tiles unreachable → serve cache, quiet staleness indicator, never block the map. `place_id` missing from current tiles → render from `place_snapshots`. Downloads resumable + checksum-verified. LLM/blurb absence degrades gracefully (fall back to source description).

## 7. Testing

- **Pipeline:** golden-fixture tests per stage (small hand-built extracts → assert reconciliation outcomes, ID stability across re-runs, deterministic scores). **Upstream-churn regression tests are mandatory:** QID A merged into B keeps `place_id` stable; an OSM feature gaining/losing its `wikidata=*` tag keeps `place_id` stable; a vanished source tombstones rather than reminting. Eval harness = ranking regression suite.
- **App:** unit tests on GRDB layer and derivations (seen, list progress); snapshot tests enumerating the **full pin matrix** — saved ∈ {0,1} × visit ∈ {none, visited, loved} (§3.2 precedence rule); one UI test for the core loop (find → save → mark seen → appears in Tracks).

## 8. Work packages

Each package is sized for one Opus agent to design in detail and one Codex agent to build. Cross-track contracts (tile format, manifest schema, place JSON schema, `place_id` format) are pinned **up front in WP-A0** — before any build in either track — because they materialize across A2 (`place_id`) and A7 (tiles/manifest) otherwise far too late for Track B to proceed safely.

### Track A — Pipeline (Python)

| WP | Name | Contents | Depends on |
|---|---|---|---|
| A0 | Contracts | The authoritative doc pinning tile format, manifest schema, place JSON schema, `place_id` format, region config format; **measured** UK/Malaysia basemap sizes vs the §5.1 pack budget | — |
| A1 | Skeleton | CLI scaffold, region config, source-record model (the interface every extractor implements), SQLite working store | A0 |
| A1b | Wiki extractors | Wikidata + Wikipedia extractors (SPARQL/dump + geotagged articles), hardened per §5.5 | A1 |
| A1c | OSM extractor | pyosmium over Geofabrik extracts, candidate-tag filtering, hardened per §5.5 | A1 |
| A1d | Register extractors | Historic England + Open Plaques; separate small spike: Malaysia heritage-register feasibility | A1 |
| A2 | Reconcile + ID registry | QID-anchored clustering, redirect/merge resolution, union-of-refs registry keying, conservative fuzzy fallback, tombstones, R2-persisted registry, churn regression tests (§7) | A1b, A1c, A1d |
| A3 | Data audit + taxonomy | Class/tag distribution dump over both regions; derive 5–7 categories; categorization rules | A1b, A1c, A1d |
| A4 | Heuristic scoring + tiers | Signal computation, config-driven composite, T1–T4 tiering, Malaysia non-LLM sanity floor (§4) | A2 |
| A5 | Eval harness | Golden-area dumps, hand-label flow, precision@k report for any config | A4 |
| A6 | LLM enrichment | Batch provider (reuse Modal/OpenRouter pattern), curiosity score, blurbs, category long-tail, reconciliation adjudication; R2 cache keyed (task_id, model, prompt_version, input_hash) | A2, A3 |
| A7 | Publisher | Place-tile emission, manifest (incl. prompt-version provenance), versioned atomic R2 publish, `pmtiles extract` region basemaps within the §5.1 budget | A0, A4 |

### Track B — iOS app (Swift)

| WP | Name | Contents | Depends on |
|---|---|---|---|
| B1 | App skeleton + user DB | Xcode project, GRDB schema + migrations + indexes (§5.4), derivations (seen, progress, viewport state resolve), snapshot writes | A0 |
| B2 | Map screen | MLNMapView wrapper (@MainActor boundary), PMTiles basemap, paper-style JSON, shape-source + style-layer pin substrate (§5.1): full pin matrix, data-driven fade, badges | B1 |
| B3 | Tile client | Manifest fetch, viewport tile loading with padded prefetch, local cache + invalidation | B1, A0 |
| B4 | Place card + core loop | Detail card via feature hit-testing, one-tap mark seen, verdict heart, save-to-list | B2, B3 |
| B5 | Lists | 'Want to go' system list, create/manage, progress rendering, list-map fading | B4 |
| B6 | Tracks | Chronological visit log, loved filter, verdict editing, place-anchored rendering via snapshots | B4 |
| B7 | Offline region packs | Region download UI (WiFi-preferred, background URLSession, storage check), whole-file pmtiles + place tiles, checksums, resumable, refresh per §5.6 | B3 |
| B8 | Discovery polish | Tier/zoom gating, clustering (MLNShapeSourceOptionClustered), category filter chips, on-map "Fresh snow" toggle, foreground nearby prompt (scans loaded viewport places) | B4 |
| B9 | Search | Name lookup over region place data + geocode, jump-to-location | B3 |
| B10 | Onboarding / first-run | Region pick → pack download offer (privacy framing) → populated map → metaphor intro, location-permission priming, stats opt-in prompt (v1.5 activates it), empty/unsupported-region states, "update required" state (§5.6) | B4, B7 |
| B11 | App Store packaging | Subtitle/screenshots/keywords executing the §1 naming-risk correction; privacy policy + App Privacy label + UK-GDPR/PDPA checklist (§9) | ship gate |

### Track C — Services (v1.5)

| WP | Name | Contents | Depends on |
|---|---|---|---|
| C1 | Anonymised stats | Relay-fronted collector (no source IPs reach it), small-N suppression, per-place counters; app event scheduler (random-delay independent submission per §9); onboarding prompt activation | B10 shipped |
| C2 | Place feedback | "Report a problem" on place card, identifier-free collector, **advisory-only** pipeline input (N diverse reports + human review before any effect, §4), moderation path | B4 shipped |

**Suggested order:** A0 first (unblocks everything). Then A1 → A1b/c/d (parallel) → A2 → A3/A4 (parallel) → A5 → A7, with A6 after A5 proves signal value cheaply. B1/B2 immediately after A0 (B2 against public Protomaps demo tiles); B3 in parallel against A0's contract. First end-to-end milestone: real UK tiles from A7 rendered by B1–B4 — the core loop on real data. B9–B11 before TestFlight.

## 9. Privacy

**Principles (non-negotiable):** the developer must be *unable* to track users, not merely unwilling — and where a channel falls short of that bar, the spec says so honestly rather than claiming anonymity it doesn't have. No third-party analytics SDKs, no advertising identifiers, no accounts in v1. All user data (visits, lists, snapshots) stays on-device.

**The tile-fetch location channel (acknowledged, mitigated).** Online viewport browsing issues tile GETs to `tiles.making-tracks.app`; Cloudflare terminates TLS and sees source IP + tile coordinates + time at the edge regardless of our code. Tiles are coarse (~z10 cells, reflecting where you *look*, not GPS), and standard R2 serving gives the developer no per-request IP logs — but the honest statement is "the CDN sees your IP like any website", not "anonymous". Mitigations, in order of strength: **offline region packs eliminate the channel entirely** (one dense country-scale blob — downloading "UK" locates you to a set of tens of millions, i.e. nowhere — then zero per-viewport fetches; packs are named a privacy feature and onboarding steers users to one); online, the padded-prefetch + aggressive caching in §5.3 decouples requests from live viewport movements.

**The map-fetch channel — bundle-first + cover-traffic (2026-07-17 amendment).** *[Rob-gated — see `docs/superpowers/amendments/2026-07-17-privacy-commitments-amendment.md`.]* The download model unifies streaming and offline packs under one **index + bundle** fetch layer (region-model design, #131 §7): the committed default is **downloading bundles, not per-viewport streaming** (streaming is the honest interim/fallback). Sub-country downloads — finer than the country-scale blob above — are a movement trace, and are sanctioned only **with cover-traffic**: decoy fetches indistinguishable from the real one on every axis Cloudflare observes (spatial spread, timing/order, request size/count, and actually reaching the edge), drawn from a cohort chosen **independently of the user's real location**. Offline packs remain the strongest point (zero recurring movement fetches). The privacy win is chunky prefetch + indistinguishable decoys, **not** "small bundles" — small bundles are only the composition unit. Minimum online granularity, decoy count, and cohort policy are Rob's parameters (P15), not baked in the design.

**Aggregate bundle-download counts (2026-07-17 amendment).** *[Rob-gated.]* The developer may count how many times each bundle is downloaded (to see which areas need work) as **aggregate, user-unlinked totals** — Cloudflare aggregate analytics, never per-request IP logs. This carries no movement trace and is distinct from the opt-in behavioural stats below; the unlinkability bar is met by construction.

**Accounts & sync (v2) — data-minimized (2026-07-17 amendment).** *[Rob-gated.]* The v2 account (for private sharing) stores only the sharing identity and the lists you chose to share — never visits, map, or history, never a tracking hook — and is never needed to use the app for yourself. v2 CloudKit sync keeps its contents private to the user under their own Apple account; the developer never sees them. (The sharing permission tiers — viewer / contributor / editor — are already captured under "Sharing privacy & permissions" below; unchanged.)

**Opt-in anonymised stats (v1.5).** Default off; offered once during onboarding (skippable, plain-language: exactly what leaves the device) and changeable in settings. When enabled, the app submits aggregate-only events — (place_id, event_type ∈ {visited, bookmarked, loved}, date) — under rules that target *unlinkability*, the actual threat (a linkable event sequence is a movement trace even without a user ID):

- No user, device, or session identifiers of any kind; timestamps coarsened to date only.
- Each event submitted independently, delayed by a random interval (hours-scale) — never at the moment of the visit, never batched with other events.
- **Worker log hygiene is not the guarantee.** Cloudflare the platform sees client IPs on every request regardless of what our Worker logs (`cf-connecting-ip`, platform analytics) — so submissions route through a **relay (Oblivious-HTTP-style) so the collector never sees source IPs at all**. That restores "unable", not "unwilling".
- **Small-N suppression.** The scheme is weakest at launch, when one opted-in user in a small town is effectively k=1 and their rare place_ids self-identify. The collector therefore suppresses low-count cells: a per-place count exists only once enough independent reports accumulate; below the threshold the data effectively vanishes rather than describing a person.
- Client-side randomized response can be layered on later without changing the collection surface (note: it needs volume too — suppression and the relay are the load-bearing fixes at small N).

Aggregate counts may later feed ranking ("quietly loved by users") — an opt-in community signal, better than fame metrics.

**Ship-blocking compliance checklist (owned by WP-B11):** publish a privacy policy URL (App Store Guideline 5.1.1 requires it even for zero-collection apps) covering Cloudflare's IP processing on tile serving and, at v1.5, the opt-in stats payload; complete the App Privacy label honestly (v1: no data collected; v1.5: opt-in usage data, "not linked to you"); note UK-GDPR lawful basis and Malaysia PDPA applicability.

**Sharing privacy & permissions (v2 requirements, captured now).** Per-list visibility is an explicit choice: **private** (only explicitly invited recipients can see it; requires an identity mechanism — deferred design) or **public link**. Permission tiers per share: **viewer** (read-only), **contributor** (add items, cannot remove), **editor** (full edit). Contributor/editor tiers imply server-mediated list state in v2; v1 schema needs no change (`list_items.added_by` arrives with sharing).

## 10. Out of scope for v1 (explicit)

Sharing/links, accounts, CloudKit sync, background location, Android/web, user-submitted places, reviews beyond the loved verdict, route planning (also: the app must never *look* like a route recorder — see naming risk).
