# WP-B3 — Tile Client (`MakingTracksTiles`)

Date: 2026-07-16
Thread: `wp/b3` · Issue: §8 B3 row · Depends on: **A0** (contracts, built), **B1** (`MakingTracksData`, built)
Design ratified by fable on `wp/b3` (Q1–Q6). Designed against the **live** artifacts on
`tiles.making-tracks.app` (fetched + verified 2026-07-16) and the merged A0/A7 contract.
Hardened after a 3-critic gate (feasibility built the package on real Swift 6.3.3; security +
spec-fidelity lenses) — the security/§5.6 fixes below are the gate's output.

## Goal

The online read path for the app: turn the published tile artifacts into validated,
in-memory place values the map (B2) and place-store (B1) consume. **Manifest/current fetch →
dual version gate → viewport→tile coverage with padded prefetch → strict §5.5 decode + sha256
verify + bomb-safe gunzip → produce `MapPlace` (B2) and `PlaceRef` (B1), with a sha-verified
local cache invalidated on repoint.** Everything the trust boundary touches is host-testable;
only the MapLibre viewport wiring is `[XCODE/SIM]`.

**Security framing (P10 / §5.5):** published tiles are **untrusted even though we published
them** — the bucket/edge could be compromised or the pipeline fooled. **sha256 is an integrity
check against a *trusted* manifest (catches truncation / cache poisoning of one object), NOT
authenticity against origin compromise** — a compromised origin serves a matching
manifest+tile. The real defense against hostile *content* is the §5.5 decode caps + host
pinning + plain-text rendering; the real defense against a decompression bomb is the
incrementally-bounded inflate, not the sha. The plan keeps that hierarchy explicit.

**First end-to-end milestone (spec §8):** real UK tiles from A7, fetched by B3, rendered by B1–B4.

## Controlling context (verified against `origin/develop` + live domain)

**Published contract (A0/A7, built — B3 is a client of it):**
- Flow: `GET {region}/current.json` → `publish_version` → `GET {region}/{pv}/manifest.json`
  → per-viewport `GET {region}/{pv}/tiles/10/{x}/{y}.json.gz`. Domain `tiles.making-tracks.app`
  (`r2_layout.json`); keys `publish/r2.py:98-128`.
- **`current.json`** (`current/1`): `{schema_version const 1, publish_version ^[0-9]{8}T[0-9]{6}Z$}`.
- **`manifest.json`** (`manifest/1`): `schema_version`, `min_reader_version` (≥ 2 forced by the
  schema **`allOf`** when `attribution` is non-empty — LIVE on UK), `region`, `publish_version`,
  `tile_z const 10`, `tiles[]{x,y,sha256,bytes 1-1048576}`, `counts{total,by_tier[4]}`,
  `basemap{filename ^…\.pmtiles$, maxzoom const 14, sha256, bytes, bbox[4]}`,
  `provenance[]{task_id,model,prompt_version}`. **Optional:** `generated_at`, `attribution[]
  {source,license,text}`.
- **tile** (`tile/1`): `{schema_version const 1, z const 10, x, y, places[≤4000]}`, gzipped
  (`mtime=0`, OS byte 255), sha256 over the **gzipped** bytes.
- **place** (`place/1`) — full cap set B3 enforces at decode (see Task 4): `place_id
  ^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$`, `name`≤200, `lat[-90,90]`, `lon[-180,180]`,
  `category`≤64, `tier 1-4`, `score 0-1`, `source_refs[1-64] uniqueItems, each ≤128, pattern`;
  optional `alt_names[≤8] each ≤200`, `blurb|null[≤600]`, `image_url|null (^https://…, ≤2048 —
  **scheme-only, NO host in the pattern**)`, `wikipedia_title|null[≤300]`. **The text fields
  (`name/category/blurb/alt_names/wikipedia_title`) carry a pattern that REJECTS control chars,
  bidi overrides (U+202A–202E/2066–2069), and zero-width (U+200B–200D/2060/FEFF) — a *reject*
  rule, not a strip.**
- **Version policy** (`versions.py:30`): `check_version(reader_max, data_version, min_supported)
  → OK|TOO_NEW|TOO_OLD` keys **`schema_version` only**. **`min_reader_version` and the schema
  `allOf` are B3's to enforce in Swift** — A0 does neither.
- **Tile addressing** (`publish/partition.py:18` `lonlat_to_z10`, web-mercator, n=1024, clamped) —
  B3 reproduces it (feasibility-verified byte-identical in Swift).
- **Image host:** `image_url` originates from Wikidata P18 (`extractors/wikidata.py:114`) → a
  Wikimedia host (`upload.wikimedia.org` / `commons.wikimedia.org`; fixture shows
  `upload.wikimedia.org`). The place schema pins only the scheme — **the host allowlist is B3's
  to add** (Task 4).
- **Live-verified:** UK `current.json`→`20260716T155409Z`; manifest `min_reader_version 2`, 1163
  tiles, 3 attributions (ODbL/OGL/PDDL); fetched tiles' sha256 matched exactly; the 4000-place
  tile decodes in ~14 ms. All captured as test fixtures.

**B1 `MakingTracksData` (built — B3 produces its input):** `PlaceRef` (throwing,
validated-by-construction) guards lat/lon/tier/field-length/rawJSON-size but **does NOT check
`place_id` pattern, `score`, `source_refs`, or the text codepoint rules** → **B3's decoder
must.** Persist path takes a `PlaceRef` (snapshot is a side effect); **B3 never reads the user
DB** (Q6). `MapPlace{id,lat,lon,tier}` — provisional, B3 **produces**, extend-never-break.

**B2 `MakingTracksMapStyle` (planned, NOT built):** B3 defines the contract B2 consumes; B2's
plan pins "B3 owns primary §5.5 validation; B2 consumes already-validated `Sendable` values,
never re-decodes."

## Ratified design decisions (fable, `wp/b3`)

1. **Pin-for-session (Q1).** `current.json` read at launch / explicit refresh only; one
   `publish_version` per session; a repoint is a clean swap at the next refresh — never shift
   places under a mid-pan user. "Tolerate mid-session change" = don't crash/corrupt when the
   pointer moves, not live-switch.
2. **Reader version = 2; refuse-not-degrade on attribution (Q2), refined per §5.6.** B3 declares
   `readerVersion = 2`. **Two-branch (§5.6), not one:** newer data (`min_reader_version >
   readerVersion`) **with a readable cached publish** → keep serving the cached older pv +
   `.updateAvailable` soft nudge; **fresh install / no readable cache** → `.updateRequired`
   explicit state. **Never an empty map, either way.** *(This refines Q2's single
   `updateRequired` to honor §5.6's two branches — flagged to fable.)* B3 **exposes
   `manifest.attribution` as required-to-display** with the legal obligation documented at the
   API surface; the app shell + B4 MUST render it (fable puts "MUST render `manifest.attribution`"
   verbatim into the B4 brief). B3's half = the machine-checkable gates + the strings.
3. **`places(inViewport:zoom:) async → [MapPlace]` is THE B2↔B3 contract (Q3) — NON-throwing.**
   B3 owns coverage/fetch/cache/decode/§5.5-validation; B2 calls on camera-idle and never
   re-decodes. **`places()` never throws to the map** (§5.5/§6 "never block/crash"): it returns
   what it can — cache on offline, valid places skipping malformed — and surfaces problems via
   `loadState`. Only `refreshPin()` (not the map path) throws. *Pinned verbatim in Task 5.*
4. **Layering (Q6).** B3 = live tiles + an `isPresentInCurrentTiles(placeID)` answer. Snapshot
   fallback for a tapped-but-absent place is **B4/app** (B1's `place_snapshots`). B3 never reads
   the user DB.
5. **Padded prefetch (Q4).** Visible tiles + a **1-tile ring**; bounded concurrency;
   cancel-on-viewport-change. `PrefetchRing.radius = 1` — a **named constant, comment-flagged
   tunable** (someone will want 2 on fast pans; per Rob's rule an untested constant is flagged,
   not baked).
6. **Cache (Q5).** sha256-verified disk cache, LRU under `TileCache.maxBytes = 64*1024*1024` (a
   **named, comment-flagged tunable**); purge non-pinned `publish_version`s on repoint. Offline
   region packs are **B7** — B3 leaves the seam, builds no packs.

## Package architecture

New pure SwiftPM package **`MakingTracksTiles`** (iOS 18 / macOS 14, Swift 6 language mode, no
UI deps — `swift test`, no simulator; feasibility-confirmed to build under strict concurrency).
Depends on `MakingTracksData` (for `PlaceRef`/`MapPlace`) and the **system `zlib`** (see
`TileCodec`). Units, each independently testable:

- **`TileFetching` (protocol) + `HTTPTileFetcher`.** The only I/O boundary; protocol so host
  tests inject a `URLProtocol` stub / captured fixtures. Live impl: `URLSession`, **https-only,
  host-pinned to `tiles.making-tracks.app`, and a `URLSessionTaskDelegate` that BLOCKS (or
  re-pins) any 3xx cross-host redirect** — the origin-URL host check alone is bypassable, and
  `current.json`/`manifest.json` have no sha backstop, so redirect pinning is mandatory for the
  root-of-trust fetches (mirrors the pipeline's SSRF-allowlist-on-redirect guard).
- **`ManifestClient`.** `current.json` → `publish_version` → `manifest.json`; strict typed decode
  (`attribution`/`generated_at` optional — must not be `required`); **the version + legal gates
  Codable can't express:** (a) `check_version`-equivalent on `schema_version`; (b) the
  `min_reader_version` reader gate (§5.6 two-branch); (c) **re-evaluate the schema `allOf`
  explicitly** — non-empty `attribution` with `min_reader_version < 2` is schema-INVALID and
  must be refused, not accepted because `1 > 2` is false; (d) **attribution-source cross-check**
  — if decoded tiles carry `source_refs` for an attribution-requiring source (`osm`,
  `historic_england`, `open_plaques` per `a1d_sources.json`) but the manifest omits that
  source's credit, **refuse** (a stripped-attribution manifest is schema-valid yet a license
  breach). A schema-invalid/inconsistent manifest is a **loud** failure: refuse the pin, keep
  serving the last verified cached publish, surface an error — never silent, never empty (§5.6
  "never silently misread"). Exposes `PinnedPublish{region, publishVersion, manifest}`,
  `attribution`, and the **`basemapURL`** (`{region}/{pv}/{basemap.filename}`) for B2 to hand
  MapLibre's `pmtiles://` source (closes the end-to-end milestone; B3 does not fetch the
  basemap).
- **`TileCodec`.** sha256 verify of the raw `.gz` against the manifest `{sha256, bytes}` **before**
  inflating, then **bomb-safe streaming gunzip via `zlib`**: `inflateInit2(16 + MAX_WBITS)` —
  which handles the gzip wrapper natively and is the **exact `wbits` of the Python `safe_gunzip`**
  (Apple's `Compression` framework decodes raw DEFLATE only and would force hand-parsing the gzip
  header/trailer on the trust boundary — **do not use it**). The 8 MiB output ceiling is enforced
  **incrementally** (per-chunk, streaming — never one-shot-then-check, or the bomb is already in
  memory), the 1 MiB compressed cap refuses pre-inflate, and end-of-stream is required
  (`Z_STREAM_END` reached **and** `avail_in == 0` after — else truncated/trailing-garbage
  rejected). zlib is a system lib (no extra linker config for the package target; note it as a
  dependency).
- **`PlaceDecoder`.** Strict §5.5 typed decode enforcing **every** `place/1` cap (Task 4),
  **skip malformed places/tiles, never throw**; cross-checks the tile's internal `z/x/y` against
  the requested coordinate (a manifest-consistent-but-mislabeled tile). Produces `MapPlace`, and
  `PlaceRef` on demand (re-validating what `PlaceRef`'s init doesn't).
- **`TileCoverage`.** `lonlat_to_z10` reproduction + viewport-bbox→covering-tiles + the padded
  ring; deterministic duplicate-`(x,y)` handling. Host-tested against `partition.py`.
- **`TileCache`.** sha256-keyed disk cache, LRU under the tunable cap, repoint purge.
- **`TileClient` (façade / actor).** Owns the pinned session + wires the above. The
  **`[XCODE/SIM]` seam is ONLY B2's map calling `places(inViewport:zoom:)`** — `TileClient`
  itself is fully host-testable.

## Tasks

1. **Package skeleton + `TileFetching` + fetch hardening + version gate.** `MakingTracksTiles`;
   `TileFetching` protocol + `HTTPTileFetcher` (https-only, host-pinned, **redirect-blocking
   delegate**); the Swift `check_version` equivalent + the `min_reader_version` §5.6 two-branch
   gate. Teeth: gate truth table (incl. `min_reader_version=3`+cache → `.updateAvailable`,
   fresh+no-cache → `.updateRequired`); **a 3xx redirect to a foreign host is refused**; a wrong
   host is refused.
2. **`ManifestClient` + gates + basemap URL.** Strict decode (attribution/generated_at optional);
   the four gates (schema_version, min_reader_version two-branch, **allOf re-validation**,
   **attribution-source cross-check**); loud failure on schema-invalid/inconsistent manifest;
   expose `attribution` + `basemapURL`. Teeth: the **live UK manifest fixture** pins clean; a
   synthetic **`min_reader_version=1` + non-empty attribution** manifest is REFUSED (allOf); a
   manifest that **strips OSM attribution while tiles carry `osm:` refs** is REFUSED; a
   `min_reader_version=3` manifest with a readable cache → `.updateAvailable`.
3. **`TileCodec` (sha256 verify + bomb-safe streaming gunzip).** zlib `inflateInit2(16+MAX_WBITS)`,
   incremental 8 MiB ceiling, 1 MiB pre-inflate refusal, end-of-stream + no-trailing-garbage.
   Teeth: **a 1-byte-flipped tile fails sha**; **a sha-MATCHING, ≤1 MiB-compressed,
   >8 MiB-inflating blob is refused MID-inflate** (the real bomb — the incremental ceiling, not
   the sha, must catch it); **trailing bytes after `Z_STREAM_END` are rejected**; the
   live-captured tiles verify + inflate.
4. **`PlaceDecoder` (§5.5, full cap enumeration) + `TileCoverage`.** Enforce and **negative-test
   every** cap — each a neuter-goes-red drop: bad `place_id` pattern, `name`/`category`/`blurb`/
   `wikipedia_title` over-length **and** a **U+202E RTL-override in `name`** (the bidi spoof —
   the most dangerous omission; the text pattern REJECTS it, plain-text rendering does not save
   it), over-count `alt_names`, non-unique / over-length `source_refs`, `tier=5`, `score=1.1`,
   out-of-range coord, non-https `image_url`, **and an `image_url` whose host is not on the
   Wikimedia allowlist** (`upload.wikimedia.org` / `commons.wikimedia.org` — verify against
   `wikidata.py` P18 output; a non-allowlisted host is **nulled**, the place kept; B4 re-pins the
   allowlist at fetch time — defense in depth). Malformed → that place dropped, tile still yields
   the rest; a fully-malformed tile → skipped, map uncrashed. `TileCoverage` cross-checked vs
   `partition.lonlat_to_z10` + the 1-ring.
5. **`TileClient` façade + the pinned public API.** Wire fetch→cache→codec→decode; pin-for-session;
   repoint swap + cache purge; padded prefetch, bounded concurrency, cancel-on-change.
   **Public API pinned verbatim (B2 consumes this):**
   ```swift
   public actor TileClient {
       public init(region: String, fetcher: TileFetching, cache: TileCache)
       public func refreshPin() async throws                       // reads current.json, pins pv; throws only on unrecoverable/programmer error
       public func places(inViewport bbox: BBox, zoom: Int) async -> [MapPlace]   // NON-throwing (Q3); never blocks the map
       public func isPresentInCurrentTiles(_ placeID: String) async -> Bool
       public func placeRef(for placeID: String) async -> PlaceRef?               // for B4 hand-off, on demand
       public var attribution: [Attribution] { get async }         // required-to-display (legal)
       public var basemapURL: URL? { get async }                   // {region}/{pv}/{filename} for B2's pmtiles source
       public var loadState: TileLoadState { get async }           // .ok | .stale | .updateAvailable | .updateRequired | .offline | .manifestInvalid
   }
   ```
   Host tests: end-to-end from live fixtures through the stubbed fetcher → `MapPlace`s; a
   mid-session repoint pins the old pv until `refreshPin()`; offline → `.stale` + served cache
   (`places()` returns cache, does **not** throw); schema-invalid manifest → `.manifestInvalid`,
   last-verified cache still served.
6. **`[XCODE/SIM]` integration note (minimal, isolated).** Document the single seam where B2's
   `MLNMapView` camera-idle calls `places(inViewport:zoom:)` and where B2 hands `basemapURL` to
   the `pmtiles://` source. **No host-verification claim** for the map wiring; everything B3 owns
   is `swift test`ed. A `[XCODE/SIM]`-tagged interface stub, not host-run.

## Compliance & non-goals

- **§5.5 trust boundary:** strict typed decode; every `place/1` cap enforced incl. the
  bidi/control **reject** patterns and the image-host allowlist; https + host-pin + redirect-pin
  on fetch; sha = integrity-not-authenticity (bounded inflate is the bomb guard); plain-text
  values only (no HTML/attributed rendering — B2/B4); **skip-not-crash** for every malformed case.
  **P10:** published tiles are untrusted even though we published them.
- **§5.6 / §6:** newer + cache → `.updateAvailable` (serve cached older + nudge); newer + no cache
  → `.updateRequired`; schema-invalid manifest → `.manifestInvalid` (loud, serve last verified);
  older tolerated in-window; offline → serve cache + `.stale`; **never silently misread, never
  empty map, never block the map.**
- **Determinism:** sha256 over gzipped bytes; cache key `region/pv/x/y` + sha, no wall-clock.
- **Non-goals (seams left, not built):** offline region packs (**B7**); snapshot fallback for
  absent places + place-card image *fetch* with the allowlist re-pin (**B4**, via B1); the
  MapLibre map + pin styling + basemap streaming (**B2**); search (**B9**).

## Gates & acceptance

- **Adversarial gate (done for this plan; repeat for the impl PR):** ≥ 3 critics, distinct
  lenses — (a) **feasibility that BUILDS on real Swift 6.3.3** against the live fixtures, (b)
  security / untrusted-data (§5.5 caps, host+redirect pin, streaming-bomb guard, sha semantics,
  allOf + attribution-source gates), (c) spec-fidelity + coherence (version/§5.6 states, the
  non-throwing B2↔B3 contract, layering vs B1/B4). Cross-examine; report raised/survived/fixed.
- **Teeth:** every cap and gate has a neuter-goes-red test — the flipped sha, the **sha-matching
  inflate bomb**, the **U+202E name**, the **allOf-violating** and **attribution-stripped**
  manifests, the **cross-host redirect**, a `min_reader_version=3`+cache → `.updateAvailable`.
  Constants (`PrefetchRing.radius`, `TileCache.maxBytes`) named + comment-flagged tunable.
- **Acceptance:** the pure package builds + all `swift test` pass on Swift 6.3.3; the live UK
  tile round-trips (sha → streaming-gunzip → decode → `MapPlace`); the bomb blob is refused
  mid-inflate; a `min_reader_version=3` manifest → `.updateAvailable`/`.updateRequired` (never
  crash/empty); an attribution-stripped manifest over `osm:` tiles is refused.
- PR → `develop`, labels **`sourcery-review` + `greptile-review`**, report on `wp/b3`. No
  self-merge; fable's independent review; `main` is Rob's.
