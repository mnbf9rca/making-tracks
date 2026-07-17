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

## 4. Lifecycle + privacy (D4) — with an OPEN decision for Rob

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

**OPEN DECISION — ESCALATED TO ROB (via fable):** Rob explicitly wants sub-region downloads
("London, not 1.5GB UK"). That is a genuine **product-vs-principle tension**: the size/convenience
win carries a privacy cost the current principles do not sanction. Options for Rob to rule on:
1. **Accept the tradeoff, informed** — ship sub-region downloads, amend §9/P15 to state the
   finer-signal cost honestly, frame it to the user in onboarding as a convenience-vs-privacy
   choice (NOT as "a privacy feature"), and mitigate the *recurring* channel (below).
2. **Keep packs coarse** — offer only nation-scale sub-regions (England/Scotland/Wales — still
   large anonymity sets, closer to §9's blob) and NOT metros; smaller than 1.5 GB UK, weaker on
   Rob's exact London ask.
3. **Mitigate the channel** — route pack + update fetches through the same relay §9 mandates for
   stats (heavy for large files), or minimize the recurring signal: **check for updates only on
   user action / app launch, never on a schedule**, and coarsen/batch. (This mitigates SEV-2
   regardless of 1/2.)
This doc does **not** pick; §9/P15 is amended by Rob. Until then the privacy section is
**pending**, and B10 onboarding must NOT inherit a "metro pack = privacy feature" claim.

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

## Constraints & compliance

Frozen contracts (`place_id` never region-dependent — §1; manifest/index/pack-descriptor
versioning, newer-than-understood degradation); determinism; §5.5 untrusted-data on **all**
downloaded artifacts incl. the new index (§5); §9/P15 privacy — **with the sub-region-download
tradeoff an OPEN §9/P15 amendment for Rob (§4)**; constants earned-not-baked (global maxzoom
[measured], any size threshold — documented tunables). *(Section-citation note: "§N" without
"spec" refers to THIS doc; spec sections are named "spec §N" to avoid the spec-§6-is-error-
handling collision.)*

## Build-WP decomposition (ratified split + order, gate-tightened)

| WP | side | scope | depends on | urgency |
|---|---|---|---|---|
| **WP-G** global basemap | **app (`ios`)** | add the world low-zoom source + its under-layers in `PaperStyle`; **repoint the hardcoded `region`/camera to a single configurable default (NOT a picker — selection is WP-RM)**; fix blank-on-pan. **Precondition: a live UK publish exists on R2** (else blocked on an A7 UK run) | codex3's world-pmtiles measurement (in flight); a live UK publish | **URGENT — ship first** |
| **WP-P** sub-region publishing + index | **pipeline (`develop`)** | consume `subregions[]` → publish-time bbox shard (decoupled: query country, filter bbox, emit sub id, **do not write the country registry**); id uniqueness assert; emit the versioned+atomic region-index; contracts: region-index schema + pack-descriptor schema (§6) + the A7 supersede | pipeline (built) | after WP-G |
| **WP-B7** offline download + lifecycle | **app (`ios`)** | Documents store (`isExcludedFromBackup`), whole-file pmtiles + bulk sha-verified tiles, resumable background `URLSession`, **content-addressed local store + cross-pv sha-reuse before purge + retain-old-until-complete** (§4), the durable world tier for offline (§2) | **B3** (built) + **WP-P** | after WP-P |
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
  framing, WP-G scope/precondition, dedup precedence, measurable accessibility. **Escalated (not
  fixable in a plan): the sub-region-download privacy floor is a §9/P15 amendment for Rob (§4).**
- PR → `develop` (docs rule), `sourcery-review` only, report on `wp/regions-design`. No self-merge;
  fable's independent review; `main` is Rob's. **The privacy §4 is marked PENDING Rob's ruling.**
