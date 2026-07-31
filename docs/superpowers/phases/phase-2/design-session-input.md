# Phase 2 design-session packet — the World door

**Status:** input for the Phase 2 opening design session (phase-cycle spec §2.1). Phase 2 is **DS-3
(#469) + DS-6 (#472)** per epic #466's phased work-list, and it opens with this session, not with
builders. Rob relays the designer; rulings are explicit words — silence is never a ruling. Nothing
below is claimable until the session rules scope.

Every item cites the artifact that carries its full text. This packet assembles; it does not
restate ratified words — where a ruling is quoted, the source section is canonical.

## What the session decides

1. The carried **component-metrics batch** (five items, one of them the agenda question).
2. **DS-3's inherited questions** — persistence, identifiers, the relocated R16 proof, and the
   routed derivation-reach question.
3. The **mockup gates**: DS-3's detailed picker wireframe (drawn to R10) and DS-6's Settings +
   About wireframes are produced or commissioned in-session (§2.1).

## 1 — The component-metrics batch

Canonical text: `docs/superpowers/phases/phase-1/tasks.md` § *The component-metrics table's batch*.

- **Item 1 — A9's press inset becomes a scaled metric.** Already ruled by Rob (verbatim in the
  source). The session's act is the table entry; the migration is one line because
  `IconRoleModifier` already anchors `@ScaledMetric` to a paired role. The shipped `1pt` literal is
  a recorded way-station.
- **Items 2+3 — the agenda question, met as one decision.** Two ratified figures press `IconRole`'s
  closed set from opposite directions: `ia-doors`' 20px raised / 18px quiet row glyphs from below
  (shipping as a `17pt` literal declared non-compliant — `MapDoorRowIconGlyph`, #529), and
  `coherence`'s 17-beside-15 pairing constant from above. The carried question: **was three the
  right closure at all?** Ruling this also disposes **#520** — Phase 1's parked 34/35 remainder
  becomes an ordinary migration row the moment it is ruled.
- **Item 4 — the snapped 21.** Worked example only; no decision requested. It is the case that
  argues for the table's existence.
- **Item 5 — Open Flag 5, and it gates Phase 2 directly.** A8's Explore Scope-row metrics are
  **MEASURED, not ratified** (spec component-metrics table, the two rows marked as such: 52pt rows
  at default, 86pt at AX, with their full geometry). DS-3's picker builds on exactly these rows,
  and the shipped A10 row cites them as measured. Wholesale ratification or amendment here removes
  the largest open provenance gap under the new surface before it is drawn.

## 2 — DS-3's inherited questions

- **Scope-set persistence.** Tree fact: today only coverage shading survives relaunch
  (`MapScreen.swift:2580`, UserDefaults-backed); include-hidden (default OFF), show-saved (default
  ON) and the category selection all reset per launch. DS-3 rebuilds the surface these controls
  mount on, so this is the moment to rule which of the user's scope choices persist across
  launches — and the answer is a designer call about intent, not a plumbing default.
- **Identifier convention.** A1's convention governs the relocated rows
  (`docs/superpowers/phases/phase-1/amendment-wave.md` § A10 → *Ownership boundary*): today's
  `map.layers.show-hidden` belongs to a sheet DS-3 dismantles. The wireframe should name the
  A1-convention identifiers for the relocated Scope rows so the contract rename happens once, in
  one commit, with nothing in flight against it.
- **The relocated R16 filled-beside-cluster proof.** Per the A8 record (amendment-wave § A8): no
  Phase 1 surface pairs a filled action with a state cluster, so **the first DS-3 or DS-6 render
  that does must carry the proof as its own acceptance evidence**. The session's wireframes decide
  which surface pairs them first. If neither Phase 2 surface does, the proof relocates again — and
  the wireframe record must say so explicitly rather than letting the obligation lapse in silence.
- **The routed derivation-reach question (open, unruled).** A10 built the saved-visibility filter
  for map pins only and routed the rest: *whether the saved filter reaches beyond map pins into
  track and list derivations is a designer question* (amendment-wave § A10 → *The asymmetry
  question*). Merged code filters discovery map pins; `Derivations.swift` is untouched. DS-3
  re-mounts these controls, so the session is the natural place for the ruling. Hidden's behaviour
  is not a template — it does not have one rule, and `lovedPlaces()`'s non-filtering is pinned by
  test as deliberate.

## 3 — Other carried designer calls

Canonical text: phase-1 `tasks.md` § *Carried to the next design session*.

- **The one-shot spec §3 amendment, with its two riders**: the *trail* rename happens inside the
  amendment (code and sheet in one commit), and `hiddenPinColor #767B82` joins the constant pin
  block, exempt from the pin-pop gate. The session can commission it.
- **R9's quiet-geometry remedy.** Quiet controls have no boundary to move, so their enabled press
  feedback fell to effectively nothing. The remedy, if perceptible feedback is wanted there, is
  another geometry — an inset, a brief symbol-weight shift — and never restored opacity. R9's
  scope, therefore the designer's call.

## 4 — Wireframe-gate notes

- **DS-3 draws to R10 as ruled**, rider included: tiling only for reversible, immediately-legible
  actions; destructive/navigational/commitment-bearing controls keep full 44pt without exception.
  The worked ~30pt arithmetic is illustrative at an assumed 8pt gap — **derive the number at the
  gap the drawn surface actually has**; the only ratified chip container is `gap:6px`,
  non-wrapping, and the wrapped multi-row flow is DS-3's design. The grouped-edit state is the
  sanctioned fallback if the render feels mis-tappy — not pre-emptively.
- **DS-6's ruled facts**: Offline maps + Coverage move into Settings (set-and-forget, per Rob);
  About rebuilds with Software licences and Data licences as proper sub-areas; the map keeps
  contextual deep links into Offline maps. All on DS-1 rows/sheets, no system List chrome.
- **Evidence law applies as boot-doc law** (`docs/process/coordination.md` § Evidence and review
  law): renders carry their measurements beside the image; the full constraint structure is
  enumerated before any figure is adopted; a general bound states its qualifier; a clearance states
  its scope.
