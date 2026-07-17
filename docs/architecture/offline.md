# Guide to Offline — canonical reference

**Maintenance rule:** whoever merges a WP that changes an offline fact updates THIS doc in the same PR.
This is the single source of truth — do not re-derive offline facts from the individual design docs;
fix them here and point to the owning design (§7). Facts + invariants + pointers only, not a re-statement
of the designs.

## 1. The completeness invariant (Rob, 2026-07-18 — binding)

> **A fresh install + ONE downloaded bundle + airplane mode = a fully working region:** map, labels,
> place cards, blurbs, and (if opted) photos — with **zero** network.

- **Images are the ONE user-optional component** (the "include images" toggle). **Everything else is
  mandatory** in a bundle.
- Anything the map needs at runtime that is neither app-shipped (§2) nor in the bundle **breaks offline**
  and is a bug. This invariant is an **acceptance test** in every offline-touching build WP (neuter any
  one component → the test goes red).

## 2. Where each asset lives: app-shipped vs bundled vs runtime-fetched

| Asset | Where | Notes |
|---|---|---|
| **World basemap z0–6** | **App-shipped** | The low-zoom world tier; present without any pack (region-model). |
| **Category icons** | **App-shipped** | SF Symbols via `style.setImage`; no remote sprite, no sprite URL. |
| **Glyphs / fonts** | **⚠ runtime-fetched today → must become app-shipped/bundle-once** | Labels render from `tiles.making-tracks.app/global/fonts/{fontstack}/{range}.pbf` (`PaperStyle.swift:2`). **Offline this breaks region labels.** Glyphs are GLOBAL (one Noto Sans stack) → **bundle ONCE app-side**, NOT per-pack. Cover the labelled scripts (incl. Malaysia Jawi/Arabic). *Open work.* |
| **Place tiles (z10)** | **Bundled (mandatory)** | `objects/tiles/{sha}.json.gz`, content-addressed. |
| **Basemap (region)** | **Bundled (mandatory)** | Per-pack; delta strategy → per-cell content-addressed objects (§3; ratified #177, build pending WP-RM-P). |
| **Description sidecars** | **Bundled (mandatory)** ⚠ *target* | `descriptions/10/{x}/{y}.json` (codex4 #173). **Not in the shipped pack yet** — the app reads no `descriptions/` (pending the pack-descriptor build, WP-RM-P). |
| **Image-index sidecars** | **Bundled (OPTIONAL — part of "include images")** ⚠ *target* | `images/10/{x}/{y}.json` (#158). Rides *with* thumbs (an image-index entry is useless offline without its thumb) — a without-images pack carries neither. **Not in the shipped pack yet** (WP-IMG-B2). |
| **Image thumbs** | **Bundled (OPTIONAL)** ⚠ *target* | `thumbs/{sha[:2]}/{sha}.webp`, content-addressed; the "include images" toggle (WP-IMG-B2). **Not in the shipped pack yet.** |
| **Search index** | **Bundled + standalone** ⚠ *target* | Per-region names + zone names; local search (B9, PR #178 OPEN). **Not built.** |
| **`current.json` (manifest/version poll)** | **Runtime-fetched every launch** | The update check — a first-party ping to `tiles.making-tracks.app` even with a full pack. Check on launch/user-action, **never on a schedule**. Not eliminated by a pack. |

> **⚠ Today vs target:** the shipped pack carries **tiles + basemap only** (the `ios` code references no
> `descriptions/`, `images/10/`, or `thumbs/`). The mandatory/optional rows above are the **completeness
> target** the invariant (§1) defines — they land as the pack-descriptor + owning build WPs ship. Rows
> marked ⚠ *target* are not in a pack a user can download today.

## 3. Content-addressing + delta model

- **Every bundled content type is a `{sha, bytes}`-listed object.** The tile `manifest.json` is **frozen**
  (`schema_version const 1`, `additionalProperties:false`) → it lists only **tiles + basemap**; **all other
  content (thumbs / description + image-index sidecars / search index) is listed in the versioned
  PACK-DESCRIPTOR file** (sidecars cannot ride the manifest — region-model §6). **⚠ The pack-descriptor is
  designed, not built** — it exists in no schema, publisher, or consumer today (ratified #177; build pending WP-RM-P → the
  WP-RM-P emitter + app-side reader); until then only the manifest's tiles+basemap deltas. Once built,
  refresh runs `updatePlan` **sha-skip** over both → an unchanged object (same sha) is not re-downloaded
  (**free delta**).
- **Per-content-type delta:**
  - **Place tiles, image thumbs** — content-addressed blobs → delta **free** (unchanged sha skipped).
  - **Description + image-index sidecars** — per-tile files → need per-file `{sha, bytes}` **manifest
    entries** so they sha-skip too.
  - **Basemap** — the monolithic `pmtiles` whole-file re-download is the "GB every time" gap; the design
    answer (WP-RM §6, #177) is **per-cell content-addressed basemap objects** (delta free at z10, same grid
    as tiles), over range-based pmtiles sync — **except the z7–9 mid-zoom tier, which is one shared
    per-region object** (below the z10 cell grid), so it re-downloads whole on any change (a small,
    bounded object, not the "GB every time" gap).
- **No content type re-downloads whole on a refresh.**

## 4. Download engine rules

- **Incremental-persist is MANDATORY** — stream each **verified** object to the content-addressed store
  **as it arrives** → **constant memory bound** regardless of pack size. (RAM-buffering the whole pack is
  unacceptable — the device was jetsam-killed at far smaller working sets.) **⚠ NOT built today:** the
  shipped `OfflineRegionDownloader` RAM-buffers the whole pack and installs all-or-nothing — it **violates
  this mandatory rule** and is the open engine work below (WP-B10d). This row is the target, not current.
- **Resume is free** *(target, not built)*: once incremental-persist lands, an interrupted download
  resumes **object-granular** via `updatePlan` sha-skip. **Today there is no resume** — an interrupted
  download restarts from zero (a consequence of the RAM-buffer above). *Open engine work (WP-B10d).*
- **GC must RETAIN in-progress objects** (failed-install GC currently removes orphans — adjust, or the
  resume set is reclaimed).
- **Background `URLSession`** (WiFi-preferred, discretionary) — the config exists but is **dead-wired**
  today (production uses a foreground ephemeral fetcher); it must be wired. *Open engine work (WP-B10d).*
- **Compression:** place tiles are app-level gzip at rest and on device, **sha over gzipped bytes** (no
  `Content-Encoding` — transport auto-decompress would break checksums); pmtiles internally compressed;
  thumbs are webp.

## 5. Single-origin invariant

- **Target invariant:** all app fetches single-origin `tiles.making-tracks.app` (tiles, basemap, sidecars,
  thumbs, glyphs, search index, `current.json`); no third-party fetch at runtime. **⚠ NOT true today** —
  the shipped place-card image path still fetches from **Wikimedia** (`allowedImageHosts =
  {upload,commons}.wikimedia.org`, `MakingTracksTiles.swift:582`); single-origin thumbs are unbuilt.
  **Single-origin holds only after WP-IMG-B/B2 lands.** Search is **local** (queries never leave the
  device); no third-party geocoder.

## 6. Cover-traffic invariant (→ #131)

- **Sub-country downloads carry cover-traffic** — decoys that are indistinguishable on every observable
  axis (spatial spread, timing/order, size/count, edge-reaching) drawn from a **fixed, intersection-
  resistant, location-independent cohort** (never fresh-random per fetch), **stable across a pack's update
  fetches**. The decoy **budget scales with selection distinctiveness**; the numbers are Rob-gated. Full
  detail + the ratified rulings: **[[#131 region-model §7 + the P14/P15 amendment]]**.

## 7. Ownership pointer table (which design owns which decision)

| Decision | Owning design |
|---|---|
| Completeness invariant; packs/zones; delta strategy | WP-RM (`2026-07-18-wp-rm-region-manager.md`, PR #177, MERGED) |
| **Offline download engine + content-addressed pack store** | **PR #149 (MERGED)** + region-model §3/§5 (`2026-07-17-wp-regions-model.md`, #131) |
| **Image-index schema + thumbs path/content-addressing (contract owner)** | **WP-IMG-P (`2026-07-17-wp-images-photos.md`, #158, MERGED)** |
| Photos card layout / attribution UI (consumer); offline-thumb bundling | WP-CARD (`2026-07-18-wp-card-overhaul.md`, #172) + WP-IMG-B2 |
| Description sidecars | codex4 description-index (PR #173) |
| World basemap z0–6; region sharding; cover-traffic §7 | Region model (`2026-07-17-wp-regions-model.md`, #131) |
| Cover-traffic / privacy commitments (P14/P15) | `docs/superpowers/amendments/2026-07-17-privacy-commitments-amendment.md` |
| Onboarding pack-offer; cold-start; download progress | B10 (`2026-07-18-wp-b10-onboarding.md`, #174) |
| Search index (local, names + zones) | B9 (`2026-07-18-wp-b9-search.md`, PR #178, OPEN) |
| Category icons (SF Symbols); layers filter | WP-ICONS / hide+icons (`2026-07-17-wp-place-state-icons.md`, #168/#170) |
