# WP-B4 — Place Card + Core Loop (`MakingTracksCore`)

Date: 2026-07-16
Thread: `wp/b4` · Issue: #15 · Depends on: **B1** (`MakingTracksData`, merged), **B3**
(`MakingTracksTiles`, merged #121), **B2** (`MakingTracksMapStyle`, plan-only — B4 wires
against its `onTapPlace` contract). Design ratified by fable on `wp/b4` (Q1–Q5); hardened
after a 3-critic gate (feasibility **built** it on Swift 6.3.3 + ran the 6-cell matrix
host-only; security + spec-fidelity lenses). The gate's fixes are folded below and marked
**[gate]**.

## Goal

The product's core loop, and the screen it happens on. **See a pin → tap → place card →
save / mark visited (+ optional loved) → pin state updates → the map fades what's visited.**
One tap in the card, no ceremony, fully reversible (P3). Plus the two obligations pinned
upstream: **render the legal `manifest.attribution`** (the app-render half of B3's Q2) and
**re-pin the image host allowlist at fetch, including redirects**. The loop and the card
view-model are **pure and host-testable** — the star seam; SwiftUI + map wiring is the thin
`[XCODE/SIM]` shell (simulator available this round per AGENTS.md #118 — build it, isolate it).

## Controlling context (verified against `origin/develop`; feasibility-critic-confirmed)

**B1 `MakingTracksData` (merged).** `PlaceRef` (`Models/PlaceRef.swift:6`, throwing init).
`PinState{saved:Bool, visit:VisitState}`, `VisitState=.none/.visited/.loved` — two orthogonal
axes, 6 cells. `Verdict={loved}` only. `Interactions.swift`: `recordVisit(_:verdict:)`
**appends** a visit event (`snapshotIfNeeded` fires — P8 free), `deleteVisit(id:)`,
`addToList(_:listID:)` (idempotent). `Derivations.viewportState(_ ids:) -> [String:PinState]`
(`:48`, off-main) is the re-fade query; it derives `loved` as **`MAX(verdict='loved')` over
ALL a place's visits** and `visited` via **`EXISTS` over all visits** — a fact that forces the
loop's edit primitives to be **per-place, not per-visit-id** (see decision 1).

**B3 `MakingTracksTiles` (merged #121).** `TileClient` actor: `placeRef(for:) async ->
PlaceRef?` (`:1002`; `nil` if not in currently-loaded tiles → fallback), `isPresentInCurrentTiles`
(`:998`), `attribution:[Attribution]` (`:1006`, required-to-display), `loadState`.
`Attribution{source,license,text}` (`:70`, control/bidi-bounded at decode). Image host allowlist
(`upload/commons.wikimedia.org`) enforced at decode (bad host nulled); **B4 re-pins at fetch
incl. redirects**. B3's `isSafeText`/`allowedPlaceKeys`/strict decode are the **shared guard
B4 reuses** (see decision 2) — not re-implemented (SAFE_TEXT parity was pinned once already,
`595ad33`).

**B2 `MakingTracksMapStyle` (plan-only, not built).** `MapPlace{id,lat,lon,tier}` exists in
`MakingTracksData`. Tap contract (B2 plan): the map calls **`onTapPlace(place_id: String)`** —
B4 gets a place_id string. Fade is B2's render of `PinState` (`opacity = visit==.none ? 1.0 :
0.35`; bookmark badge = `saved`; heart = `.loved`). **B4 writes state + signals; B2 renders**
— B4 never draws the fade. B4 wires against `onTapPlace` with a stub until B2 is built.

**Spec.** §3.1 seen = ≥1 visit, event-log (`visits(id,place_id,visited_at,verdict)`),
un-mark = delete event, re-visits appended. §3.2 two **orthogonal** axes ("orthogonal, not a
state machine"). §3.3 verdict nullable `loved`, **editable/removable later from the card or
Tracks**. §3.4 one tap in the card (two physical from the map), no confirmation, reversible,
**no geolocation auto-mark**, nearby prompts foreground-only v1. §5.5 plain-text only,
https+expected-host images. §6 absent from tiles → render from `place_snapshots`. §7: one UI
test of the loop + snapshot tests of the full 6-cell pin matrix.

**Principles:** P1 fading = progress; P3 one tap, reversible, nothing destroyed; P4 seen is a
global fact; P5 nothing silent (no geolocation auto-mark); P8 first-interaction snapshot.

## Ratified design decisions (fable, `wp/b4`) — with gate refinements

1. **Additive, PER-PLACE B1 primitives (Q1 — expanded from 3 to 5 by the gate; flagged to
   fable).** The loop operates on `place_id`, but B1's APIs are visit-id/list-id keyed and the
   pin derivation is MAX/EXISTS **over all** a place's visits — so the primitives must be
   per-place, and two more are required than Q1's original three. Add to `MakingTracksData`
   (extend-never-break; existing suites untouched except additions; each a `swift test`):
   - `snapshot(for placeID:) -> PlaceSnapshot?` — the §6 fallback read *(ratified)*.
   - `removeFromList(placeID:listID:)` — un-save *(ratified)*.
   - `setLoved(placeID:, _ loved: Bool)` — per-place verdict edit *(ratified, redefined
     per-place)*: `true` marks the latest visit `loved`; **`false` clears `loved` across ALL
     the place's visits** (else the MAX-over-all derivation keeps the heart and un-love is a
     no-op — **[gate]** reversibility/P3).
   - `deleteVisits(placeID:)` — place-keyed delete-all for the **un-visit** toggle *(NEW —
     **[gate]**)*: a stateless card controller has no visit-id, and the pin returns to `.none`
     only when all the place's visits are gone. `deleteVisit(id:)` alone can't do it.
   - `wantToGoListID() -> Int64` (or `systemList()`) — the seeded "Want to go" list id
     *(NEW — **[gate]**)*: `addToList` needs a `listID` and B1 exposes no list accessor today,
     so the Save action has nothing to save into without this.
   - `PlaceSnapshot: Equatable` — additive conformance *(NEW — **[gate]**, so a `CardSource`
     enum wrapping it synthesizes `Equatable`)*.
2. **B4-owned §5.5 card decoder over `rawJSON` (Q2) — hardened.** One decoder for **both**
   sources — `PlaceRef.rawJSON` (tile) and `PlaceSnapshot.snapshotJSON` (fallback). It
   **reuses B3's shared `isSafeText`/`allowedPlaceKeys`/strict typed-decode guard set — no
   re-implementation [gate]** — and, on **both** paths (the snapshot path never saw B3):
   - **re-applies the SAFE_TEXT scalar filter** to every string field (strip/reject
     control/bidi/zero-width; `Text` alone does NOT neutralize a U+202E in an old/tampered
     snapshot — **[gate]**);
   - caps input bytes **before** parse on the snapshot path (`PlaceRef.maxRawJSONBytes`
     guards only the tile path — **[gate]**);
   - **re-pins the image host** (https + `{upload,commons}.wikimedia.org`) → `imageURL?` else
     `nil`;
   - derives per-place source names **only from pattern-valid `source_refs`** — validate each
     ref against `^[a-z][a-z0-9_]*:…` **before** splitting on `:`, map the prefix through a
     **fixed allowlist dict** (`osm→OpenStreetMap`, `historic_england→Historic England`,
     `open_plaques→Open Plaques`, `wd/wp→Wikidata/Wikipedia`), **drop unknown/malformed**
     (never render a raw prefix — a `Historic England:1` ref must not spoof a source name —
     **[gate]**).
   No B3 change.
3. **`AsyncStream<Set<String>>` reactivity seam (Q3).** After any card action the loop
   controller emits the **changed place_ids**; `MapScreen` observes and re-runs `viewportState`
   for just those pins (off-main); B2 re-renders the fade. B4 defines the contract; B2 consumes
   it uncoupled. (Feasibility-confirmed sound under Swift-6 strict concurrency: a
   `final class: Sendable` controller with a `Sendable` continuation.)
4. **Attribution — legal render, ON the map chrome, one tap max (Q4 + RIDER, NON-NEGOTIABLE).**
   `manifest.attribution` (from `TileClient.attribution`) is per-publish/region-wide and legally
   must be shown. The entry affordance is the **standard attribution "ⓘ"/label on the persistent
   map chrome — ONE tap to the full Credits surface**, rendering the ODbL/OGL/PDDL `text`
   **verbatim via `Text(verbatim:)`** (the license text is untrusted per P10 and `isSafeText`
   permits markdown `[ ]( )`, so a compromised license string must not become a tappable link —
   **[gate]**). Not in settings, not buried (ODbL "reasonably calculated to make aware"). The
   card separately shows lightweight **informational per-place source names** (decision 2).
   *Hard acceptance criterion on the shell task.*
5. **Three orthogonal one-tap reversible toggles (Q5) — over the per-place primitives.** The
   card offers, **no confirmations** (P3): **[Save]** (`addToList(wantToGoListID())` /
   `removeFromList` — bookmark badge, independent of visit), **[Visited]** (`recordVisit` /
   `deleteVisits(placeID:)` — drives fade), and when visited a **[♥ Loved]** toggle
   (`setLoved(placeID:,·)`). Each is reversible and emits its `place_id`. "One tap" = one tap
   in the card. No geolocation auto-mark (P5).

## Package architecture

New pure SwiftPM package **`MakingTracksCore`** (iOS 18 / macOS 14, Swift 6 language mode, no
UI deps — `swift test`, no simulator), depending on `MakingTracksData` + `MakingTracksTiles`.

- **`PlaceCardModel`** — the §5.5 card decoder (decision 2): `rawJSON` (either source) +
  `PinState` → plain-text `name/category/blurb/alt_names`, host-re-pinned `imageURL?`, allowlisted
  source names; SAFE_TEXT-filtered, byte-capped, skip-not-crash.
- **`PlaceResolver`** — `place_id → CardSource`: `TileClient.placeRef(for:)`; on `nil`, B1
  `snapshot(for:)`; on both-absent, `.unavailable`. Behind injected protocols (`TileResolving`,
  `SnapshotReading`); the real `TileClient` actor conforms directly (async), `AppDatabase`
  conforms — host-testable both paths. **On the snapshot path it reconstructs a `PlaceRef`**
  (throwing init) from the `PlaceSnapshot` fields, because `addToList`/`recordVisit` require one.
- **`CoreLoopController`** — the three toggles (decision 5) over the per-place primitives → B1
  writes → emits the changed place_id on `AsyncStream<Set<String>>`. Holds no view state.
- **`AttributionModel`** — `[Attribution]` → verbatim Credits list + the per-place source-name
  lookup.
- **`ImageLoader`** — fetches place/attribution images through a **dedicated `URLSession` whose
  task delegate re-pins the Wikimedia allowlist on `willPerformHTTPRedirection`** (or disallows
  redirects), feeding a plain `Image` — **NOT `AsyncImage`**, which follows 30x redirects
  through `URLSession.shared` and would let a Wikimedia URL 302 to an attacker host (an IP/UA
  beacon on card open — §9 "unable to track"). **[gate]** Mirrors B3's `RedirectDelegate`,
  pinning image hosts.
- The **app target** owns: `PlaceCardView` (SwiftUI, `Text(verbatim:)` for every source-derived
  field — never `LocalizedStringKey`/literal interpolation [gate]), the `onTapPlace` wiring, the
  **map-chrome attribution ⓘ → `CreditsView` (`Text(verbatim:)`)**, and `MapScreen`'s observation
  of the reactivity stream. `[XCODE/SIM]`, isolated.

## Tasks

1. **B1 additive per-place primitives (decision 1).** `snapshot(for:)`, `removeFromList`,
   `setLoved(placeID:,·)` (true→latest, false→all), `deleteVisits(placeID:)`, `wantToGoListID()`,
   `PlaceSnapshot: Equatable`. Host tests each; **B1's existing suite stays green untouched**;
   a drift-guard that additions don't alter existing behavior. Teeth: love then **un-love clears
   the heart even with an older loved visit present** (the MAX-over-all case); un-visit returns
   the pin to `.none` (all visits gone); un-save removes list membership.
2. **`PlaceCardModel` — the hardened §5.5 decoder (decision 2).** Reuse B3's shared guard set;
   SAFE_TEXT filter + byte cap + image-host re-pin + `source_refs` pattern-before-prefix +
   allowlist-drop-unknown; skip-not-crash. **Every adversarial vector runs specifically through
   the SNAPSHOT path** (the path that never saw B3): teeth for a `U+202E` name, a non-Wikimedia
   `image_url`, a markdown/`%@` blurb, a `Historic England:1` / colon-less `source_ref`, an
   over-cap `snapshotJSON` — each yields an inert/dropped field, card still shown.
3. **`ImageLoader` — redirect-pinned fetch (decision 2/[gate]).** Dedicated session + redirect
   delegate re-pinning the Wikimedia allowlist; plain `Image`. Teeth: a Wikimedia URL that
   302s to a non-Wikimedia host yields **no request to that host** (assert via a recording stub);
   an initial non-allowlisted host is refused.
4. **`PlaceResolver` + `CoreLoopController` + reactivity (decisions 3, 5, §6).** Resolver:
   present→tile, absent→snapshot (reconstruct `PlaceRef`), both-absent→`.unavailable` (graceful).
   Controller: three toggles → per-place B1 writes → emit changed ids on `AsyncStream`. Host
   tests on in-memory `AppDatabase`: **the full 6-cell STATE matrix** (saved∈{0,1} ×
   visit∈{none,visited,loved}) asserted via `viewportState` after each transition — the §7
   matrix, host-run, no simulator. *(The **visual** render-matrix — `PinState`→fade opacity +
   bookmark/heart badges, §3.2's precedence — is **B2's** snapshot test, deferred; B4 owns the
   state half.)* Every toggle reversible + emits its id.
5. **`AttributionModel` + Credits data (decision 4).** `[Attribution]` → verbatim Credits list +
   source-name lookup. Host-tested (the live UK manifest's 3 attributions render verbatim;
   source_refs→names via the allowlist).
6. **`[XCODE/SIM]` shell (isolated).** `PlaceCardView` (`Text(verbatim:)`, `ImageLoader` not
   `AsyncImage`), `onTapPlace`→card, the **map-chrome attribution ⓘ → `CreditsView` reachable in
   ONE tap (hard acceptance criterion, decision 4)**, `MapScreen` observing the reactivity
   stream. Wire against B2's `onTapPlace` with a stub until B2 is built. The §7 **core-loop UI
   test** (find → save → mark seen → appears in Tracks) runs here under the #118 simulator
   runbook — with an explicit stub map standing in for "find" (B2 unbuilt), a DB/query assertion
   standing in for "appears in Tracks" (Tracks is **B6**, unbuilt), and the **map fade left
   unverified in B4** (it is B2's render). Under the #118 designated-sim + `flock` discipline.

## Compliance & non-goals

- **P3/P5/P1:** one tap in card, no confirmations, fully reversible, no geolocation auto-write
  (the resolver is read-only; every write is a user toggle; `snapshotIfNeeded` fires only inside
  a user-initiated write — merely opening a card writes nothing); the card's copy frames fading
  as progress (a design/copy-review item, not a coded test). **P8** free via B1's write path.
- **§5.5 / P10:** plain `Text(verbatim:)` only; SAFE_TEXT re-applied on both paths; image fetched
  only over https from the re-pinned Wikimedia host, redirects pinned; our own snapshot treated
  as untrusted. **§6:** absent→snapshot; both-absent→graceful `.unavailable`, never blank-crash.
- **Legal:** `manifest.attribution` verbatim, reachable in **one tap from the map chrome** — a
  hard acceptance criterion.
- **Non-goals (seams left):** map render + pin styling + fade + basemap (**B2**, plan-only — B4
  stubs the tap/fade seam and does the state matrix; B2 owns the visual matrix); **Lists** screen
  (**B5**); **Tracks** screen (**B6**); onboarding (**B10**); "report a problem" (**C2**, needs
  B4 shipped); search (**B9**). B4 builds none of these.

## Gates & acceptance

- **Adversarial gate (done for this plan; repeat for the impl PR):** ≥ 3 critics — (a)
  **feasibility that BUILDS `MakingTracksCore` on Swift 6.3.3** + runs the 6-cell state matrix
  against in-memory `AppDatabase`; (b) security / untrusted-data (image redirect-pin, SAFE_TEXT
  on both paths, `Text(verbatim:)`, source_refs pattern-before-prefix — neuter each, test reds);
  (c) spec-fidelity + coherence (§3.2 orthogonality intact; per-place reversibility; B1
  extend-never-break; the one-tap attribution). Cross-examine; report raised/survived/fixed.
- **Teeth:** every §5.5 vector run **through the snapshot path**; un-love clears with an older
  loved visit; un-visit → `.none`; a redirecting image host blocked; the 6 cells enumerated;
  the B1 additions don't red B1's suite.
- **Acceptance:** `MakingTracksCore` builds + all `swift test` pass on Swift 6.3.3; the 6-cell
  state matrix passes host-only; the `[XCODE/SIM]` core-loop UI test passes under #118;
  **Credits reachable in one tap from the map chrome**.
- PR → `develop`, label **`sourcery-review`** only (per the greptile-spend policy). Report on
  `wp/b4`. No self-merge; fable's independent review; `main` is Rob's.
