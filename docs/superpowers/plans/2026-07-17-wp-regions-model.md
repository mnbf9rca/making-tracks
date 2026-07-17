# Region Model — sub-regions, downloads, lifecycle, global basemap

Date: 2026-07-17
Thread: `wp/regions-design` · Design doc (PRs into `develop`, docs rule). Decomposes into build
WPs (pipeline → `develop`; app → `ios`). Ratified by fable (D1–D5 + WP split); hardened after a
3-critic gate (id-safety / privacy / coherence). **Gate outcome flagged inline as `[gate]`.**
**One OPEN decision requires Rob — see §4 (privacy of sub-region downloads is a §9/P15
principles question, not mine to set).**

## Why

Rob is using the app daily; his feedback converges on the **region model**. Verbatim: *"i assume
i can download 'london' or 'south east england' not just 1.5gb of 'uk'"*; *"global basemap should
be included … otherwise when i pan to UK the map disappears below a certain zoom level"*; *"need a
way to manage lifecycle of downloaded regions — delete, update"*. This doc designs sub-region
granularity, the global-basemap fallback, the download/offline story, lifecycle, and the
region-manager UX, then decomposes them into build WPs.

## Grounded facts (recon: pipeline+contracts on `develop`, app on `ios`; all gate-verified)

- **`place_id` is region-INDEPENDENT** (mint = `hash(select_mint_anchor(refs))`, anchor =
  `min(refs)` by source priority; `place_id.py:81-100`). Reconcile runs whole-country against a
  **region-keyed registry** (`registry/{region}.jsonl`); `resolve()` matches an incoming cluster
  against any ref of an existing record **before** minting (`reconcile.py:53-59,253-269`) — so a
  place, once minted, keeps its id even if its anchor ref later disappears. **This
  resolve-vs-remint stability is the load-bearing id-safety fact (see §1).**
- **Publish keys everything on one `region` string** — `config.load(region)`, the query
  `WHERE p.region=? AND status='live'` (`publish_stage.py:145`, which selects `lat`/`lon`),
  `registry/{region}.jsonl` write + `mark_shipped`, and the R2 output prefix — all off one string.
  Place tiles are NOT bbox-filtered at publish. Basemap = `pmtiles extract --maxzoom=14
  --bbox=<region bbox>` — cut is purely bbox-driven, so a smaller bbox is a smaller basemap with
  zero code change.
- **Contracts already anticipate sub-regions, dormant:** region-config schema has
  `pack_granularity:"country"|"subregion"` + `subregions[]{id,bbox}` (`region-config.schema.json:60-73`,
  `SUBREGIONS_MAX=256`); no code consumes them (`config.py` doesn't even surface them).
- **Blank-on-pan root cause (app):** `PaperStyle.paperBasemapStyle` has a single `"basemap"`
  vector source (region pmtiles, bbox, maxzoom 14) + a flat `background` layer; **pan outside the
  bbox → source empty → only `background` paints → the map "disappears."** No global tier. Region
  hardcoded to `"malaysia"` (`MapScreen.swift:101`), camera to KL
  (`MLNMapViewRepresentable.swift`).
- **B7 offline seam:** `TileCache` doc — *"B7 offline packs are intentionally outside this B3
  cache"*; `manifest.tiles[]` lists every tile with `{sha256,bytes}`; `TileCodec.decode` is the
  per-tile verify. **The streamed basemap is NOT verified** by app code (MapLibre fetches it); a
  *downloaded* pmtiles can be sha-checked. **B3's `TileCache` stores tiles at
  `{region}/{publishVersion}/tiles/{z}/{x}/{y}-{sha}.json.gz` and `purgeNonPinned` deletes
  non-pinned pv dirs** — a fact the partial-update design must work around (§4). Storage is Caches
  (OS-evictable, 64 MiB LRU) — unsuitable for a downloaded region.
- **Spec:** §5.1 MapLibre OfflinePack ≠ PMTiles → **whole-file downloads**, point style at local
  path; sub-region = "a pipeline knob, not an app change." §5.6 refresh when the manifest moves.
  §9 packs are a **privacy feature at country scale** ("downloading UK locates you to tens of
  millions … then zero per-viewport fetches"); the stats channel is routed through an OHTTP-style
  relay so the collector never sees IPs. **§9 states its safety at *country* scale and does not
  define a sub-region privacy floor** — see §4. §5.5 all published files are untrusted (bucket may
  be compromised). Manifest is written last, atomically (§5.2).
- **Tunable levers** (`caps.py`): `TILE_ZOOM=10`, `BASEMAP_MAXZOOM=14` (schema `const 14`),
  `PACK_BUDGET_CEILING_BYTES=3 GiB`, `SUBREGIONS_MAX=256`, per-config `size_budget_bytes`.

## 1. Region granularity — publish-time bbox shards (D1)

**Sub-regions are publish-time bbox SHARDS of the whole-country reconcile — NOT separate
extract/reconcile scopes.** Reconcile stays country-wide (one region-keyed registry, one id per
place); publish emits a sub-region shard = the country's `status='live'` places whose `lat`/`lon`
fall in the sub-region bbox + a bbox-cut basemap. The bbox filter operates on the
**already-reconciled `places` table** (`publish_stage.py:136-148`, `lat`/`lon` present), i.e. on
**already-minted `place_id`s** — gate-confirmed id-safe.

> **Supersedes** WP-A7 plan (`…wp-a7-publisher.md:286`), which specified *"Sub-region packs are
> SEPARATE REGIONS … each its own region, bbox, manifest, tile partition, and publish."*
> **Corrected rationale [gate — my first rationale was refuted]:** the risk is NOT a
> boundary place losing its mint anchor to a bbox-clipped extract (that can't happen — a `wd:`
> ref rides on the OSM member's own `wikidata=` tag, and clustering merges only on shared refs;
> `refs.py:23-27`, `cluster.py:77-90`). The real unsafety is **longitudinal registry drift**: a
> separate `uk_london` reconcile runs against an **independent, empty registry** and re-mints from
> scratch, so it diverges from the country id the moment the anchor ref set changes over time —
> whereas the whole-country `resolve()` keeps the id stable once minted. Reconciling once and
> sharding only the *output* eliminates the drift. **A7's own concern — one basemap + one tile
> partition per manifest — stays valid**: the publish-shard still runs publish once per
> sub-region (one basemap each); D1 only relocates the split from *reconcile scope* to *publish
> input*, it does not license multi-cut-in-one-publish.

- **Declaration:** consume the dormant `subregions[]{id,bbox}`; each sub-region publishes as its
  own R2 prefix (`region_id` convention `{country}_{sub}` → `uk_london`, valid per
  `^[a-z][a-z0-9_]*$`). **[gate]** Assert **global uniqueness** of the composed id at implement
  time (the schema stores the leaf `id`; nothing today prevents a future country config colliding
  with a composed sub-id).
- **Publish decoupling [gate — MED, WP-P scope]:** `publish_stage.run` is single-`region`-coupled.
  A shard must **query by the country region, filter by the sub-bbox, emit under the sub id — and
  NOT write the registry (`mark_shipped`/`registry/{sub}.jsonl`) under the sub id.** The country
  registry stays singular (Principle 17); shards ship tiles+basemap+manifest+current.json only,
  read-only against the country reconcile output.
- **Overlap:** allowed (London ⊂ South East); a shared place appears in both shards' tiles with
  the **same `place_id`**. The app **de-dups at RENDER time across active packs** (they are
  different tile files); when two installed packs are at different `publish_version`s their
  snapshots may differ — **prefer the higher `publish_version`** (newer). **[gate]**
- Whole-country publishes (uk, malaysia) remain valid and untouched.

## 2. Global basemap fallback — the urgent fix, durable for offline (D2)

**Root cause:** one region pmtiles (bbox+maxzoom 14), no global tier. **Fix:** add a global
low-zoom `"world"` vector source in `PaperStyle.paperBasemapStyle`, with its own
`earth`/`water`/`boundaries` layers drawn **under** the region `"basemap"` layers, so the world
tier always paints context and the region adds z7–14 detail. **[gate: spell out the duplicate
world-sourced layers — it's not just "a source", it's a second set of base layers beneath the
region ones.]**

**Measurement gate (the global maxzoom is a swept constant — codex3 is building/measuring the
world pmtiles now):**
- **world z0–6 ≤ ~50 MB → BUNDLE** in the app binary.
- **larger → tune to z0–5, or STREAM from R2.**

**[gate — MED-HIGH, load-bearing correction] Bundle and stream are NOT interchangeable for the
offline user.** For a user with a region pack installed and offline, panning outside the pack
bbox **re-blanks unless the world tier is durably present**. Streaming + B3's OS-evictable 64 MiB
cache does not guarantee that. So: **any offline pack MUST carry the world tier** — bundled, or
**downloaded into Documents at pack-download time** (durable). App-Store cellular-size optics push
*away* from bundling; offline integrity pushes *toward* a durable copy — the decision must weigh
both, and "stream" is complete **only** for the online-no-pack user. (Latent contract note: the
manifest's `basemap.maxzoom` is `const 14`, so a z0-6 world tier cannot be manifest-expressed; if
it ever needs manifest-backed checksum verification, that const must widen — flag, not block.)

## 3. Download model — whole-file packs in Documents (D3)

A downloaded region = a pinned `publish_version`'s **{manifest snapshot + all place tiles +
whole-file basemap pmtiles (+ optional thumbs, §6)}**:

- **Bulk tiles:** iterate `manifest.tiles[]`, verify each via `TileCodec.decode` (sha256+bytes).
  **Basemap:** whole-file download, verify against `manifest.basemap.sha256`/`bytes`.
- **Integrity vs authenticity, stated honestly [gate — HIGH, I overclaimed this].** The sha closes
  the **corruption / truncation / partial-download / below-TLS cache-poisoning** gap that the
  streaming path leaves open (MapLibre fetches the basemap unverified). It is **NOT authenticity**:
  §5.5's in-scope threat is a *compromised bucket*, which rewrites the manifest **and** the file so
  the sha matches — against that, checksum-vs-manifest adds nothing over TLS origin auth (the same
  trust the streaming path already has). Meeting §5.5's bucket-compromise threat on the download
  path would require a **signed manifest / pinned key** — noted as a gap, not claimed as solved.
  Also: the downloaded `.pmtiles` is parsed by **MapLibre**, outside our typed decode — an
  **unhardened parser surface** the sha does not protect (a manifest may legitimately point at a
  hostile-but-matching file). The 3 GiB size-cap applies.
- **Storage = Documents**, NOT Caches (survives OS eviction — downloaded is user data), separate
  from B3's 64 MiB LRU. **Set `URLResourceValues.isExcludedFromBackup = true`** on pack files/dirs
  (Documents is iCloud-backed by default; multi-GB re-downloadable data must not bloat backups;
  App Review expects this). **[D3 rider]**
- **Whole-file** (§5.1), **resumable background `URLSession`**, **WiFi-preferred**,
  **storage-headroom check**. Once installed, point the style at the **local pmtiles path**.
- **§5.5:** every downloaded artifact checksum-verified + size-capped like streaming.

## 4. Lifecycle + privacy (D4) — privacy RULED by Rob (2026-07-17)

### Lifecycle (mechanics)
- **List** installed regions (name, on-disk size with/without thumbs, `publish_version`, status).
  **Delete** removes the Documents pack. **Update signal = the `current.json` flip** (the app has
  `VersionGate`/`TileLoadState.updateAvailable`).
- **Partial update [gate — HIGH, the reuse is neither free nor B3-provided].** `publish_version`
  is in the tile PATH, so a new pv = new URLs for every tile; sha-diff the new manifest vs the
  installed pack and **fetch only content-changed tiles**, but the unchanged ones must be **locally
  copied old-pv → new-pv keyed on matching sha** — B3's `TileCache` keys the local path by
  `publishVersion` too and `purgeNonPinned` **deletes** the old pv, so naive reuse gives **zero
  reuse + a full re-download**. Required: **(a)** a **content-addressed local pack store keyed by
  sha** (so pv-in-path stops mattering), **(b)** run the cross-pv copy **before** any purge, **(c)**
  **retain the old pack until the new one is complete** (also what "old pack keeps working"
  requires). The basemap is re-fetched only if its sha changed.

### Privacy — DE-ASSERTED floor + escalation [gate — SEV-1/SEV-2, the headline]
**My draft asserted a "≥1M-metro k-anonymity floor" and cited §9 as licensing it. That was an
overclaim and I am withdrawing it.** The gate is right:
- **§9 defines its packs-are-a-privacy-feature safety at *country* scale** ("UK = tens of
  millions, then zero fetches"); it contains **no k-anonymity floor** and uses **unlinkability**,
  not k-anonymity. Introducing a floor is **new privacy policy**, which per PRINCIPLES.md must be
  an **argued amendment to §9/P15 — Rob's call, not a plan assertion.**
- **The metric was wrong:** the anonymity set of the signal is *"who downloaded `uk_london`"*, not
  *London residents* — a Kuala-Lumpur user downloading `uk_london` is **revealed**, not hidden. A
  "national/ceremonial unit" escape hatch admits sub-1M, sharply-locating units.
- **The decisive regression:** the *purpose* of sub-regions is to download **multiple, finer**
  packs, so the CDN edge sees a **sequence** of metro-granular GETs from one IP over time —
  precisely the linkable coarse-location trace **P15 forbids**, and the exact harm §9 spends its
  whole budget relaying the *lower*-stakes stats channel to avoid. The **update-poll on
  `current.json` + partial-update bursts** make it a **recurring** beacon, breaking §9's "zero
  fetches after download." So **sub-region download is materially less private than a country
  pack** — a real cost, not the "privacy feature" §9 describes at country scale.

**What is true and stays:** downloads are ordinary CDN GETs with **no developer-accessible
per-request record and no account/identifier/telemetry**; but — mirroring §9's own precision —
**Cloudflare's edge still sees IP + which region-file + time** (that visibility is the leak above,
not nothing). The region manager introduces no identifier; downloads must carry **no custom
identifying headers/query params [gate]**; the background-`URLSession` identifier is app-local.
WiFi-preferred rides a **more** stable/geolocated IP — it compounds the leak (a cost of the
bandwidth choice, noted).

**RULED BY ROB (2026-07-17, via the privacy.md rulings — resolves this escalation):** sub-region
downloads **proceed, WITH cover-traffic.** Smaller downloads are shipped *together with* a mechanism
that hides which one you actually want — e.g. the app fetches a few other bundles at the same time,
so the CDN can't tell the real target from the decoys. This directly mitigates the sequenced-metro-GET
movement trace (the SEV-1/SEV-2 leak) rather than accepting it. **The mechanism's feasibility is
owned by the design (WP-B7), not this policy:** decoy *full-bundle* fetches are bandwidth-prohibitive
at 1.5 GB scale — but see the bundle-size addendum below (small bundles make cover-traffic cheap).
The privacy floor question is thereby **closed**: the answer is not a k-anonymity floor but a
cover-traffic requirement. B10 onboarding may frame smaller downloads honestly (they come with the
hiding mechanism); it still must not call a bare metro download "a privacy feature" absent the decoys.
Recurring channel (SEV-2): keep the mitigation — **check for updates only on user action / app
launch, never on a schedule.**

### Addendum — Rob's product rulings (2026-07-17)

- **BUNDLE-FIRST is the product direction.** Downloading a bundle (map + places for an area) is how
  Making Tracks is meant to work; **streaming per-viewport tiles is the interim/fallback until
  bundles ship**, described honestly as such. This flips the model's default: WP-G/B7 build toward
  download-first UX, not streaming-first. (Reflected in the privacy policy, `privacy.md`.)
- **Bundle size is a PRIVACY PARAMETER, not just a cost knob.** Rob's point: bundles can be *small*.
  Small bundles change the cover-traffic economics — a handful of small decoy bundles is cheap, where
  decoy country-packs are not. **But small is NOT monotonically "more private"** — a small on-demand
  fetch is also *sharper* (finer location) and *more frequent*. **§7 quantifies this and resolves it:**
  small bundles are the *index/composition* unit; the online fetch policy prefers *chunky prefetch*;
  the privacy win is chunky prefetch + spread-consistent decoys, not "make bundles tiny." Bundle
  sizing is a WP-B7/WP-P tunable, earned-not-baked.
- **NEW INFRA REQUIREMENT (WP-P / infra): aggregate, user-unlinked bundle-download counts.** The
  policy commits that "we count how many times each bundle is downloaded, to see which areas need
  work — but can't tell who downloaded which." That requires an aggregate count per bundle with **no
  per-user linkage** (Cloudflare aggregate analytics, never our own per-request IP logs). This is a
  new pipeline/infra deliverable that must exist and must be provably user-unlinked.

## 5. Region index + region-manager UX (D5)

- **A new published region-index static file** (e.g. `regions.json`), **schema'd + versioned with
  the `min_reader_version` pattern** (readers detect newer-than-understood, degrade). Per region:
  `{id, display_name, parent, bbox, basemap_bytes, tile_count, bytes_without_thumbs,
  bytes_with_thumbs}`. **[gate — do NOT embed the live `publish_version`]** — it duplicates
  `current.json` and can skew; the app reads the region's `current.json` for the live pv at
  download time. The index is emitted **written-last / atomically**, after each region's
  `current.json` flip + full upload (the §5.2 manifest rule, extended to the index), so it never
  advertises a not-yet-live region.
- **The index is UNTRUSTED input (§5.5/P10) [gate — HIGH]:** size-cap the index download; cap the
  region count (a `SUBREGIONS_MAX`-analogous bound); **validate every `id` against
  `^[a-z][a-z0-9_]*$` before it composes into a fetch prefix** (path-traversal/key-injection
  guard); bound the numeric fields and bbox ranges; render `display_name` as **plain text, length-
  capped** (§5.5 no-markup).
- **Region-manager screen:** Installed (name, size, status, delete, update-when-available) +
  Available (browse the index, size with/without images, download with progress). "Include images"
  is a download-size choice (§6).
- **Accessibility (standing criterion) [gate — make it measurable]:** Dynamic Type (semantic
  fonts — the app already does this); VoiceOver labels + `accessibilityValue` on download progress
  **throttled** (announce at intervals, not per byte); contrast **≥ WCAG AA 4.5:1**; and the map
  surface's own accessibility is in scope for WP-RM.

## 6. Thumbnails — optional, feature-flagged pack component (fable addendum)

Per-place thumbnails (~20–30 KB, **rehosted on our R2** per #129; **sourcing/licensing = #129,
this doc owns pack-size/format only**).

- **Version model — pinned to resolve the refuse-vs-degrade conflict [gate — HIGH].** "Thumbless
  packs stay valid / old app degrades" requires an **optional `thumbnails_present` feature flag
  that does NOT raise `min_reader_version`** (a *degrade*, not the *refuse*-gate `min_reader_version`
  triggers). The flag + per-image `{sha, bytes, license, attribution}` live in a **new versioned
  pack-descriptor** file (its own schema, `schema_version`, R2 place — to be pinned in WP-P;
  they cannot ride the manifest, which is `additionalProperties:false` + `schema_version const 1`).
- **BUT attribution is legally load-bearing [gate].** A thumb carries `{license, attribution}` that
  **must render with the image** (the same rule that makes the manifest force `min_reader_version
  ≥ 2` when attribution is present). So "degrade by dropping the thumb" is fine **only if dropping
  the image also drops nothing legally required elsewhere** — the app must never show a thumb
  without its attribution, and an app that can't render image attribution must not show thumbs
  (drop the image, keep the place). This is the card-level analogue of B3-Q2 / B4's attribution
  gate.
- **Size:** the index + region manager report `bytes_with_thumbs` and `bytes_without_thumbs`; the
  download offers the choice.
- **Privacy:** rehosted-on-R2 thumbs are **single-origin** (no third-party Wikimedia beacon —
  aligns with the B4 image-redirect fix). **[gate — SEV-6]** But **streaming thumbs online without
  the thumb pack is a *per-place* signal — sharper than §9's coarse tile channel** — so the
  online-thumb path inherits §4's open privacy question; bundled-in-pack thumbs are zero-fetch and
  fine. The B4 image allowlist could later collapse to our one origin (a #129/B4 follow-up).

## 7. Unified fetch model — one index, one bundle unit, mode picks granularity (Rob design input, 2026-07-17)

**Rob's input (verbatim):** *"pulls data in realtime? i suppose that's possible too — probably good —
you can choose to make it offline. but instead of 'per viewpoint' it should be very small bundles
perhaps — everything you need? or it has an index."*

**The unification.** Collapse "streaming" and "offline pack" into ONE mechanism: an **index** lists
**bundles**; a **fetch policy** driven by mode picks which bundles to fetch and how far ahead; a
**decoy wrapper** wraps every fetch uniformly. There is no separate "streaming" concept — **online
mode** is just the fetch policy that pulls the small covering bundle(s) for the current view on
demand; **offline mode** is the policy that pulls aggregate (city/country) bundles ahead of time.
Today's structure is already most of the way there — this is an evolution of the fetch layer, not a
rebuild.

**Today's artifacts are special cases (grounded against the tree):**

| today | unified model |
|---|---|
| `regions.json` region-index (§5) | THE index — generalizes from regions to bundles at all granularities |
| z10 place tile (wire key `{region}/{pv}/tiles/10/{x}/{y}.json.gz`) | the finest **places-bundle** (immutable per-`publish_version` URL — **not** hash-keyed on the wire; see the content-addressing note below) |
| region pmtiles (bbox, maxzoom 14) | a coarse **basemap-bundle** |
| world z0–6 pmtiles (§2) | the coarsest **basemap-bundle** |
| B7 whole-file pack {manifest+tiles+basemap} | the offline fetch policy = "fetch every bundle covering area X, ahead of time" |
| B3 per-viewport `TileCache` fetch | the online fetch policy = "fetch the covering bundle(s) for the current view, on demand" |

Bundles are **typed and independently versioned** — a places-bundle bumps per `publish_version`; a
basemap-bundle rarely bumps. **Do NOT merge types into one monolithic per-area blob** — that forces a
basemap re-download on every place update and throws away §3's sha-diff partial-update win.
"Everything you need for area X" = the *covering set across types* the index resolves, fetched
independently, immutable per version, cacheable. *(Grounding correction, post-gate: today's wire
artifacts are **publish_version-addressed, not content-addressed** — `r2.py` keys tiles at
`{region}/{pv}/tiles/10/{x}/{y}.json.gz` and the basemap at `{region}/{pv}/{region}.pmtiles`, with no
hash on the wire; the `-{sha}` suffix is only B3's LOCAL `TileCache` filename, under a pv-scoped path
that `purgeNonPinned` deletes. True content-addressing is the §4 to-be-built sha-keyed local pack
store, not a property of today's fetch layer.)*

**Two real wrinkles — flagged, owned by WP-B7/WP-G, NOT hand-waved:**
1. **Basemap online fetch is pmtiles range-requests, not whole-bundle GETs.** MapLibre streams a
   region pmtiles by HTTP range into its internal z/x/y index (grounded fact: unverified,
   MapLibre-parsed). That is *already* a per-viewport fetch at fine granularity, and it does not
   decompose into discrete bundle GETs the decoy wrapper can treat like place-bundles. Options for
   WP-B7/WP-G: (a) pre-cut area basemap-bundles (district pmtiles) listed in the index, so the online
   basemap path is whole-bundle GETs too; (b) keep range-streaming and decoy at the range level.
   **Unresolved — a design question, not solved here.** The clean uniform story holds today for PLACE
   data and for WHOLE-FILE prefetch; the online basemap is the awkward edge.
2. **Bundle granularity is the whole privacy story — quantified next.**

### The privacy quantification — "how small is too small"

**The trap: bundle ≠ privacy.** An on-demand fetch of a bundle covering area *A*, made while the user
looks inside *A*, over their real IP, at time *t*, reveals to Cloudflare *"user ∈ A at t."* The
sequence over a session is a **movement trace at resolution A**. If *A* ≈ viewport this is **exactly
today's per-viewport streaming exposure** — renaming tile→bundle buys nothing. The win comes not from
the bundle unit but from two independent levers, both named by fable:

**Lever 1 — prefetch chunkiness (cuts the NUMBER of exposure events).** Fetch bundles much *larger*
than the viewport. Moving *within* a fetched bundle produces **zero new fetches → zero new
exposure.** Exposure events over a session ≈ (area explored) / A, so coarser A → fewer events →
weaker trace. At A = country this is precisely §9's existing win ("download the country, then zero
per-viewport fetches"): the CDN sees one bulk-download event ("has UK") plus a launch-frequency
update-poll — **not** "no trace at all" (the update-poll on `current.json` is the §4 recurring channel,
mitigated to launch-only, present at every granularity including country; the exposure ≈ area/A model
covers only movement-driven fetches, not this orthogonal poll). **Offline packs are just the coarsest
point on this continuum** — which is what unifies them with streaming. Chunkiness is *free* (fewer
requests = cheaper) and is the primary lever.

**Lever 2 — decoys (cut the PRECISION of each event).** Fetch the real bundle alongside (k−1) decoys
so the CDN sees k GETs and can't tell which is real → location ambiguous over the union of k areas.
Cost = k× bandwidth (cheap only when bundles are small — see below). **The governing rule: a decoy is
cover only if it is indistinguishable from the real fetch on EVERY axis the CDN observes.** That is far
more than "fetch a few others" — WP-B7 must close all of these, or the decoys are theatre *(post-gate:
the earlier draft named only spread + intersection and framed them as the complete set — itself the
one-horn overclaim that broke the withdrawn k-anonymity floor; the real obligation is indistinguishability
across all observable axes)*:
   - **Spatial spread.** Adjacent decoys still localize you to a region; decoys must be drawn across
     the anonymity area being claimed (national spread for national ambiguity).
   - **Timing and order.** The k GETs must be simultaneous / order-randomized and decoupled from the
     pan event. Otherwise the real bundle is simply the one fetched *when the user moved* — fired first
     for fast render, decoys trailing as padding — and on-demand real fetches stay re-identifiable by
     their correlation with movement at time *t*, spatial spread notwithstanding.
   - **Size, count, and composition.** A chunky real covering-set (many bundles / large bytes) hidden
     among token single-bundle decoys is separable by request-count and response byte-length alone.
     Decoys must match the real fetch's request count, byte-length class, and composition — chunky real
     prefetch needs equally chunky decoy sets, not tokens.
   - **Must reach the CDN.** A decoy is cover only on a fetch that actually travels to the edge (IP +
     object + time logged). A bundle already in the device's local store generates NO request, so a
     "recycled" local decoy is invisible cover — the cover channel must bypass/revalidate to the edge,
     or be a steady background hum. (This is why cover traffic and cache efficiency pull against each
     other; see the economics note below.)
   - **Intersection vs cross-session linkage — an OPEN tradeoff, not a solved obligation.** If each
     fetch draws *fresh random* decoys, a longitudinal attacker intersects candidate sets across fetches
     and recovers the real trace (the real bundle is in every set; decoys vary). Making the cohort
     **sticky** defeats that — **but a stable cohort recurring from one IP is itself a cross-session
     quasi-identifier, and a cohort spread *around* the real area leaks that area.** So stickiness is not
     a clean fix: the cohort must be derived **independently of the user's real location** (a
     population-shared cohort, not a home-centred spread), and residual cross-session linkability is one
     of the parameters Rob ratifies (below), not something this mechanism closes on its own.

**Both levers are required below city scale:** chunkiness defends the event-*count*/timing channel,
decoys defend each event's *precision*; neither alone suffices — and decoys defend precision only if
every axis above holds.

**Refining "bundle size as a privacy parameter" (corrects the §4 addendum's shorthand).** Small
bundles have **two opposing effects**: they make decoys *affordable* (bandwidth) but each fetch
*sharper* (finer location) and *more frequent* (more events). So small is **not** monotonically "more
private." Resolution:
   - **Small bundles are the INDEX / COMPOSITION unit** — fine-grained availability so any area can be
     assembled — **not necessarily the online FETCH size.**
   - **The online fetch policy prefers CHUNKY prefetch** (pull a coarse covering set), using decoys
     only for the residual fine-grained on-demand fetches.
   - The privacy win = **chunky prefetch + decoys indistinguishable on all Lever-2 axes**, *not* "make
     bundles tiny."

**The floor is Rob's to set (see [[principles-changes-are-robs]]).** This section quantifies the
*shape* of the tradeoff and names the obligations; it does **not** set the numbers. The **minimum
online fetch granularity**, the **decoy count k**, and the **decoy spread/consistency policy** are
P15/§9 parameters — surfaced for Rob's ratification in the PRINCIPLES amendment (they define what
"unlinkable at scale S" concretely means), not baked here. Recommended *shape* for that ratification:
above a coarse-area threshold the chunk is its own anonymity set (no decoys); below it, decoys
mandatory and indistinguishable on all Lever-2 axes (spread, timing/order, size/count, edge-reaching,
location-independent cohort); **never** an on-demand fetch at viewport granularity without decoys.

**CDN / cost economics.** More granular = more requests (each a CDN GET + cache-key + a timing/IP
event); tiny bundles = request explosion, per-request overhead, and *more* exposure events; decoys
multiply request count by k. Chunky prefetch REDUCES requests — it wins on cost AND privacy at once.
Cache keys **should become** content-addressed (bundle_id + sha, immutable, cache-forever) — a §4
to-be-built TARGET, **not** today's wire model (today's R2 objects are pv-keyed, so identical bytes get
a fresh URL each pv). **Caveat that ties to Lever 2's "must reach the CDN":** a decoy served from the
local cache-forever store sends no request and so provides **zero** cover — cover traffic and cache
efficiency pull in opposite directions, and WP-B7 owns reconciling them (decoys revalidate/bypass to
the edge, or run as a background hum). Do not conflate a warm local cache with working cover.

**Verdict: fold in — it doesn't break anything real.** The index+bundle model is a clean
generalization; today's tiles/manifest/basemap/pack are special cases; the partial-update and
separate-cadence wins survive because bundles stay typed. The one genuinely open piece is the
online-basemap range-streaming edge (wrinkle 1), handed to WP-B7/WP-G. The privacy analysis is honest
about the trap (bundle ≠ privacy) and pins the two obligations decoys must meet.

## Constraints & compliance

Frozen contracts (`place_id` never region-dependent — §1; manifest/index/pack-descriptor
versioning, newer-than-understood degradation); determinism; §5.5 untrusted-data on **all**
downloaded artifacts incl. the new index (§5); §9/P15 privacy — **§4 design RULED (cover-traffic, not
a k-anonymity floor); the argued §9/P15 PRINCIPLES edit is a separate Rob-gated PR**; the fetch model
unified under index+bundles (§7); constants earned-not-baked (global maxzoom
[measured], any size threshold — documented tunables). *(Section-citation note: "§N" without
"spec" refers to THIS doc; spec sections are named "spec §N" to avoid the spec-§6-is-error-
handling collision.)*

## Build-WP decomposition (ratified split + order, gate-tightened)

| WP | side | scope | depends on | urgency |
|---|---|---|---|---|
| **WP-G** global basemap | **app (`ios`)** | add the world low-zoom source + its under-layers in `PaperStyle`; **repoint the hardcoded `region`/camera to a single configurable default (NOT a picker — selection is WP-RM)**; fix blank-on-pan. **Precondition: a live UK publish exists on R2** (else blocked on an A7 UK run) | codex3's world-pmtiles measurement (in flight); a live UK publish | **URGENT — ship first** |
| **WP-P** sub-region publishing + index | **pipeline (`develop`)** | consume `subregions[]` → publish-time bbox shard (decoupled: query country, filter bbox, emit sub id, **do not write the country registry**); id uniqueness assert; emit the versioned+atomic region-index; contracts: region-index schema + pack-descriptor schema (§6) + the A7 supersede | pipeline (built) | after WP-G |
| **WP-B7** offline download + lifecycle + fetch model | **app (`ios`)** | Documents store (`isExcludedFromBackup`), whole-file pmtiles + bulk sha-verified tiles, resumable background `URLSession`, **content-addressed local store + cross-pv sha-reuse before purge + retain-old-until-complete** (§4), the durable world tier for offline (§2); **the unified index+bundle fetch layer (§7): mode-driven fetch policy (chunky online prefetch / aggregate offline), the decoy wrapper meeting ALL Lever-2 obligations (spatial spread, timing/order, size/count/composition parity, must-reach-CDN, location-independent cohort), and a call on wrinkle-1 (online-basemap range-streaming)** | **B3** (built) + **WP-P** | after WP-P |
| **WP-RM** region-manager UX | **app (`ios`)** | manager screen (installed + available, progress, delete/update), region selection, accessibility (measurable) | **WP-B7** | after WP-B7 (own WP for reviewability) |

**B10 Onboarding** (later) hooks region-pick → download offer — **must reflect Rob's §4 privacy
ruling, not a "metro = privacy feature" claim.** Thumbnails (#129) supplies the images WP-P/B7
budget for.

## Gate & acceptance (this design doc)

- **Adversarial gate (done): 3 critics** (id-safety / privacy / coherence). Raised ~20 findings;
  the core decisions (D1 publish-shard [id-safe, confirmed], D2 global-basemap fix, D3 downloads,
  the WP split) **survived**; folded: the corrected id-safety rationale, publish decoupling,
  offline-durable world tier, partial-update content-addressing, the index untrusted+atomic
  posture, the thumbnail feature-flag/attribution resolution, the integrity-not-authenticity
  framing, WP-G scope/precondition, dedup precedence, measurable accessibility. **The escalated
  sub-region-download privacy question is now RULED by Rob (§4): sub-regions ship WITH cover-traffic;
  the answer is a cover-traffic requirement, not a k-anonymity floor.**
- **Second gate (§7 unified fetch model, 2026-07-17): 3 critics (privacy-threat / coherence-arch /
  principles-fidelity) → verify.** Raised 9, **2 survived adversarial verification**, both folded, plus
  3 verify-withdrawn findings folded anyway because they exposed real defects in the §7 prose:
  (1, survived) the decoy obligations were framed as a closed set of two — the one-horn overclaim that
  broke the k-anonymity floor — so Lever 2 is **reframed around the governing rule** (a decoy is cover
  only if indistinguishable on every observable axis) with five obligations: spatial spread, timing/order,
  size/count/composition, must-reach-CDN, and the intersection-vs-cross-session-linkage tradeoff;
  (2, survived) "already content-addressed / today's model" was a **false tree-grounding** — corrected
  (today's wire is pv-addressed, `r2.py:106/115`; content-addressing is the §4 to-be-built target);
  (3–5, folded) the warm-cache-recycling line self-contradicted the "must-reach-CDN" cover requirement,
  the "no trace at all" for country packs ignored the §4 update-poll beacon, and sticky cohorts are
  themselves a cross-session fingerprint. The unifying model itself **survived** — it's a clean
  generalization, today's artifacts are special cases, typed bundles preserve the partial-update/cadence
  wins. Open piece handed to WP-B7/WP-G: wrinkle-1 (online-basemap range-streaming).
- PR → `develop` (docs rule), `sourcery-review` only, report on `wp/regions-design`. No self-merge;
  fable's independent review; `main` is Rob's. **The privacy §4 is RULED (2026-07-17): cover-traffic
  + bundle-first + user-unlinked download-counts; see the §4 addendum. The argued §9/PRINCIPLES edit is
  a separate Rob-gated PR (`docs-privacy-principles-amend`).**
