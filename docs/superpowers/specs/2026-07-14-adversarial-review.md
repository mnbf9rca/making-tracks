# Making Tracks — Spec Review Synthesis

Adversarial review of `docs/superpowers/specs/2026-07-14-making-tracks-design.md`. Sixteen findings survived cross-examination by independent refuters. They are deduplicated (converging lenses noted), then ranked by severity and impact. Several findings had their *severity* trimmed by refuters without being refuted; those adjustments are reflected below.

---

## Critical

### 1. A Wikidata QID merge silently breaks `place_id` stability and corrupts user data
**Severity: critical · §5.2 · pipeline**

`place_id` is "derived from its anchor ref," and the registry is meant to guarantee IDs are never reassigned. But Wikidata merges duplicate items routinely; the losing QID becomes a redirect and stops appearing as a live coordinate-bearing item in the next dump. So on the next run a cluster that anchored on `Q123` (→ `place_id X`) re-anchors on the winner `Q456` and mints a **new** `place_id Y`, while `X` loses its live source and gets tombstoned. `place_snapshots` keeps Tracks rendering the old visit, but the live map now shows the place as fresh unseen snow — so "have I seen this?" answers **wrong** on the live map. This violates Principles 7, 8 and 1 in exactly the way they exist to prevent, and it is silent and effectively irreversible once IDs ship. The identical failure occurs when a place's anchor source changes (an OSM feature gains/loses a `wikidata=*` tag). §7's "ID stability across re-runs" test only exercises *unchanged* input, so a naive anchor-keyed implementation passes the stated tests and still fails here. A pure-Wikidata place (a plaque with no OSM join) has the QID as its only ref, so redirect resolution is genuinely required — union-of-refs alone cannot rescue it.

**Spec change:** Resolve Wikidata redirects/merges every run and map a merged QID onto the **existing** `place_id` rather than minting a new one. Key the registry on the union of every source ref ever clustered (all QIDs + OSM ids), with explicit merge/split rules. Add a regression test: *QID A merged into B keeps `place_id` stable.*

---

### 2. The tile/manifest/`place_id` contract has three conflicting owners; the real one (A7) is last
**Severity: critical (refuters lean "major") · §8 · delivery**

§8's intro claims the cross-track contracts (tile format, manifest schema, place-JSON schema, `place_id` format) are "fixed in the WP-A1/WP-B2 designs so tracks can proceed in parallel." But A1 produces only a CLI scaffold + source-record model + extractors, and B2 is the map screen — neither emits a tile, manifest, or `place_id`. `place_id` is actually minted in **A2**; tiles/manifest/place-JSON are emitted by **A7**, the tail of Track A (A7←A4←A2←A1). The spec contradicts its own intro: the B3 row says "contract from A7 design" and the suggested order concedes "B3 once A7's contract is designed." So a build agent picking up B3 (or the offline-pack B7) has no authoritative contract and must either block on the last Track A design or invent a schema A7 later contradicts — corrupting the `place_id`/versioning contracts Principles 7 and 11 protect. This silently breaks Principle 18 ("contracts before parallelism") while appearing to satisfy it. (Refuters note B1/B2 *can* still parallelise, so "collapses the parallel story" overstates it — but the misattribution and missing up-front contract are real.)

**Spec change:** Carve the contract into one explicit up-front deliverable (a WP-A0 / "A7-contract-first" doc) pinning tile format, manifest schema, place-JSON schema and `place_id` format before any A-build and before B1/B3 build. Correct the §8 intro to name **A2** (`place_id`) and **A7** (tiles/manifest) as the true sources.

---

### 3. The pin-rendering architecture is unnamed, and clustering (B8) contradicts the path B2 will naturally pick
**Severity: critical (refuters lean "major") · §5.1 / §8 (B2, B8) · iOS**

Pins are runtime features from the tile client, not part of the PMTiles basemap, so B2 must choose one of two mutually exclusive MapLibre Native architectures — and the spec never names one. Path A (`MLNPointAnnotation`/`MLNAnnotationView`) gives trivial per-pin fade and free tap-callouts, but collapses at Central London density and has **no** clustering. Path B (`MLNShapeSource` GeoJSON + symbol/circle layers) GPU-scales and is the **only** path that supports the native clustering (`MLNShapeSourceOptionClustered`) that B8 explicitly requires — but fade must become a data-driven opacity expression, "loved" a second badge layer, and tap manual hit-testing. §4's framing of clustering as "light… a safety net, not a dedicated subsystem" actively biases a B2 agent toward the annotation path. The concrete failure: B2 builds annotation-view pins (SwiftUI-friendly), B4 wires the place card to annotation selection, then B8 discovers clustering is impossible — forcing a rewrite of the pin layer **and** B4's tap/selection wiring. §5.1 already commits to MapLibre-internal decisions at this altitude (OfflinePack/PMTiles workaround, R2 range requests, self-wrapping `MLNMapView`), so this belongs there too.

**Spec change:** In §5.1/B2, mandate the shape-source + style-layer architecture (GeoJSON `MLNShapeSource` → symbol/circle layers) as the pin contract: fade as a data-driven opacity expression, "loved" as a badged symbol layer, clustering via `MLNShapeSourceOptionClustered`, tap via feature hit-testing — so B4's selection and B8's clustering share one substrate. State explicitly that `MLNAnnotation` is rejected for the same density reason MapKit was.

---

### 4. "Anonymous" tile fetches are an always-on location trace — and "unable to track users" isn't literally true
**Severity: critical (refuters lean "medium") · §9 · privacy-security** — *converges with findings 5 and 6 below; three privacy findings share one root cause, which strengthens the observation.*

§9 asserts "tile fetches are anonymous static-file GETs," but any user without an offline pack (all new users; anyone browsing an unpacked region) issues a stream of viewport tile GETs to `tiles.making-tracks.app`. Cloudflare terminates TLS and records source IP + requested tile coordinates + timestamps at the edge, independent of any Worker code. For in-the-field GPS-centred use (the app's primary mode, §3.4 nearby prompts) that sequence is a real-time movement trace keyed to an IP, default-on, with no opt-in — a larger version of the exact threat §9's stats design labours to prevent, and a contradiction of Principles 14 (unable, not unwilling) and 15 (a linkable place-event sequence is a movement trace). Offline region packs neutralise this (whole-file download → zero per-viewport fetch) but the spec never frames them as a privacy property. (Refuters temper severity: tiles are coarse ~z10 cells reflecting where you *look*, and on standard R2 pricing the developer can't retrieve per-request IP logs — so the defect is the false "anonymous" label and the un-flagged channel, not a live tracking capability.)

**Spec change:** Stop describing tile GETs as "anonymous." Acknowledge the tile-fetch location channel in §9; name offline region packs as the mitigation and steer users to download their region; for online use, prefetch a padded area and cache aggressively so requests don't track the live viewport. Soften "unable to track" to what is true (no app-level identifiers, no accounts, on-device by default, CDN sees IP like any website).

---

### 5. No search or go-to-location — the bookmark-now-visit-later loop has no entry point for a trip
**Severity: critical (refuters lean "moderate/high") · missing · product**

The screen list (§5.3) is Map / Place card / Lists / Tracks / Settings, and no §8 work package includes geocoding, name lookup, or jump-to-place; §10's out-of-scope list doesn't mention search either, so it is an *unreasoned omission*, not a deliberate deferral. With region packs whole-file and region-scoped, a user prepping the highest-intensity discovery journey — "I'm going to Edinburgh next month, what's interesting there?" — can only pan and zoom the map by hand across the planet, and there is no way to find a specific named place. (Refuters correctly narrow the claim: the *proximity* loop works fine from a geolocation-centred map with no search, and saved places are re-findable via Lists → map, so "the loop cannot start without it" is overstated. But search is a genuine, foreseeable gap, and — being purely additive, touching none of the `place_id`/tile/manifest contracts — it is cheap to add.)

**Spec change:** Add a place/location search work package to v1 (B-track): geocode + name lookup over the region manifest, jumping the map to a matched coordinate and loading that viewport's tiles. It can be simple, but it must exist.

---

## Important

### 6. Opt-in stats make the Worker *unwilling*, not the developer *unable* — and the scheme is weakest at launch
**Severity: important · §9 · privacy-security** *(converges with finding 4)*

§9 rests unlinkability on "a Worker that never logs IPs" plus hours-delayed independent events. But Cloudflare terminates the connection: the client IP is present on every request (`cf-connecting-ip`, platform analytics, abuse logging) regardless of what the Worker logs, so the developer remains *capable* of correlating IP → `place_id` → date. That fails Principle 14's structural-incapability bar. Worse, v1.5 ships right after the first TestFlight — the smallest possible opted-in population. One user in a small Malaysian town opting in gives daily volume of effectively k=1: IP re-groups the "independent" events into a per-person trace, and hours-scale delay gives no cover. Even ignoring IP, a lone opted-in user reporting rare `place_id`s self-identifies. The spec's "if scale ever warrants, client-side randomized response can be layered on later" inverts the risk — the scheme is weakest when N is smallest, which is exactly when it launches. (Note: randomized response "from v1.5" doesn't itself solve k=1, which needs volume — the load-bearing fixes are suppression and a relay.)

**Spec change:** Don't claim unlinkability on Worker-side log hygiene alone. State the platform-IP threat explicitly in §9; gate collection behind a minimum aggregate count per place/region (suppress low-count cells); route submissions through Oblivious HTTP / a relay so the collector never sees client IPs.

---

### 7. No privacy policy, App Store label plan, or UK-GDPR/PDPA lawful-basis analysis
**Severity: important · missing · privacy-security** *(converges with findings 4 and 6)*

The app targets the UK (UK-GDPR) and Malaysia (PDPA); IP addresses are personal data, and Cloudflare processes them for every user via tiles (v1) and the stats collector (v1.5). Apple has mandated a privacy-policy URL (Guideline 5.1.1(i)) and an accurate App Privacy label since Dec 2020, even for zero-collection apps — an inaccurate label risks rejection or removal. §10's out-of-scope list does **not** descope App Store compliance, and the spec already does forward privacy planning (it captures v2 sharing-privacy requirements now), so a ship-time privacy checklist sits at the document's own altitude. The lawful-basis/PDPA sub-claim is the weakest (v1 collects no personal data), but the missing policy/label plan and the overstated "unable to track" claim are real, in-scope-for-ship, and non-trivial.

**Spec change:** Add a ship-blocking checklist: publish a privacy policy covering Cloudflare IP processing (tiles + stats) and the opt-in stats payload; complete the App Privacy label honestly (opt-in stats as Usage/Coarse Location, "not linked to you"); note UK-GDPR lawful basis and Malaysia PDPA.

---

### 8. The identifier-free feedback endpoint is a Sybil-abusable suppression channel, and its hostile free text isn't in the untrusted-input list
**Severity: important (v1.5 scope; refuters note lowered urgency) · §5.5 / WP-C2 · privacy-security**

Because §9 forbids identifiers, "report a problem" must be an identifier-free public collector whose output the pipeline "consumes as a correction/suppression input." With no accounts and no identifiers by design, per-user rate-limiting is impossible, so a single actor can script thousands of "not there / inappropriate" reports to bury a rival's site or vandalise a town's map — and the spec specifies no gate (threshold, IP/time diversity, human review) between feedback and suppression. Separately, the free-text field and "inappropriate" flag are attacker-authored input landing in R2 and the pipeline, yet §5.5's untrusted-data rules are written for *source databases* and never name user-submitted feedback — the one input authored by arbitrary internet actors with intent — as untrusted, moderation-bearing, and (if it ever reaches a prompt) injection-bearing. (The prompt-injection sub-claim is partly covered by the universal "all external data untrusted" rule and is somewhat speculative; the Sybil-suppression and content-moderation gaps are the load-bearing parts.)

**Spec change:** Make feedback strictly advisory — it never auto-suppresses. Require N independent, IP/time-diverse reports plus human review before suppression or the "inappropriate" flag takes effect. Cap and scrub free text, add it explicitly to §5.5's untrusted-input list, and add a moderation path for "inappropriate."

---

### 9. The LLM cache key `(model, prompt_version, input_hash)` omits the task dimension → cross-task collisions
**Severity: important · §5.2 · pipeline**

Four distinct LLM uses — curiosity score, blurb, category long-tail, reconciliation adjudication — share one key schema. Curiosity, blurb, and category all consume essentially the same input (name + summary + tags), so they produce the same `input_hash`. If `prompt_version` is a per-task counter (the natural reading), then `(model, prompt_version=1, input_hash=H)` is claimed by whichever task writes first, and a later task reads back the wrong output. §5.5's mandated schema-validation catches the *cross-type* case (a blurb string where a curiosity float is expected) but **not** a same-shape collision: blurb and category-long-tail both emit strings, so a category label can silently ship in the blurb field and pass validation (Principle 11 violation). Because tiles and tiers derive from these outputs, this is silent content corruption. Separately, bumping one task's `prompt_version` shifts every place's score → tier with no recorded link between a shipped tier and the config that produced it, undermining Principle 13's empirical loop.

**Spec change:** Add an explicit task component to the key: `(task_id, model, prompt_version, input_hash)`, and schema-validate each cached output against its task's expected shape on read. Record the `prompt_version` set that produced a given tiering in the manifest so eval labels stay tied to the config that generated them.

---

### 10. The core fade render needs a keyed "seen/saved?" join the schema doesn't index, and the R-tree rationale doesn't apply to it
**Severity: important (refuters temper the perf alarm) · §5.3 / §5.4 · iOS**

Every discovery/list map render must resolve each viewport place's state (unseen/saved/visited/loved). Viewport `place_id`s arrive from tiles (hundreds at street zoom), and for each the app must query the user DB for membership in `visits` and `list_items`. §5.4 declares both tables with **no index on `place_id`**, so the membership lookup full-scans them. Meanwhile §5.3 justifies choosing GRDB over SwiftData by "R-tree spatial indexing," but the R-tree is useless here: the fade decision is a keyed membership lookup, not spatial, and the only spatial user data (`place_snapshots.lat/lon`) exists only for already-touched places, so it can't cover the discovery viewport. The one plausible v1 R-tree use — the foreground "you're near X" prompt (B8) — is itself unspecified as to whether X is a saved place (DB) or any nearby discovery (tile data, not in the DB). (Refuters note the perf risk is overstated — a few thousand user rows scan in sub-ms, and a `Set<String>` cache sidesteps it — but the missing indexes in the schema of record and the internally inconsistent R-tree rationale are genuine defects.)

**Spec change:** Add explicit indexes on `visits(place_id)` and `list_items(place_id)` (and a PK on `list_items`) to §5.4, and describe the viewport-state query as a batched keyed lookup. Correct the §5.3 rationale (justify GRDB by predictable/testable migrations and raw-SQL control), and state precisely where — if anywhere — the R-tree is used in v1 and over which rows, including what the nearby prompt queries against.

---

### 11. Offline region packs are unbounded whole-file downloads with no size or zoom budget
**Severity: important (refuters: "unbuildable" overstated) · §5.1 / §8 (B7) · iOS**

§5.1 establishes that MapLibre's OfflinePack API doesn't work with PMTiles, so region packs are whole-file `.pmtiles` downloads at country granularity (UK, Malaysia) with no sub-region option — and the spec sets no maximum zoom and no size budget anywhere. A whole-UK basemap at walkable zoom is highly zoom-sensitive (roughly ~10× per added level), so the file could be hundreds of MB or several GB, unvalidated. This is an *architectural* decision made without feasibility validation: a KL-only user is forced to download all of Malaysia; a UK user on cellular starts a multi-GB single-blob download. Because A7 emits the per-region basemaps that B3/B7 consume, offline granularity/size is an A7↔B7 contract that Principle 18 wants fixed before parallel work — and the flat "whole-file per region" commitment pre-empts reconsidering granularity. Additionally, the offline pack's refresh lifecycle against the §5.6 versioning contract is undefined: when manifest version N+1 ships, whether/how a pack downloaded at version N refreshes is unspecified (Principle 11). (Max-zoom/WiFi-only/background-URLSession/storage-check are legitimately B7 design detail; feasibility and refresh are the surviving core.)

**Spec change:** In §5.1/B7, fix a max zoom for the offline basemap and a stated per-region size budget (with **measured** numbers for UK and Malaysia extracts), require WiFi-only + background `URLSession` + a storage-headroom check, and define the offline-pack refresh policy against §5.6. If country-granularity blobs exceed a usable budget, reconsider sub-region tiling before B7 is designed.

---

### 12. WP-A1 bundles five heterogeneous extractors + scaffold + a feasibility spike — too big for one design + one build pass
**Severity: important · §8 · delivery**

A1 = CLI scaffold + region config + source-record model + SQLite store + five extractors spanning four unrelated source technologies (Wikidata SPARQL/dumps, Wikipedia geotagged articles, OSM via pyosmium PBF streaming, Historic England register, Open Plaques), and §4 additionally folds the Malaysia heritage-register feasibility check into A1. Each extractor is a distinct untrusted-input boundary that §5.5 requires be hardened independently, and pyosmium PBF streaming shares nothing with a SPARQL client. A single Codex build pass will run very long or, more likely, ship shallow, under-hardened extractors on the pipeline's riskiest surface — feeding weak inputs into A2 reconciliation. (Refuters flag one overreach: A2's own conservative fuzzy fallback + QID anchoring + regression tests mean shallow extractors don't *automatically* cause false merges — but the sizing/hardening risk stands on its own, and the fix is contract-neutral because the shared source-record model already defines the interface.)

**Spec change:** Split A1 into A1a (scaffold + region config + source-record model + SQLite store — the interface the extractors implement) plus one WP per extractor or per source family (Wikidata+Wikipedia / OSM / registers+plaques). Make the Malaysia register feasibility a separate small spike, not a rider on the foundational WP.

---

### 13. No work package owns first-run/onboarding or App Store packaging — the two presentation risks the spec calls make-or-break
**Severity: important · missing · delivery**

The spec twice elevates presentation to existential: the naming risk "drives App Store packaging," and the subtitle plus first screenshot "must immediately establish this is discovery, not route logging" (§1; Principle 6), with the whole product resting on users grasping the fresh-snow metaphor. Yet §8 contains no WP for App Store assets (subtitle, screenshots, keywords, anti-route-recorder framing) and none for first-run/onboarding, and §5.3's screen list omits onboarding entirely. A cold install also lands before any region pack exists; the guided path to a populated map, and the offline/unsupported-region empty states, are unspecified and unowned, and the metaphor-teaching "Fresh snow" toggle only arrives late in B8. (Refuters trim two sub-prongs: the map does render from remote HTTPS tiles online without a pack, so "blank first launch" is weaker than stated, and the metaphor is deliberately taught in-product rather than via ceremony — but no WP owns App Store packaging, initial region selection, location-permission priming, or the first-run orchestration.)

**Spec change:** Add a WP owning first-run/onboarding plus cold-start/empty-state (region-pick → download → populated map → metaphor intro, with location-permission priming), and a WP owning App Store packaging (subtitle, screenshots, keyword strategy) tied to the naming-risk mitigation. Add onboarding to the §5.3 screen list.

---

### 14. "Saved" and "visited" are declared orthogonal, but the pin taxonomy defines only 4 of the 6 combinations
**Severity: important · §3.2 · coherence**

§3.2 lists exactly four pin states (unseen · saved · visited · visited & loved), then insists saved and visited "coexist freely… orthogonal, not a state machine." Orthogonality means two independent axes — on-a-list {no, yes} × visit-status {none, visited, loved} = six combinations. The rendering for **saved AND visited** and **saved AND loved** is never specified: does the pin fade, or keep its saved affordance, and is there even a defined "saved" marker to carry through a fade? Since §3.2 also says "marking seen never mutates list membership," a saved place that gets visited is the guaranteed end state of the core save→visit→mark-seen loop, not an edge case. §7 compounds it with a third, incompatible flat enumeration ("unseen/saved/visited/loved × fade") — where "saved × fade" is precisely the undefined cell. WP-B2 ("pin rendering for all states") and WP-B8 (fade) each build against an under-defined set and will diverge on the app's core fresh-snow visual language.

**Spec change:** Add an explicit precedence rule to §3.2 defining the pin for every (saved ∈ {0,1}) × (visit ∈ {none, visited, loved}) cell — e.g. visit-status drives fade/heart, saved contributes an independent badge that persists through fading — and update §7's snapshot-test list to enumerate the same matrix.

---

## Minor

### 15. Swift-6-strict-concurrency "from day one" collides specifically with MapLibre's un-Sendable ObjC/UIKit API
**Severity: minor · §5.3 · iOS**

§5.3 adopts Swift 6 strict concurrency as "a toolchain setting… vastly cheaper than retrofitting" — true in general, but MapLibre Native iOS is an ObjC/UIKit XCFramework whose types (`MLNMapView`, `MLNMapViewDelegate`, `MLNShapeSource`, `MLNAnnotation`) predate Swift concurrency and aren't Sendable-annotated. The async tile client (B3) handing decoded features to the map crosses an actor boundary into non-Sendable MLN types under strict checking, producing real day-one friction (delegate callbacks; feeding `MLNShapeSource` from a background decode). The risk is that a B2 agent hitting a wall of Sendable diagnostics disables strict concurrency to make MapLibre compile — silently reversing a stated decision. The architecture already implies the containment (self-wrapped `MLNMapView`, typed value-model decoding); the spec just never says so. (One refuter argued this is a one-line `@preconcurrency import` fix and overstated — but both refuters agreed the cheap containment note is worth adding.)

**Spec change:** Note in §5.3 that the MapLibre wrapper is a `@MainActor`-isolated boundary using `@preconcurrency import`, that all map mutations occur on the main actor, and that the tile client delivers plain Sendable value types (decoded models) to that boundary rather than MLN objects — containing the concurrency cost to the wrapper rather than leaking it across B2/B3/B4.

---

### 16. `visits.note` is a schema field with no capture path, no display path, and a scope conflict
**Severity: minor · §5.4 · coherence**

The `note` column appears only in the two schema renderings (§3.1, §5.4) and in no prose. §3.4 defines mark-seen as "one tap, no ceremony," §3.3 offers only the verdict heart, and WP-B4/B6 neither collect nor render a note. A free-text per-visit note is arguably "a review," which §10 puts explicitly out of scope for v1, and Principle 3 warns added friction "kills the core mechanic." The spec's own convention contradicts the column: §9 defers `list_items.added_by` out of the v1 schema until sharing arrives (added later via migration), so a lone unexplained `note` column is the exception to the document's own forward-compat pattern. An agent building B1 mints a column while B4/B6 agents get no guidance, and could plausibly build an out-of-scope note editor or leave dead schema.

**Spec change:** Either drop `note` from the v1 §5.4 schema (add it via migration when a note-entry feature is actually designed), or add one sentence stating where a note is entered and displayed, reconciled against §10's review exclusion.

---

## Honourable mentions (refuted, but genuinely borderline)

- **English-only recall + absent Malaysia pageviews collapse Malaysia scoring to LLM-only**, in tension with "LLM never the sole gate" (pipeline). Refuted, but worth a sanity check that the Malaysia scoring path has a non-LLM signal.
- **Verdict is promised "editable later" but no screen or work package owns editing/removing it** (coherence). Refuted, but the edit/undo path is thin.
- **The "newer data" versioning fallback assumes a cached older version a fresh install doesn't have** (coherence). Refuted, but the fresh-install-on-stale-app path deserves one confirming sentence.

---

## What the spec gets right

The refuter notes repeatedly credit a genuinely strong foundation. The `place_id` stability contract, tombstoning, versioned atomic R2 publishes, and the schema-validate-everything discipline are the right invariants — the surviving pipeline findings are gaps *within* a sound contract model, not a broken one. The privacy posture is unusually principled: it is precisely *because* Principles 14 and 15 set a real structural-incapability bar that the reviewers could hold the tile-fetch and stats channels to it. The GRDB-over-SwiftData decision itself is correct (predictable migrations over irreplaceable local history), even where its stated rationale needs fixing. And the deliberate choice to teach the fresh-snow metaphor in-product rather than through onboarding ceremony was explicitly upheld under cross-examination. The defects above are almost all *under-specification a build agent would fill in wrongly* — cheap to close now, expensive to discover post-build — rather than flawed architecture.