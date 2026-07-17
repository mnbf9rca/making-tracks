# WP-#129 — Place photos: rehost + licensing + card attribution + pack integration

**Status:** design (opus), adversarial-gate pending → PR to `develop`, `sourcery-review`, report `docs/images-design`.
Builds on the region-model §6 thumbnail rider (merged #131) and WP-P (#148). App changes target `ios`.

## Why

Places want a photo. The direction is ruled (fable/Rob): the **pipeline fetches Commons images at
publish time** (Wikidata P18 / lead image), resizes to card thumbnails (~20–30 KB), stores per-image
`{sha, bytes, license, attribution}`, and **rehosts on OUR R2** — single-origin, no third-party
fetch from the app (the glyph/basemap precedent). This doc owns: image sourcing + license filtering,
attribution rendering (legal), the thumbnail pipeline, the contract changes, pack integration, and
the app-wiring note — then a build-WP decomposition.

## Grounded facts (recon: pipeline+contracts on `develop` @ d3931d9; app on `origin/ios` @ 5ea9a95; all cited)

- **P18 is captured then thrown away.** `extractors/wikidata.py:114-116` stores the P18 image into
  `props["image"]` as a **resolved `https://` URL** (via `_https`), NOT the Commons `File:` filename.
  `score/signals.py:45-47` collapses it to a boolean (`1.0 if image else 0.0`); the URL string is
  **dropped at the score→publish boundary** (`score_stage.py:258-271` serialize only numeric signals).
  `publish/publish_stage.py:185-230` emits only `{place_id,name,lat,lon,category,tier,score,source_refs}`
  — **no `image_url`, `blurb`, `wikipedia_title`, or `alt_names` are published today.** So the whole
  image path is greenfield in publish; the P18 value survives only in `source_records.props_json`.
- **Attribution is per-SOURCE, never per-place (#138 @ 32bb31c).** `config/a1d_sources.json` carries
  `{license (SPDX), attribution}` per source; `publish/attribution.py` aggregates
  `[{source,license,text}]` into the manifest; `manifest.py:71` sets `min_reader_version = 2 if attr`.
  `credits.py` (#147) renders `attribution.md` + `ios/App/Sources/OSSCredits.json`. **No per-image
  or per-place license/attribution model exists.**
- **`place.schema.json` is `additionalProperties:false`** (`:7`) and HAS `image_url`
  (`["string","null"]`, https-only, ≤2048) — but **no `image_license`/`image_attribution`**, and no
  `schema_version` (place is embedded in the tile). Adding fields to it is a **breaking** change.
- **`manifest.schema.json`**: `additionalProperties:false`, `schema_version` const 1,
  `min_reader_version ≥ 2` iff `attribution` non-empty. **`tile.schema.json`**: `schema_version`
  const 1, `z` const 10, `places` → `place/1`, maxItems 4000. Contracts frozen at v1 (`versions.json`).
- **`region-index.schema.json`** already REQUIRES `bytes_without_thumbs` + `bytes_with_thumbs`
  (each `0..3 GiB`) — **but `publish_stage.py:399` sets `bytes_with_thumbs = bytes_without_thumbs`
  (no thumb bytes counted); tests assert equality.** The pack-descriptor schema and
  `thumbnails_present` flag from §6 are **design-only, not built.**
- **Publisher** (`r2.py`): public keys `{region}/{pv}/tiles/10/{x}/{y}.json.gz`,
  `{region}/{pv}/{region}.pmtiles`, `manifest.json`, `{region}/current.json`, `regions.json` (root).
  `_PUBLIC_KINDS = {tile,basemap,manifest,current,region_index}` enforced. **No publish-time fetching**
  — the publish stage reads DB + cuts basemap + gzips. `fetch.get_to_file(url,dest,*,expected_hosts,
  max_bytes,timeout,deadline)` (`fetch.py:120-162`) is the hardened primitive (https+host-allowlist +
  redirect-allowlist + byte-cap + deadline + atomic + rejects `Content-Encoding`). `llm/cache.py` is
  the content-hash-keyed, validate-on-read, atomic, private-R2-published cache template.
- **Tiers**: `t1_min=0.85, t2_min=0.65, t3_min=0.35` (`scoring.json`); `score`+`tier` are on the
  publish place dict; `caps.select_tile_places` already ranks `(tier, -score, place_id)`. No publish
  floor today (every categorized winner ships). ~600k is a docs-only production target ($40–60/sweep);
  real runs are small (Malaysia 5,036).
- **App (`origin/ios`)**: `PlaceContentGuards.allowedImageHosts = {"upload.wikimedia.org",
  "commons.wikimedia.org"}` (`MakingTracksTiles.swift:579`), used at **4 call sites**
  (`ImageLoader.swift:20,:51`, `PlaceCardModel.swift:104`, `MakingTracksTiles.swift:675`) + hardcoded
  in tests. `ImageLoader` is hardened (2 MB cap, streaming abort, allowlisted redirects). The card
  (`MapScreen.swift`) renders the image (`maxHeight 180`) with **NO per-image attribution** — manifest
  attribution shows only in a separate global `CreditsView`; `AttributionModel` is dead. Decoder
  already enforces a `missingAttributionSources` invariant (required sources must be in the manifest).
  **No pack code** (WP-B7 is a stub comment); **no image cache** (`ImageLoader()` per card load).

## 1. Architecture — images are a versioned SIDECAR component, not tile fields (D1)

**fable's question — does `image_url` fit, or need a sidecar? → It needs a sidecar.** Putting
per-image `{license, attribution}` on the place JSON breaks `place.schema` (`additionalProperties:false`)
and forces a `min_reader_version` **refuse-gate**: a reader that doesn't understand the new fields
refuses the whole region — so a region loses *all* its places on an old app merely because it gained
photos. That contradicts P11 ("degrade gracefully") and my own §6 rider (thumbnails are an optional
component that **degrades, does not refuse**).

**Decision: a per-tile IMAGE-INDEX sidecar + content-addressed thumbnail blobs.**

- **Image-index sidecar**, published parallel to each place tile that has imaged places:
  `{region}/{pv}/images/10/{x}/{y}.json` — its **own versioned schema** (`schema_version`,
  `min_reader_version` pattern), `additionalProperties:false`. Each entry, keyed by `place_id`:
  `{place_id, thumb_sha256, bytes, license, attribution, source_url}`. This is the single source of
  truth for a place's photo + its legally-required credit.
- **Thumbnail blobs are content-addressed and global:** `thumbs/{sha[0:2]}/{sha}.webp` at the public
  bucket root — **immutable, cache-forever, deduped across places, publish-versions, and regions.**
  The online URL is `https://tiles.making-tracks.app/thumbs/{sha[0:2]}/{sha}.webp` (**same host as
  tiles** — fable's ruling: single-origin stays literal, one allowlist entry); the app derives it from
  `thumb_sha256`. (This sidesteps the pv-churn the region §7 gate flagged for tiles: image bytes are
  truly content-addressed from day one.)
- **Base tile/manifest are UNCHANGED.** `place.image_url` stays null/unused (the pipeline still never
  sets it; the image-index supersedes it — left in the schema, not churned). `manifest.min_reader_version`
  does **not** bump for images. Old/incapable readers simply ignore the image-index → **image-less
  cards, region still loads.** An image-capable reader loads the parallel image-index and joins by
  `place_id`.
- **Why not tile fields (the rejected alternative):** simpler data model and reuses the existing
  `image_url` plumbing, but the refuse-gate above, and it splits attribution across the online
  (tile) and offline (pack) paths. Pre-release there are no old readers *yet*, but the contract
  discipline is permanent and the sidecar is §6-consistent, so we design for degrade now.

## 2. License filtering — which Commons licenses we may redistribute (D2)

We **resize** (a derivative work) and redistribute in a **non-commercial** app (Rob's ruling, 2026-07-17:
*"the app is not commercial"* — free, no ads, no payments; CC's NC test is about use directed at
commercial advantage). That set the acceptable-license boundary:

- **ACCEPT** (credit rendered for all — see §3): Public Domain / PD-old / PD-art, **CC0**,
  **CC-BY** (2.0/2.5/3.0/4.0), **CC-BY-SA** (all versions), and — under the non-commercial ruling —
  **CC-BY-NC** and **CC-BY-NC-SA**.
- **REJECT**: **CC-BY-ND / CC-BY-NC-ND / any -ND** (no-derivatives — resizing is a derivative →
  forbidden regardless of the NC ruling), **GFDL-only** (impractical; accept only if *also*
  dual-licensed CC-BY-SA), **non-free / "fair use"**, and **anything without a machine-readable
  license, or ambiguous** (§5.5 posture: reject-on-doubt → no image).
- **[NC eligibility is CONTINGENT — Rob's rider, recorded not relitigated].** NC images are eligible
  *only while the app stays non-commercial.* If monetisation ever arrives, every **NC-derived thumb
  must be purgeable MECHANICALLY** — see the purge operation in §5 and the risk note (§Risk). The
  `license_code` field (§3/§5) is queryable precisely so the NC subset can be selected and purged.
  ND stays rejected on the *derivative* ground, independent of commerciality.
- **[gate — resolve the derivative theory, one theory throughout]** We treat a resize + WebP re-encode
  as an **adaptation** (a derivative). This is the *same* premise that lets us reject -ND, so we must
  carry it consistently: for **CC-BY-SA** sources our thumbnail is **relicensed under the same BY-SA
  version**, and §3's credit must *declare that* (same-license + license URI), not merely name the
  source's license. (CC's FAQ arguably treats a pure format/size shift as a verbatim non-adaptation,
  under which SA would not attach and the -ND reject would be merely conservative — but we do not rely
  on that; one theory, applied to both the reject set and the SA obligation.)
- **License classification — STRICT, on the machine-readable code (feasibility gate).** Classify on
  `extmetadata.License` (the short code, e.g. `cc-by-sa-4.0`, `cc0`, `pd`); **reject when that field
  is absent or unrecognised** (Commons metadata is frequently missing/messy). `LicenseShortName` is
  **display only**, never the classifier. Match the code against an explicit accept-allowlist
  (config-driven, earned-not-baked). Cache reject decisions. State the expected drop rate from
  missing-metadata + rejected-format files in the WP-IMG-P acceptance (it is non-trivial).

**[RESOLVED — Rob ruled 2026-07-17: "the app is not commercial" → NC accepted, contingent (above).]**
The commerciality call was Rob's, not mine ([[principles-changes-are-robs]]); recorded, not
relitigated. The contingency + mechanical purge path (below) is the standing condition on it.

## 3. Attribution rendering — legally load-bearing (D3)

- **Attribution is a STRUCTURED model, not a freeform string [gate — legal, the core fix].** One
  string cannot be validated for legal completeness. The image-index entry carries structured fields:
  `{creator, license_code, license_name, license_url, source_url, modified}`. The app assembles the
  displayed credit from these; the pipeline never ships a pre-baked sentence.
  - **`creator`** — from `extmetadata.Artist`, **HTML-stripped to plain text** (see below), required.
  - **`modified` — MANDATORY and always true.** CC-BY 4.0 §3(a)(1)(B) (and 2.0/2.5/3.0) require
    *indicating that you modified the material*; we **always** resize + re-encode, so every entry
    carries a modification notice (e.g. rendered "…— modified (resized)"). Omitting it ships every
    BY/BY-SA thumbnail in breach — a golden fixture asserts it is present on every entry.
  - **`license_url`** — the canonical license deed URL (e.g. `https://creativecommons.org/licenses/by-sa/4.0/`);
    **required for BY/BY-SA** (the license notice must link/where practicable), host-pinned to
    `creativecommons.org` (or PD marker). For **BY-SA**, this + `license_code` is our declaration that
    the thumbnail is offered under the same BY-SA version (the §2 share-alike obligation).
  - **`source_url`** — the Commons **File:** page, **host-pinned** `^https://commons\.wikimedia\.org/wiki/File:…`
    and built by URL-encoding a *validated* `File:` title (never string-concatenating untrusted text).
- **HTML-strip Commons text — SAFE_TEXT is NOT enough [gate — untrusted-data].** `extmetadata.Artist`/
  `Credit` are HTML fragments (`<a>`, `<bdi>`, `<span>`, often multi-line) and SAFE_TEXT
  (`text.py`) strips only control/bidi/zero-width codepoints — **`< > & " '` and full tag markup pass
  through**. So the pipeline must **HTML-strip to plain text** (extract text content, or reject-on-any-tag
  per §5.5) *before* applying SAFE_TEXT + length cap. Golden fixtures: `Artist = <a href="javascript:…">x</a>`
  → `x`; `<bdi>Name</bdi>` → `Name`. Defence in depth: the app renders the credit with plain-text
  SwiftUI `Text` **only** — never markdown / `AttributedString` / HTML.
- **The invariant is CREATOR-present, not string-non-empty [gate — legal].** Extending the existing
  `missingAttributionSources` decode rule to images: an entry is valid only if `license_code` is
  accepted **and** (`creator` is non-empty **or** the license is PD/CC0) **and** the `modified` notice
  is present. A BY/BY-SA image whose `Artist` is missing/unparseable is **dropped** (keep the place) —
  never rendered with a license-only, creator-less credit. Teeth: neuter the creator-required check and
  a *BY-without-creator* fixture must flip from rejected to accepted. Structural because the sha (image)
  and the credit fields live in the **same** record — you cannot obtain the image without its credit.
- **Card UI (new):** the assembled credit (creator · license · "modified" · link) rendered with the
  image on the place card (the §2 gap), plain-text only.

## 4. Thumbnail pipeline — format, size, dedup, determinism, cost (D4)

- **Format: WebP**, quality-tuned to **~20–30 KB** at **~320 px longest edge** (card shows ≤180 pt
  → ~360–540 px @2–3×; 320–400 px is right). iOS-native decode; deterministic given a **pinned
  libwebp** + fixed params. (AVIF is a smaller-still future option; WebP is the deterministic,
  well-tooled choice now — flagged tunable.)
- **Determinism + cache:** a content-addressed blob cache keyed by
  `(commons_filename, commons_sha1, target_spec, encoder_version)` (the `LlmCache` template). Same
  input → same output bytes → same `thumb_sha256`. Cache persists across publishes (published to
  private R2) → re-publish re-fetches nothing; **reject decisions are cached too** (avoid re-hitting
  known-bad files).
- **Dedup:** content-addressed by our `thumb_sha256` → a Commons file shared by many places is fetched,
  resized, and stored **once**; many `place_id`s reference one sha.
- **Fetch discipline (reuse `fetch.get_to_file` + Commons API via `get_json`):** https + host-allowlist
  (`upload.wikimedia.org`, `commons.wikimedia.org`) + byte-cap + deadline + atomic; **low concurrency,
  descriptive User-Agent, respect `maxlag`** (Commons etiquette). Publish-time (fable's ruling) but
  cached, so publish stays deterministic given the cache.
- **Bound the DECODE, not just the download [gate — untrusted-parser, SEV-3].** `fetch.get_to_file`
  caps *downloaded* bytes only; resizing must **decode the untrusted original** (Pillow/greenfield — no
  decoder dep exists yet), and a few-hundred-KB file can be a decompression bomb (a small PNG/WebP →
  gigapixels in RAM). WP-IMG-P must: a strict **input-format allowlist** (JPEG/PNG/WebP); an early
  **dimension gate read from the header BEFORE full decode**; `Image.MAX_IMAGE_PIXELS` set low with the
  Pillow **DecompressionBombWarning promoted to an error**; a decode wall-clock/memory cap; and
  **decode in a subprocess** so a bomb kills a worker, not the run. Cache the reject (§ above).
- **Format coverage — many P18 values are NOT raster [gate — feasibility].** Commons lead images are
  frequently **SVG** (also TIFF/GIF). SVG is a *scripting/XXE* surface and is **rejected** at the
  format allowlist (a future rasterize-via-sandbox step could add it). This plus missing-metadata
  rejects means a **material fraction of places get no thumb** — state the measured drop rate in
  WP-IMG-P acceptance rather than assuming near-100% coverage.
- **Cost / tiering — a NEW eligibility floor gate:** fetching for 600k places is the cost driver, so
  **thumbnails ship for the best places first** — an eligibility floor `tier ≤ 2` (score ≥ 0.65,
  fable's ruling: stands as the default), config-driven (earned-not-baked), matching
  `select_tile_places`' `(tier, -score)` ranking. The floor can lower over successive sweeps as cost
  allows; the cache makes each lowering incremental.
- **Measure-then-commit (fable's ruling — WP-G precedent):** WP-IMG-P must run a **bounded first sweep
  and emit a measured cost report** (images fetched / rejected-by-reason / bytes / API time / est. full
  extrapolation) **before** committing to the full `tier ≤ 2` run. No blind full-sweep; measure, report,
  then commit.
- **P18 → filename recovery (build note):** the pipeline captures a *resolved* P18 URL, not the
  `File:` title the `imageinfo` API needs. Recover the filename from the upload-URL path (last
  segment) or capture the raw P18 value at extraction. Flag: verify against a real P18 value before
  building.

## 5. Contract changes (D5)

- **New `image-index` schema** (`contracts/schemas/image-index.schema.json`, `$id .../image-index/1`),
  `additionalProperties:false`, `schema_version` const 1, `min_reader_version` pattern. Each entry:
  `{place_id, thumb_sha256 (hex64), bytes (0..cap), creator (≤256), license_code (≤64, enum-checked
  against the accept-allowlist), license_name (≤64, display), license_url (https, host-pinned
  creativecommons.org or PD marker, ≤256), source_url (host-pinned `^https://commons\.wikimedia\.org/wiki/File:`,
  ≤2048), modified (bool, must be true)}`. Array cap mirrors the tile `places` cap. New caps in
  `caps.py`. Bump `versions.json` (`image_index:1`). Golden fixtures (valid + invalid: **off-host
  source_url**, source_url with injected `?`/`#`/`..`, off-host license_url, **BY-without-creator**,
  `modified:false`, HTML-in-creator, oversize, control chars, bad sha).
- **Publisher — corrected against `r2.py` [gate — the described path was wrong].** The upload path is
  **NOT** the generic "atomic written-last" and it **hard-filters kinds**: `publish_prepared_to_r2`
  (`r2.py:270-283`) keeps only `{tile,basemap,manifest}` as content, then uploads
  `[content, current, region_index, private]`; `_assert_bucket_invariants` / `_PUBLIC_KINDS` gate the
  rest. So WP-IMG-P must **extend that kind allowlist** to add `image` (per-region content, uploaded in
  the **content group, before the `current` flip**) and `thumb` (root blobs). **Ordering guarantee
  (not atomicity):** `thumb` blobs upload **FIRST** (before any image-index that references a sha), the
  `image` index next in the content group, `current` flips last — so a live pointer never references a
  missing blob or a missing index. Root `thumb` blobs are content-addressed + immutable
  (**write-if-absent**, never overwrite a differing sha); a crash can leave an **orphan blob** (a sha no
  live index references) — harmless (~20–30 KB), reclaimed by GC (below), never a dangling *reference*.
- **Global-blob lifecycle / GC [gate — content at a root path breaks per-region delete].** Thumb blobs
  live at a **global root** (`thumbs/…`) to dedup across regions/pv, so they are **outside** a region's
  `{region}/…` prefix and are **not** removed by a region delete/supersede. A blob is live iff **some
  live region's image-index references its sha**; a periodic **reference-count GC** (sweep live indexes,
  delete unreferenced blobs) reclaims orphans. Until GC runs, orphans are cheap and harmless. WP-IMG-P /
  WP-P own the GC pass; deleting a region deletes its `images/…` index tiles (its `{region}` prefix),
  never blobs directly.
- **NC mechanical-purge operation [Rob's contingency rider — required, testable].** Because
  `license_code` is a queryable field on every image-index entry, a **documented, tested purge op**
  exists: (1) select every entry whose `license_code` is an NC variant; (2) rewrite each affected
  `images/…` index tile to drop those entries (+ recompute `bytes_with_thumbs`); (3) reference-count GC
  removes the now-orphaned `thumbs/{sha}` blobs. This composes the existing index-rewrite + GC — no new
  primitive. It is the standing condition on NC eligibility (§2): if the app ever becomes commercial,
  run the purge. WP-IMG-P ships it with a test (seed NC + non-NC, purge, assert NC blobs+entries gone,
  non-NC intact).
- **`region-index`**: make `bytes_with_thumbs` **real** (`basemap + tiles + image-index + thumb
  blobs`); fix `publish_stage.py:399` + the equality tests.
- **`place.schema` `image_url`**: unchanged, left unused (superseded by the image-index; not churned).
  Note for WP-IMG-B: the app currently decodes `DecodedPlace.imageURL` from `place.image_url` — that
  path must be **retired/ignored** in favour of the image-index join, so a stale null `image_url` never
  competes with the index.
- **`manifest`**: unchanged. Image presence is signalled by the image-index existing + `bytes_with_thumbs
  > bytes_without_thumbs`, **not** by a manifest field — so `min_reader_version` does not bump.

## 6. Pack integration (D6) — folds into WP-B7

- A pack for a region includes its **image-index tiles + the thumbnail blobs** for its places. The
  image-index **doubles as the pack-descriptor**: `thumb_sha256` gives verify-on-download integrity,
  `bytes` gives size accounting. `thumbnails_present` is a **pack-level flag** (in the pack's descriptor,
  NOT the manifest) — a degrade flag, exactly per §6: a pack-thumb-incapable reader drops the blobs,
  keeps the places; it never raises `min_reader_version`.
- **"Include images" download choice:** the region-manager offers with/without thumbs using the
  now-real `bytes_with_thumbs` / `bytes_without_thumbs`.
- **Privacy (§6 + region §7):** bundled-in-pack thumbs are **zero-fetch** (fine). **Online** thumbs are
  per-place fetches of `thumbs/{sha}.webp` — a **sharper per-place signal than the coarse tile
  channel** — so the online-thumb path **inherits the region §7 cover-traffic obligations** (the thumb
  GET is another bundle fetch the decoy wrapper must cover; content-addressed cache-forever blobs help,
  but a cache miss is a real edge fetch). Single-origin rehosting removes the third-party Wikimedia
  beacon regardless.

## 7. App wiring (D7) — `ios`, folds into the image build WP

- **Allowlist collapses to one origin — `tiles.making-tracks.app`** (fable's ruling: same host as
  tiles; single-origin literal, **one** allowlist entry). `PlaceContentGuards.allowedImageHosts` →
  `{"tiles.making-tracks.app"}`. Update the **4 call sites** + the hardcoded Wikimedia test hosts.
  Image URLs now come from the image-index (our origin), not `place.image_url`.
- **Card gets images from the image-index join, not `place.image_url`:** load the parallel image-index
  tile → join by `place_id` → `{thumb_sha256 → our URL, creator, license_name, license_url, modified}` →
  `ImageLoader.fetch` (allowlist = our origin) → render image **+ assembled credit** (creator · license ·
  "modified" · link), rendered with **plain-text `Text` only** (never markdown/`AttributedString`/HTML —
  the defence-in-depth from §3). Enforce the **creator-present** never-uncredited invariant at decode
  (extend `missingAttributionSources` to images; drop the image, keep the place, on a violation). The
  old `DecodedPlace.imageURL`/`place.image_url` path is **retired** so a stale null never competes.
- **Image blob cache:** add a small content-addressed image cache mirroring `TileCache` (thumbs are
  ~20–30 KB; bundled offline, cached online). Repurpose/remove the dead `AttributionModel`.

## Constraints & compliance

Frozen contracts + versioning (new `image-index` schema is `min_reader_version`-gated and degrades,
never silently misread — P11); determinism (pinned encoder, content-addressed, cached — P12); §5.5
untrusted-data on **every** Commons field (license, artist, url) + the published image-index; §9/P15
privacy (single-origin; online thumbs inherit the §7 cover-traffic obligation); constants
earned-not-baked (thumbnail size/quality, eligibility floor — documented tunables); legal — never a
thumbnail without its credit (structural). *("§N" = spec section; "§N (this doc)" for local refs.)*

## Build-WP decomposition (proposed split + order)

| WP | side | scope | depends on |
|---|---|---|---|
| **WP-IMG-P** pipeline images | **pipeline (`develop`)** | P18 filename recovery; publish-time Commons `imageinfo` fetch + **strict license filter** (incl. NC-accept); bomb-bounded **decode** + **WebP resize** (pinned, deterministic); content-addressed **blob cache** (+ cached rejects); emit `images/…` index tiles + `thumbs/…` blobs; make `bytes_with_thumbs` real; **eligibility floor** (tier ≤ 2, config) + **measure-then-commit cost report**; **NC mechanical-purge op + test** (§5); global-blob **GC**. Contracts: `image-index` schema (structured attribution) + caps + `versions.json` + fixtures | contracts (built), publisher (built) |
| **WP-IMG-B** app images online | **app (`ios`)** | image-index tile decode + `place_id` join; **per-image attribution UI** (assembled, plain-text, creator-present gate); **allowlist → `tiles.making-tracks.app` (1 entry)** (4 sites + tests); retire `place.image_url` path; content-addressed **image cache**; retire `AttributionModel` | WP-IMG-P + B4 card (built) |
| **WP-IMG-PACK** offline thumbs | **app (`ios`), folds into WP-B7** | pack includes image-index + blobs; `thumbnails_present` degrade flag; verify-on-download via `thumb_sha256`; "include images" choice; online-thumb cover-traffic per §7 | WP-IMG-B + WP-B7 |

Order: **WP-IMG-P → WP-IMG-B → WP-IMG-PACK** (pipeline produces the artifacts; app consumes online;
offline last with WP-B7).

## Rulings (2026-07-17 — resolved, was "open flags")

1. **License set / commerciality — RULED (Rob):** *"the app is not commercial"* → **NC accepted**
   (BY-NC, BY-NC-SA), **contingent** on the app staying non-commercial, with a required **mechanical
   NC-purge** op (§5) + §Risk note. ND stays rejected (derivative ground). §2 updated.
2. **Image origin host — RULED (fable):** **`tiles.making-tracks.app`** — same host as tiles,
   single-origin literal, one allowlist entry. §1/§7 updated.
3. **Eligibility floor — RULED (fable):** `tier ≤ 2` **stands as default**; WP-IMG-P runs a
   **measure-then-commit** bounded first sweep + cost report before the full run (§4).

## Risk

- **NC-eligibility is commerciality-contingent (Rob's rider).** NC-licensed thumbnails are lawful only
  while the app is non-commercial. **Trigger:** any move to ads / payments / commercial advantage.
  **Mitigation (must exist before NC images ship):** the `license_code` field makes the NC subset
  queryable, and the **mechanical purge op (§5)** — index-rewrite to drop NC entries + GC the orphaned
  blobs, with a test — removes them without a re-fetch. Recorded so the contingency can never be
  forgotten: shipping NC images **requires** the purge op to be built and tested first.

## Gate & acceptance (this design doc)

- **Adversarial gate (done): 4 critics (legal / contract-versioning / privacy-untrusted / feasibility)
  → verify. Raised 19, 8 survived, all folded.** Legal was the sharpest lens:
  - **Attribution is now a STRUCTURED model** `{creator, license_code, license_name, license_url,
    source_url, modified}` — a freeform string can't be validated for legal completeness (§3).
  - **`modified` notice is mandatory** on every entry (CC-BY 4.0 §3(a)(1)(B); we always resize) — else
    every BY/BY-SA thumbnail ships in breach.
  - **CC-BY-SA share-alike is discharged**, not just asserted: the thumbnail is relicensed under the
    same BY-SA version with a license URL (§2 one-theory ruling: resize = adaptation, applied to both
    the -ND reject and the SA obligation).
  - **The never-uncredited invariant is creator-present**, not string-non-empty — a BY image with a
    missing `Artist` is dropped, not shown with a creator-less credit (teeth test specified).
  - **SAFE_TEXT does NOT strip HTML** — Commons `Artist` is HTML, so the pipeline HTML-strips before
    SAFE_TEXT, and the app renders plain-text only (§3).
  - **The decode is bomb-bounded** (format allowlist, pre-decode dimension gate, low
    `MAX_IMAGE_PIXELS`, subprocess) — the download byte-cap does not bound decompression (§4); SVG and
    missing-metadata files are rejected, so coverage is materially < 100% (state the drop rate).
  - **The publisher description was WRONG** and is corrected against `r2.py:270-283`
    (`publish_prepared_to_r2` hard-filters kinds; not atomic) — plus a **global-blob GC** for the
    content-addressed root blobs that a per-region delete cannot reach (§5).
  - **`source_url`/`license_url` are host-pinned** (Commons / creativecommons.org) with
    injection-fixture coverage (§5).
  Withdrawn on verification (11): incl. a WebP-nondeterminism objection (pinned encoder holds) and
  redundant restatements.
- **The unifying architecture (sidecar + content-addressed blobs) SURVIVED** — it avoids the
  refuse-gate, degrades cleanly, and the schema/versioning is sound; the survivors were refinements to
  the legal model, the untrusted-data handling, and the (mis-described) publisher path, not the design.
- PR → `develop`, `sourcery-review` only, report `docs/images-design`. No self-merge; fable reviews;
  `main` is Rob's.
