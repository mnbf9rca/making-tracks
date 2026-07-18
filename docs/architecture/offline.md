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

- **Incremental-persist — BUILT (#193, WP-B10d).** Each object is fetched, verified, and streamed to the
  content-addressed store **as it arrives** (`writeVerifiedTileObject` / `prepareVerifiedBasemapObject`),
  so memory is bounded per-object, not per-pack — the RAM-buffer-the-whole-pack / all-or-nothing behavior
  is **gone**. (This was the jetsam-kill fix; earlier revisions of this doc marked it unbuilt — corrected
  on the #193 merge.)
- **Resume — BUILT (#193), object-granular.** An interrupted download resumes via `updatePlan` sha-skip
  over what is already in-store; only explicit **cancel** discards (**pause ≠ cancel**). **Sub-object
  resume is NOT built** — a half-streamed *basemap* restarts from zero because it is one monolithic
  `.pmtiles` (the chunking-bound gap, §3 / WP-RM §8 INV-4); the fix is the per-cell basemap (§3).
- **GC retains in-progress objects — BUILT (#193).** Mark-and-sweep protects both installed
  (`referencedObjects`) and **live in-progress** (`referencedInProgressObjects`) objects before sweeping.
  **WP-DL-SAFETY (#202) closes the orphan sweep gaps:** hidden `*.tmp` object files and abandoned
  `root/tmp/*` install dirs are swept by deferred maintenance and at `beginDownload`; final object GC is
  fail-closed if installed/current metadata cannot be trusted, and live basemap prepare temps are registered
  so a concurrent sweep skips them while hash verification stays outside the store lock.
- **Background `URLSession`** (WiFi-preferred, discretionary) — **BUILT for object transfer (#197,
  WP-B10d2 / #191 ruling)** while the app is alive/backgrounded. Pack object fetches now use the
  delegate-backed background configuration (`sessionSendsLaunchEvents`), recreate the identifier session
  for UIKit `handleEventsForBackgroundURLSession`, and deliver stored handlers after
  `urlSessionDidFinishEvents`; manifest/current metadata fetches remain foreground. This is the
  **INV-10a** split in WP-RM §8. **Full task adoption** (task-state re-adoption, pack completion after app
  death, progress reattachment, partial-object/system-task recovery) remains the **INV-10b** residual owned
  by **WP-DL-SAFETY**. Do not claim unattended completion after termination until INV-10b is built and
  tested. Neither is WP-B10d (which shipped the foreground incremental engine above).
- **Download safety contract:** the full set of download-safety invariants (atomicity, resume,
  idempotence, chunking bound, GC soundness, crash-window consistency, disk/ENOSPC safety, concurrency,
  honest progress, relaunch adoption) — each with a today-vs-target marker, `file:line`/PR evidence, an
  owning WP, and its acceptance test — lives in **[[WP-RM §8 download safety contract]]**. After
  WP-DL-SAFETY (#202), the remaining open gaps are **INV-4** (basemap chunking → WP-RM-P pipeline cut +
  WP-RM-G app render) and **INV-10b** (full background-task adoption after relaunch). INV-10a is satisfied
  by #197; INV-1/5/6/7/8 are satisfied by #202's engine hardening. INV-9 remains the #196 UI contract unless
  a future non-UI caller needs engine-level paused/running state.
- **Compression:** place tiles are app-level gzip at rest and on device, **sha over gzipped bytes** (no
  `Content-Encoding` — transport auto-decompress would break checksums); pmtiles internally compressed;
  thumbs are WebP.

## 5. Single-origin invariant

- **Target invariant:** all app fetches single-origin `tiles.making-tracks.app` (tiles, basemap, sidecars,
  thumbs, glyphs, search index, `current.json`); no third-party fetch at runtime. **⚠ NOT true today** —
  the shipped place-card image path still fetches from **Wikimedia** (`allowedImageHosts =
  {upload,commons}.wikimedia.org`, `MakingTracksTiles.swift:582`); single-origin thumbs are unbuilt.
  **Single-origin holds only after WP-IMG-B/B2 lands.** Search is **local** (queries never leave the
  device); no third-party geocoder.
- **Redirect/origin enforcement (#191 ruling):** first-party tile/object URLs are accepted only for
  `https://tiles.making-tracks.app`. Foreground transfers keep the synchronous redirect veto; background
  pack object transfers add the WP-B10d2 (#197) post-hoc check of the final response URL before accepting
  the delegate-staged bytes. A missing or off-origin final URL discards the temporary file and fails the
  object closed.

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
| **Incremental download engine (file-backed staging, resume, pause/cancel, GC)** | **WP-B10d, PR #193 (MERGED)** |
| **Background object-transfer wiring + final-response origin verification** | **WP-B10d2, PR #197 (MERGED; closes #191)** |
| **Download SAFETY contract (10 invariants: atomicity/resume/idempotence/chunking/GC/crash-window/disk/concurrency/progress/relaunch)** | **WP-RM §8** (`2026-07-18-wp-rm-region-manager.md`); WP-DL-SAFETY (#202) satisfies INV-1/5/6/7/8; gaps → WP-RM-P + WP-RM-G (INV-4), INV-10b full task adoption (deferred); INV-10a session recreation/object-transfer handoff satisfied by #197; INV-9 remains the #196 UI contract unless promoted to engine scope |
| **Image-index schema + thumbs path/content-addressing (contract owner)** | **WP-IMG-P (`2026-07-17-wp-images-photos.md`, #158, MERGED)** |
| Photos card layout / attribution UI (consumer); offline-thumb bundling | WP-CARD (`2026-07-18-wp-card-overhaul.md`, #172) + WP-IMG-B2 |
| Description sidecars | codex4 description-index (PR #173) |
| World basemap z0–6; region sharding; cover-traffic §7 | Region model (`2026-07-17-wp-regions-model.md`, #131) |
| Cover-traffic / privacy commitments (P14/P15) | `docs/superpowers/amendments/2026-07-17-privacy-commitments-amendment.md` |
| Onboarding pack-offer; cold-start; download progress | B10 (`2026-07-18-wp-b10-onboarding.md`, #174) |
| Search index (local, names + zones) | B9 (`2026-07-18-wp-b9-search.md`, PR #178, OPEN) |
| Category icons (SF Symbols); layers filter | WP-ICONS / hide+icons (`2026-07-17-wp-place-state-icons.md`, #168/#170) |
