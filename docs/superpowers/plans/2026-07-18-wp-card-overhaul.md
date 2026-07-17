# WP-CARD — place-card overhaul (#171), absorbing WP-IMG-B (photos + blurbs)

**Status:** design (opus). Rob ordered a **full place-card overhaul** (#171) — today's card is "bland — no
text, no images." This doc is the card-overhaul master design; the earlier WP-IMG-B (photos + blurbs) is
**absorbed** as the photo and blurb *components* of the card. Adversarial-gate → PR to `develop`,
`sourcery-review`. App changes target `ios`. Thread `p2p/fable__opus`.
Consumes the **shipped** contracts (#158 image-index + thumbs; #157 Wikipedia attribution). Attribution
is a **compliance surface — non-optional UI, small at the card bottom** (Rob's hierarchy). Argue-don't-
diverge on privacy/licensing.

## Why

The place card is the payoff of the discovery loop but is currently near-empty. Rob's hierarchy (#171):
**PROMINENT** name → type → description → photo → list membership; **SMALL** attribution at the bottom
(+ an optional outbound source link). This design gives the card a real layout and wires in the shipped
image pipeline. **§0 is the new card layout/hierarchy;** §1–§6 are the **photo** component (the image-index
sidecar, thumb integrity, mandatory attribution, single-origin fetch, bounded cache, offline); §7–§8 are
the **blurb** component (Wikipedia text + CC BY-SA). Pipeline/contract parts stand as first drafted; the
card-layout, action-row, list-membership, and a11y sections are the #171 expansion.

## Grounded facts (recon: shipped contracts on `develop`; app on `origin/ios`; all cited)

- **Shipped image-index contract (#158)** — `contracts/schemas/image-index.schema.json` (`.../image-index/1`):
  `{schema_version const 1, min_reader_version 1–999, z const 10, x/y 0–1023, places[] maxItems 4000}`;
  each place `{place_id, thumb_sha256 (hex64), bytes, width, height, attribution}` where **attribution
  requires the KEYS** `{creator, license_code, license_name (≤128), license_url (https, pinned to
  creativecommons.org by|by-sa versions/ports), source_url (https commons File:, injection-guarded),
  modified (const true)}`. **[gate — creator is NULLABLE].** `creator` is `anyOf:[string,null]`; the
  schema forces a **non-null** creator **only** when `license_code` matches `^CC-BY(-SA)?-…` — so for
  **PD / CC0-1.0** (also in the accept set) `creator: null` is **valid and emitted** (`images.py:552-556`).
  So "requires all six values" is wrong: PD/CC0 photos legitimately carry a null creator and need no
  attribution author. The app must handle both the **license set** `{PD, CC0-1.0, CC-BY 1.0–4.0,
  CC-BY-SA 1.0–4.0}` (NC/ND excluded) and a **null creator**. **The pipeline emits `min_reader_version: 1`** (`images.py:600`) —
  the app reader is at **2** (`VersionGate.readerVersion`), so it gates in **cleanly, no reader bump.**
  Thumbs: `thumbs/{sha[:2]}/{sha}.webp` at the public root (`images.py:411`), content-addressed, global.
  The sidecar is **OPTIONAL** ("tile place payloads remain unchanged") → tiles without images degrade.
- **App reuse map (`origin/ios`, `MakingTracksTiles.swift`):**
  - **`HTTPTileFetcher`** — `trustedHost = "tiles.making-tracks.app"`, https + host-validation + redirect
    validation. **Reuse it for the image-index JSON AND the thumb blob** (same origin) — NOT
    `ImageLoader`, whose `PlaceContentGuards.allowedImageHosts` is still the two **Wikimedia** hosts
    (`:582`) and which has **no sha verification**.
  - **`TileCodec.decode(gzipped:expectedSHA256:expectedBytes:)`** — the `sha256(data)==expected` + byte +
    inflate-bomb pattern. **The thumb path must mirror this** (verify fetched thumb `sha256 == thumb_sha256`);
    `ImageLoader` has neither check — content integrity is greenfield.
  - **`TileClient`** (actor) fetches z10 tiles at `…/{region}/{pv}/tiles/10/{x}/{y}.json.gz` per viewport
    (1-tile prefetch ring, concurrency 4) — the **direct analog** for `…/images/10/{x}/{y}.json`.
  - **`TileCache`** — 64 MiB disk cache, access-counter LRU — the template for a bounded thumb cache.
  - **`VersionGate`** — `RegionIndex.decode`/`Manifest.validate` gate `schema_version` + `min_reader_version`;
    the image-index decoder mirrors it.
  - **Offline packs are BUILT, not a stub [corrects the #129 assumption].** `OfflineRegionDownloader` +
    `OfflineRegionStore` — content-addressed `objects/tiles/{sha}.json.gz` + `objects/basemaps/{sha}.pmtiles`,
    atomic install + rollback, GC of unreferenced objects, storage-headroom, background `URLSession`.
    They bundle **only tiles + basemap** today — **no `.webp` / thumb object** — so offline thumbs are a
    concrete **extension** of this store, not a future contract. `RegionIndex` already carries
    `bytesWithThumbnails`/`bytesWithoutThumbnails` size estimates.
  - **Card + attribution:** `PlaceCardSheet` renders an image via `ImageLoader().fetch` + a 16 M-pixel
    decode-bomb guard, `maxHeight 180`; `PlaceCardModel` carries `imageURL: URL?` but **no sha / width /
    height / attribution**. **Per-image attribution UI is greenfield**; the only attribution UI is the
    global manifest `CreditsView`. `AttributionModel` is dead (tests only). **Image-index/thumb
    consumption is entirely greenfield** (grep-confirmed).
- **Blurb (Phase 2):** **not published today** — publish emits only `{place_id, name, lat, lon, category,
  tier, score, source_refs}` (`publish_stage.py:234-249`). The **Wikipedia plaintext extract IS captured**
  (`extractors/wikipedia.py:53`, `explaintext=1` → plaintext, cap 300) into `source_records.props_json`,
  but feeds **scoring only** — never a published place. The app **already renders `blurb`**
  (`PlaceCardModel.blurb` + `Text(verbatim:)`), so its render path is a ready template. **Wikipedia
  attribution plumbing already shipped (#157):** `a1d_sources.json` `wikipedia: CC-BY-SA-4.0`,
  `attribution.py` `wp→wikipedia`, a test, an `attribution.md` row — so the `attribution.md:30` "requires
  a new wikipedia source…" note is **stale**. `blurb` is SAFE_TEXT-guarded but **SAFE_TEXT does not strip
  HTML** (moot today — the extract is plaintext).

---

# CARD LAYOUT & HIERARCHY (#171 — the overhaul)

**Grounded:** today `PlaceCardSheet` is a flat stack — name, category (verbatim), image (`maxHeight 180`),
blurb, action buttons (Save/Visited/Love), altNames, sourceNames (joined "/"), and a debug `placeID`. Rob:
"bland — no text, no images." The overhaul gives it a hierarchy.

## 0.1 The card, top to bottom (Rob's hierarchy)

1. **Name — PROMINENT** (large semantic title), the visual anchor.
2. **Type** — the category as its **#166 icon + label** (e.g. museum glyph + "Museum"), a subtitle under
   the name (§0.2).
3. **Description** — the blurb (§7–§8), body text, `Text(verbatim:)`.
4. **Photo** — the thumb (§1–§6), `scaledToFit`, sized from the index's `width/height`; **absent → the card
   omits the photo block** (no broken frame, no forever-spinner).
5. **List membership** — which **user** lists this place is in (§0.4, the B5 seam).
6. **Action row** — Save / Seen / Hide (§0.3), the core loop + triage.
7. **Attribution — SMALL, at the bottom** (§3): photo credit (+ Wikipedia text credit) in caption type
   with the outbound source link(s). Small per Rob's hierarchy but **still mandatory/non-optional** — a
   photo/text never renders without its credit.

Drop the visible `placeID` (dev-only affordance if kept); `altNames` fold under the name, `sourceNames`
are subsumed by the attribution block. *(Order matches Rob's spec exactly — description before photo; if
a photo-first layout reads better in practice, that's a deviation to run past Rob, not assumed here.)*

## 0.2 Type display (rides #166)

The type row = the WP-ICONS `category → SF-Symbol` glyph (with the fallback for unknown/`uncategorized`) +
the human category label. Pure presentation — `category` is already on the place; no new data.

## 0.3 Action row — Save / Seen / Hide, with rapid triage (#167)

The primary row carries the full triad: **Save** (= membership in the **"Want to go"** system list —
`CoreLoopController.setSaved` add/removes it there; **Save IS a list op, not a separate concept** —
important for §0.4), **Seen** (one-tap visit + optional loved heart), **Hide** (rapid triage — one tap →
**the card closes/dismisses** → "Hidden — Undo" toast, per the #167 ruling; there is no card deck, so
triage is hide → close → tap the next pin → hide). All one-tap, reversible, no confirmation (spec §3.4).
Hide's card surface lives here (WP-HIDE consumes it). The row **wraps** at accessible text sizes (§0.5),
never truncates or hides an action.

## 0.4 List-membership display — the B5 seam (design the seam, NOT sharing)

Show which **user** lists the place is in — a local derivation over `list_items` for this `place_id`
(like `viewportState`). **[gate — reconcile Save vs membership].** `Save` already writes `list_items`
(the "Want to go" system list), so the membership chips **MUST exclude the system Save list** (Save is
the *button*; chips show only *user-created* lists) — otherwise the same fact renders twice ("Saved" +
"In: Want to go"). **Today only "Want to go" exists** (the seed list; no user-list creation UI until B5),
so the chip row is **empty until B5** — the seam is wired (the read + the render), the content arrives
with B5. **Pre-condition flag for B5 [latent bug]:** the shipped `saved` derivation is *"member of ANY
list"* (`Derivations.swift:65`, no `list_id` filter) while `setSaved` removes only from "Want to go" — so
once B5 adds a second list, a place in only that list reads `saved=true` but the Save button's
`removeFromList("Want to go")` is a no-op (can't clear). **Narrow `saved` to "in Want to go" before B5
ships user lists.** **Design the seam, not the feature:** the card *reads* membership now; full list
management is B5; **sharing is out of scope until accounts exist** (privacy.md). Local-only, no network.

## 0.5 Accessibility (standing criterion — measurable)

- **Dynamic Type:** all card text semantic fonts; the layout **reflows** at accessibility sizes (action row
  wraps, photo scales) — name/description never truncate.
- **VoiceOver:** the photo has an `accessibilityLabel` ("Photo of <name>"); the attribution + source link
  are focusable and announced ("Photo by <creator>, <license>, source"); actions carry labels +
  saved/seen/hidden state in `accessibilityValue`.
- **Contrast:** the small attribution and any photo-overlay text meet **WCAG AA 4.5:1** — attribution is
  never rendered so small/faint it fails (a compliance *and* a11y point at once — small ≠ illegible).

## 0.6 Offline graceful degradation

The card works fully offline: **name / type / description / list-membership** come from the tile + local DB
(always offline-available). The **photo** comes from the bundled pack thumb (§6) if downloaded, else is
**omitted** offline (never a spinner-forever / broken frame). Attribution renders whenever its photo/text
renders and is absent when the component is (nothing uncredited, nothing orphaned). Every place has a
usable card offline.

---

# THE PHOTO COMPONENT (§1–§6) — image pipeline + mandatory attribution

## 1. Image-index sidecar consumption (D1)

- **Fetch parallel to the place tile.** For each viewport z10 tile the app already loads, also fetch the
  **optional** sidecar `…/{region}/{pv}/images/10/{x}/{y}.json` via **`HTTPTileFetcher`** (single-origin).
  A 404 / absent sidecar is normal → that tile simply has no photos (degrade). Same viewport-bounded
  lifecycle as tiles (the sidecar entries ride the viewport, evicted on pan — #151-consistent).
- **Decode like `RegionIndex.decode`:** strict `additionalProperties`-equivalent key handling,
  `VersionGate.schema(schema_version)` + `VersionGate.reader(min_reader_version)` (=1 today → `.ok`),
  size caps, → a `[place_id: ImageEntry]` map (`ImageEntry{thumbSHA256, bytes, width, height, attribution}`).
  A per-entry validation failure **drops that entry** (the place keeps its non-photo card), never the tile.
- **New model + `MapPlace`/`PlaceCardModel` wiring:** the card resolves its `ImageEntry` by `place_id`
  from the loaded sidecar (a new lookup on the tile client, parallel to `viewportState`). `PlaceCardModel`
  gains the image fields; the old `place.image_url` path stays retired (per #129).

## 2. Thumb fetch + content integrity (D2)

- **URL is derived, not carried:** `https://tiles.making-tracks.app/thumbs/{sha[:2]}/{sha}.webp` from
  `thumbSHA256`. Fetch via **`HTTPTileFetcher`** (single-origin, redirect-validated).
- **Verify `sha256(bytes) == thumbSHA256` [gate — the integrity check `ImageLoader` lacks].** A mismatch
  **rejects the image** (no render) — this is the content-addressed guarantee (mirror `TileCodec`'s
  `sha256`+`bytes` check). Also enforce `bytes == entry.bytes`. Then the existing **decode-bomb guard**
  (`isSafeDecodedImage`, 16 M px) before `UIImage`. Reserve layout from the index's **`width`/`height`**
  (no decode needed to size).
- **Not `ImageLoader` as-is:** `ImageLoader` is Wikimedia-allowlisted + unverified; WP-IMG-B either
  extends it (add `expectedSHA256:` + swap the allowlist to the single origin) or routes thumbs through a
  small `HTTPTileFetcher`-based loader. Recommend the latter — one trusted-origin fetch path, sha-verified.

## 3. MANDATORY attribution rendering — the compliance surface (D3)

- **Position: SMALL, at the card BOTTOM (Rob's hierarchy, §0.1) — but still non-optional.** "Small" is
  layout, not optionality: caption type, unobtrusive, below the action row — yet it renders **whenever**
  its photo/text renders and **cannot** be collapsed/hidden. Small ≠ illegible (WCAG AA, §0.5).
- **Non-optional UI, rendered WITH the image.** Whenever a photo shows, a credit block shows:
  **[creator ·] license_name (link → license_url) · "from Wikimedia Commons" (link → source_url) ·
  "modified (resized)"** — always present: license + source + modified. It **cannot be collapsed or
  hidden**; a photo without its credit must never render.
- **Creator is OPTIONAL in the render [gate — nullable creator].** For PD/CC0, `creator` is null and
  legally no author attribution is owed → **omit the creator segment** (never render "null ·" or a
  dangling separator): e.g. `CC0 1.0 · from Wikimedia Commons · modified`. For BY/BY-SA the schema
  guarantees a non-null creator, so it always shows.
- **Never-uncredited is LICENSE-SPECIFIC, not "all six present":** the app drops the photo only if a field
  **required for THAT license** is missing/malformed — **a BY/BY-SA entry with a null/empty creator is
  invalid → drop** (schema shouldn't emit it, but defend in depth); a **PD/CC0 entry with null creator is
  VALID → render** (license + source + modified). Always drop on off-pattern `license_url`/`source_url`,
  unrecognised `license_code` (outside `{PD, CC0-1.0, CC-BY 1.0–4.0, CC-BY-SA 1.0–4.0}`), or
  `modified≠true`. (Extends the existing `missingAttributionSources` decode discipline.)
- **Plain-text + validated links ONLY [gate — untrusted-data].** Render `creator`/`license_name` with
  **`Text(verbatim:)`** — never markdown/`AttributedString`/HTML (the pipeline HTML-strips, but the app
  must not re-introduce a parse). `license_url`/`source_url` are opened only after re-checking they match
  the schema's https + host patterns (creativecommons.org / commons.wikimedia.org); open in-app
  (`SFSafariViewController`) or the system browser. No other host is reachable.

## 4. Fetch policy — single origin (D4)

- **`tiles.making-tracks.app` only**, for both the image-index JSON and the thumb blob — reuse
  `HTTPTileFetcher.trustedHost`. Do **not** widen `ImageLoader`'s Wikimedia allowlist. No third-party
  fetch (the single-origin privacy story; the #129 allowlist-collapse, now concretely "reuse the tile
  fetcher's origin"). The legacy Wikimedia `allowedImageHosts` becomes unused for the photo path (leave
  or retire per the card's old `image_url` cleanup).

## 5. Memory / bounded thumb cache (D5, #151-consistent)

- **A bounded, content-addressed thumb cache** mirroring `TileCache`: key = `thumbSHA256` (immutable →
  cache-forever-until-evicted; dedup across pv/region/place), byte-capped + access-counter LRU (a
  separate budget from the 64 MiB tile cache, e.g. a smaller thumb budget — a tunable). The in-memory
  `ImageEntry` map is viewport-bounded like `loadedPlaces`. **No unbounded growth** — the sidecar entries
  evict with the viewport; only the small on-disk thumb cache persists, LRU-trimmed.

## 6. Offline — EXTEND the built pack store to bundle thumbs (D6)

- **Decision (argued): thumbs are BUNDLED in offline packs, not fetched online-while-offline.** Rationale:
  (1) **privacy** — an online thumb GET is a **per-place** signal (a sha maps 1:1 to a place's image),
  **sharper** than the coarse tile channel; bundled-in-pack thumbs are **zero-fetch**, the privacy-clean
  path (consistent with §9 "packs eliminate the channel" and the #129 §6 ruling). (2) **offline actually
  works** — a downloaded region shows photos with no network. (3) It reuses the existing content-addressed
  store cleanly.
- **Concrete extension of `OfflineRegionStore`/`Downloader` (they are BUILT):** add a **thumb object type**
  `objects/thumbs/{sha}.webp` alongside `objects/tiles/*` / `objects/basemaps/*`; the downloader fetches
  the region's **image-index sidecars + each referenced thumb** (sha-verified on install, like tiles),
  GC'd by the same unreferenced-object sweep; **storage-headroom + the `bytesWithThumbnails` estimate**
  gate the "include images" size choice (the estimate field already exists). An **"include images"
  toggle** on download (per #129) uses `bytesWithThumbnails` vs `bytesWithoutThumbnails`.
- **Online-no-pack** still fetches thumbs per-view (§2) — single-origin; the per-place signal is the
  accepted cost of online browsing, and the region §7 cover-traffic obligations apply to it (flag to the
  fetch-model WP). **Bundled is the privacy-preferred path; onboarding steers toward a pack (per §9).**

---

# THE BLURB COMPONENT (§7–§8) — Wikipedia text (separately commissionable)

## 7. Publish the Wikipedia extract as a blurb (D7 — pipeline)

- **The data exists, plaintext, ready.** Lift the captured Wikipedia `extract`
  (`source_records.props_json`, `explaintext=1`, ≤300 chars) onto the published place as `blurb` — read
  it in `_joined_places`/`tiles.py` (or a `blurb` column), SAFE_TEXT-guarded + ≤600 (`BLURB_MAX`), exactly
  like the other place strings. The app **already renders `blurb`** (`Text(verbatim:)`) — so publishing it
  is the only step to get text on cards.
- **Content-safety note:** the extract is **plaintext today** (no HTML), so SAFE_TEXT suffices. **If a
  future blurb source is HTML or LLM-generated**, the pinned blurb **content-safety screen** (A6, not
  built) must run **before** publish — SAFE_TEXT does not strip markup. Record this as a precondition on
  any non-plaintext blurb source.

## 8. CC BY-SA **text** attribution — per-place, the compliance surface (D8)

- **Source-level Wikipedia credit already ships (#157)** — a `wp:*` `source_ref` emits the manifest
  `wikipedia` / CC-BY-SA-4.0 line + bumps `min_reader_version` to 2. That is the **floor**, not the bar.
- **CC BY-SA text reuse needs PER-PLACE attribution [gate — licensing, argue-don't-diverge].** Crediting
  "Wikipedia content" generally does not attribute the **specific** article the blurb came from. The
  rigorous bar (WMF ToU / BY-SA): a **link to the source article** (which carries author history) + the
  CC BY-SA notice, shown **with the text**. So Phase 2 must **publish per-place Wikipedia provenance** —
  the `wikipedia_title` field **AND the source LANGUAGE** → the app renders **"From Wikipedia: <title>"**
  linking to `https://<lang>.wikipedia.org/wiki/<title>` beneath the blurb, plus the versioned linked
  license.
- **[gate — the article link needs a published LANGUAGE].** The extractor is **multi-language**
  (`extractors/wikipedia.py` gates on `props['lang']`; region-config allows up to 16 languages), but
  `place.schema` carries only `wikipedia_title` — **no language**. A hardcoded `en.wikipedia.org` link
  would 404 / mis-attribute a `ms`/other-language blurb, defeating the per-place BY-SA link. **WP-BLURB-P
  must publish a `wikipedia_lang`** (a new nullable place field, from `props['lang']`); the app builds the
  URL from it. **Until `wikipedia_lang` is published, render NO article link** (fall back to the
  source-level manifest credit) — never a wrong-language link.
- **[gate — the text license must be VERSIONED + LINKED, matching §3].** Render **"CC BY-SA 4.0"** (the
  pinned Wikipedia version, `a1d_sources.json`) linking to `https://creativecommons.org/licenses/by-sa/4.0/`
  — not a bare unversioned "CC BY-SA". BY-SA requires identifying the license by URI; this matches the
  image path's mandated license link (§3). Plain-text + validated link only.
- **Share-alike-for-text [flag — confirm, don't assume].** A ≤300-char factual intro may be de-minimis,
  but the safe posture (matching the image ND/BY-SA rigor) is: **attribute per-place + note CC BY-SA**;
  whether our blurb *text* must itself be *offered* under BY-SA (as image thumbnails are) is a licensing
  call I **flag for Rob/fable**, recommending the conservative "attribute + BY-SA-noted, link to article"
  and **not** claiming the text is relicensed unless required. (This is the text analog of the image SA
  discharge; surfaced, not decided in a plan.)
- **App:** render the blurb (exists) + a **Wikipedia attribution line** (article link + CC BY-SA), plain-
  text/link only, same discipline as §3. Small addition to the card.

---

## Build-WP decomposition

| WP | side | scope | depends on |
|---|---|---|---|
| **WP-CARD** card layout/hierarchy | **app (`ios`)** | the §0 overhaul: typographic hierarchy (name/type/**description/photo**/list-membership/action-row/small-attribution — Rob's order); **type row** (#166 icon+label); **list-membership chips** (read `list_items`, **exclude the system Save list**; empty until B5); **a11y** (Dynamic Type reflow, VoiceOver, WCAG AA — #163); **offline degradation** (photo omitted, rest present). Container hosting the photo/blurb/action components | B4 card (built); WP-ICONS (type icon); #167 action row |
| **WP-IMG-B1** photos online | **app (`ios`)** | image-index sidecar fetch+decode (reuse `HTTPTileFetcher`, `VersionGate`); thumb URL + **sha256 verify** + decode-bomb + width/height; `PlaceCardModel` image fields; **mandatory attribution UI** (small-at-bottom, plain-text, validated links, drop-if-invalid); bounded thumb cache | #158 (shipped); WP-CARD |
| **WP-IMG-B2** offline thumbs | **app (`ios`)** | extend `OfflineRegionStore`/`Downloader`: `objects/thumbs/{sha}.webp` + image-index in the pack, sha-verify + GC + headroom; **"include images"** size toggle (`bytesWithThumbnails`) | WP-IMG-B1; the built pack store |
| **WP-BLURB-P** publish blurb + provenance | **pipeline (`develop`)** | lift Wikipedia `extract` → `blurb`; publish `wikipedia_title` **+ `wikipedia_lang`** (from `props['lang']`, for the article URL); SAFE_TEXT + cap; content-safety precondition for non-plaintext sources | pipeline (built); #157 attribution (shipped) |
| **WP-BLURB-B** blurb attribution UI | **app (`ios`)** | render the per-place Wikipedia credit — article link `https://<lang>.wikipedia.org/wiki/<title>` (only if `wikipedia_lang` present) + **"CC BY-SA 4.0" linked to the deed** — with the existing blurb render | WP-BLURB-P (incl. `wikipedia_lang`) |

## Open flags (fable/Rob)

1. **BY-SA-for-text share-alike (§8)** — must our blurb *text* be *offered* under BY-SA, or is per-place
   attribution + CC BY-SA notice + article link sufficient? Licensing call; recommend the latter.
2. **Thumb cache budget (§5)** — a separate small byte budget vs folding into the 64 MiB tile cache (a tunable).

## Gate & acceptance

- **Gate 1 — photo/blurb pipeline (done): 4 critics + verify, 12 raised, 6 survived, all folded.** Licensing
  was sharpest — my "all six attribution fields always present" was **wrong**: `creator` is **nullable** for
  PD/CC0 (would have dropped legit public-domain photos + rendered "null ·") → creator-optional render +
  license-specific drop rule (§3); the Wikipedia article link needs a published **`wikipedia_lang`**
  (multi-language extractor, else wrong/404) → added to WP-BLURB-P (§8); the text license must be
  **versioned + linked** ("CC BY-SA 4.0" + deed), matching the image discipline (§8).
- **Gate 2 — §0 card layout (done): 3 critics + verify, 9 raised, 3 survived, all folded.**
  - **Save IS list-membership** — Save writes the "Want to go" system list and `saved` derives from
    membership in *any* list, so the chips would double-display "Saved" and inherit a latent unsave bug
    when B5 adds a second list → chips **exclude the system Save list** (empty until B5) + a pre-condition
    to narrow the `saved` derivation to "in Want to go" before B5 (§0.4).
  - **Hierarchy order** — I'd silently put photo before description; restored to Rob's order (§0.1) with a
    note that photo-first would be a Rob-gated deviation.
  - **"Advance to next"** implied a nonexistent card deck → corrected to "the card closes" (§0.3).
  The photo/blurb architecture + the card hierarchy survived; folds were compliance precision + the
  Save/membership reconciliation.
- PR → `develop`, `sourcery-review` only, report `p2p/fable__opus`. No self-merge; fable reviews; `main`
  is Rob's.
