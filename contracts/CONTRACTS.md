# Making Tracks Contracts

This directory is the executable WP-A0 contract package. Machine-readable artifacts in `schemas/`, `versions.json`, `regions/`, `basemap-budget.json`, and `src/mt_contracts/` are the source of truth; this document explains how downstream work packages consume them.

## Status And Immutability

All boundary artifacts carry schema versions from `versions.json`. Shipped shapes change only by bumping the relevant `schema_version`; never edit a shipped contract in place.

`place_id` is immutable once shipped. The `mt1_` scheme, the canonical mint-key grammar, validation of all known ID schemes, and `fixtures/place_id/frozen_vectors.json` are Principle 7 tripwires. Caps are named in `src/mt_contracts/caps.py`, and schema literals are tested against those constants.

The Python package exposes the shared A1/A2 surface at `mt_contracts`: `is_canonical_ref`, `strip_unsafe_text`, `available_regions`, and `load_region_config`. Wheel builds ship `schemas/`, `regions/`, `versions.json`, and `basemap-budget.json` as package data and load them through `importlib.resources`; editable checkouts keep the repo-root fallback.

## `place_id`

Grammar: `mt1_<26 Crockford base32 chars>`, where the body is derived from the lower 128 bits of `sha256(mint_key)`. Current minting emits `PLACE_ID_PREFIX == "mt1_"`; validation uses `KNOWN_ID_SCHEMES`, so shipped IDs keep validating after a future mint scheme is added.

Canonical mint keys are exact, ASCII, lowercase-prefix, whitespace-free strings:

- `wd:Q123`
- `osm:{node|way|relation}/456`
- `hehle:1234567`
- `plaque:openplaques/9876`
- `wp:12345`

`hehle` means Historic England List Entry. `wp` means a Wikipedia page ID. New sources are append-only: add a new source grammar, priority entry, and conformance vectors without altering existing grammars or minted IDs.

IDs are minted once for new clusters, then owned by the registry. Anchor priority is QID, OSM node, OSM way, OSM relation, Historic England, Open Plaques, Wikipedia page ID; this is mint-time determinism only and has no meaning after mint. Registry lookup is by union of every ref ever attached to a place, so QID merges and OSM tag churn keep the same ID.

Ambiguous multi-place ref matches raise `AmbiguousRefsError` with candidate `.place_ids`; the contract never silently merges. `superseded_by` is soft de-dup: loser IDs remain valid forever, resolve transitively to the terminal winner, and cycles are rejected. Published tiles must carry only winner IDs; `registry.tile_winner_violations` is the A7 guard.

Registry records use `first_shipped_version` as the first pipeline version that minted the place and made it eligible for publish; reconcile sets it at mint time and never rewrites it. After a successful publish, A7 calls `registry.mark_shipped(records, shipped_ids, publish_version)`, which advances `last_seen_version` for the IDs that actually shipped and backfills `first_shipped_version` only for legacy records where it is empty. A7 must not mutate registry records directly.

## Place JSON

Place records contain `place_id`, `name`, `lat`, `lon`, `category`, `tier`, `score`, optional `alt_names`, `blurb`, `image_url`, `wikipedia_title`, and `source_refs`.

The schema applies named caps from `caps.py`. `SAFE_TEXT` guards every source- or LLM-derived string, including nullable `blurb` and `wikipedia_title`: C0 controls, DEL, C1, U+2028/U+2029, bidi overrides and isolates, U+200B/U+200C/U+200D, U+2060, and U+FEFF are rejected. LRM/RLM are deliberately allowed so legitimate RTL names survive. `strip_unsafe_text` removes exactly that denylist and preserves LRM/RLM. `image_url` is `https://` plus control/whitespace-free; host allowlisting is app configuration. Non-finite floats (`NaN`, `Infinity`) are rejected in the Python validation layer. `source_refs` use the open canonical-ref grammar, with source-specific canonical checks for known prefixes such as `wd`, `osm`, `hehle`, `plaque`, and `wp`.

## Place Tile

Tiles are z10 XYZ JSON envelopes served at `{publish_version}/tiles/10/{x}/{y}.json.gz`. Gzip uses `mtime=0` and header OS byte `255`, so identical tile content produces stable bytes and stable SHA-256 across Python/zlib platforms. `tilecodec.gzip_tile` enforces `MAX_TILE_COMPRESSED_BYTES`; readers use `tilecodec.safe_gunzip`, bounded by both `MAX_TILE_COMPRESSED_BYTES` and `MAX_TILE_UNCOMPRESSED_BYTES`. Do not use `gzip.decompress` for untrusted tile bytes.

`MAX_PLACES_PER_TILE = 4000`. `caps.select_tile_places` deterministically sorts by tier ascending, score descending, then `place_id` ascending, and enforces both count and serialized-byte caps. A7 must log every dropped place.

## Manifest

A region manifest contains schema version, reader floor, publish version, tile index with per-tile SHA-256 and byte counts, counts by tier, basemap descriptor, and prompt provenance. `provenance` has `minItems: 1` and includes `task_id` to avoid cross-task LLM-cache collisions.

`basemap.filename` is anchored, character-classed, length-capped, and `.pmtiles`-suffixed to prevent path traversal. `tiles` and `provenance` arrays are bounded. The publisher writes manifests last and atomically under versioned publish paths; rollback is repointing the manifest.

## Search Index

The v1 `search-index` contract is a local-search artifact over places that actually shipped in z10 tiles. It is not a source corpus and must not contain broader live DB rows that the app cannot resolve from a tile. Entries carry `kind`, `place_id`, `name`, `alt_names`, folded `tokens`, `lat`, `lon`, `tier`, and `category`. `place_id` is required for `kind == "place"` and must be null for future `kind == "zone"` entries. Text uses the same `SAFE_TEXT` denylist and place/category caps as place JSON. Tokens are bounded by `SEARCH_TOKENS_MAX` and `SEARCH_TOKEN_MAX`; each artifact is capped by `MAX_SEARCH_INDEX_BYTES`.

Full offline search is prefix-sharded under:

- `{region}/{publish_version}/search/full/{prefix}.json`

Those shard objects are listed in `pack-descriptor.json` as `kind: "search_index"` with per-object `sha256`, `bytes`, and `schema_version`, so pack updates can delta per changed prefix shard. ASCII tokens shard by their first one or two lowercase alphanumeric characters. Non-ASCII tokens shard by `u_` plus the first eight lowercase hex characters of `sha256(token_utf8)`, via `mt_contracts.shard_key_for_token`; this keeps object paths ASCII while preserving native-script search terms inside the artifact. A full shard validates only if each entry has at least one token that maps to that shard key.

Full shards that would exceed `MAX_SEARCH_INDEX_BYTES` split deterministically instead of aborting the publish. First-level split shards append `_x`, where `x` is the token's next lowercase ASCII alphanumeric character when one exists; short tokens and non-ASCII hash buckets use `_hN`, with `N` the first hex character of `sha256(place_id)`. If a split shard is still over the byte cap, it appends additional `_hN` place-id hash suffixes, consuming the next hash character at each level, until the artifact is under cap. Readers that search a shorter prefix load every shard whose key is the base prefix or starts with `{base}_`; readers with a longer prefix may narrow to the matching next-character split. `mt_contracts.shard_key_matches_token` is the semantic validator for unsplit, first-level split, and recursively hash-split full shards.

The online no-pack search entry point is the notable compact index under:

- `{region}/{publish_version}/search/compact.json`

The compact object is not pack-scoped and is not listed in the pack descriptor. It is discovered from `regions.json` via required `search_compact: {path, sha256, bytes, schema_version}`. `validate_region_index` requires that path to match the same region id and `publish_version`, keeping `current.json`'s publish version as the single version authority. When upgrading a pre-search `regions.json`, the publisher must not synthesize compact URLs for old publish versions that do not contain the object; those legacy entries are omitted until republished with real compact metadata.

## Region Config

Region IDs and source keys are lowercase additive identifiers, not enums. Top-level region IDs are deterministic slugs derived from the source extract path: strip the Geofabrik continent directory and `-latest.osm.pbf` suffix, then use the remaining lowercase hyphenated basename unchanged (`europe/united-kingdom-latest.osm.pbf` -> `united-kingdom`; `asia/malaysia-singapore-brunei-latest.osm.pbf` -> `malaysia-singapore-brunei`). The region config filename must be `{region_id}.json`, and `load_region_config` rejects filename/content mismatches. Display names are taken from the extract source metadata, not hand-authored labels; for Geofabrik extracts, use the proper extract name published by Geofabrik. The pre-release legacy IDs `uk` and `malaysia` are not aliases; a cutover to new region IDs must be paired with the app-side hardcoded region-list update in the same release. Sources are optional per region; no source or region is load-bearing. Region config includes `region_id`, `display_name`, `bbox`, `languages`, `sources`, and `basemap`. `source_pmtiles` is HTTPS-only and control/whitespace-free. A1 reads configs through `available_regions()` and `load_region_config(region_id)`.

## Basemap Pack Budget

The offline pack ceiling is `caps.PACK_BUDGET_CEILING_BYTES == 3_221_225_472` bytes. The chosen v1 max basemap zoom is 14.

Measured z14 pack sizes:

| Region | z14 bytes | Decision |
|---|---:|---|
| United Kingdom | 1,463,177,229 | Country pack viable |
| Malaysia, Singapore, and Brunei | 223,155,574 | Country pack viable |

These rows are exact real extract sizes and are mirrored in `basemap-budget.json` and `regions/*.json`.

## Versioning And Compatibility

`versions.MIN_SUPPORTED_VERSIONS` records the §5.6 back-compat floor per artifact, today all `1`. `versions.check_version(reader_max, data_version, min_supported)` returns:

- `OK`: data is within the reader's supported window.
- `TOO_NEW`: keep cached older data and prompt for app update.
- `TOO_OLD`: refuse the data.

On fresh install with only too-new data, the app shows an update-required state. A manifest's `min_reader_version` is an additional data-declared floor: if the app's max understood version is below it, the reader refuses.

## Consumer Map

| Consumer WP | Consumes from A0 |
|---|---|
| A1 | `regions/*.json`, `region-config.schema.json`, `available_regions`, `load_region_config`, `strip_unsafe_text`, `is_canonical_ref` |
| A1b | `place_id.py` canonical `wd` and `wp` source-ref grammar for Wikidata and Wikipedia extractors |
| A2 | `place_id.py`, `registry.py`, `registry-record.schema.json` |
| A7 | `tile.schema.json`, `manifest.schema.json`, `checksums.sha256_hex`, `tilecodec.gzip_tile`, `caps.select_tile_places`, `registry.tile_winner_violations`, region `basemap` block |
| B1 | `place.schema.json` |
| B3 | `manifest.schema.json`, `tile.schema.json`, `versions.check_version`, `tilecodec.safe_gunzip` |
| B7 | `basemap-budget.json`, `caps.PACK_BUDGET_CEILING_BYTES`, region `basemap` block |
| B9 | `search-index.schema.json`, `region-index.schema.json` `search_compact`, `pack-descriptor.schema.json` `search_index`, `versions.check_version` |
