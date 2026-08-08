# Visit Edit Context Design

Issues: #435 and folded fidelity defect #641

Status: semantic ruling approved by planner; rendered design packet awaits independent validation and Rob's taste ruling before implementation

## Purpose

The Visit date editor should show the operator the other recorded visits to the same place, so the day they are correcting makes sense against that history. The context is informative only: the focused editor still edits one visit event and never implies that hidden rows can be reordered or mutated from this screen.

This amendment also restores two ratified #221 elements that drifted from the live SwiftUI view: the `After save` consequence block and the fixed Cancel/Save footer. These changes affect the same authored hierarchy and land as one coherent surface repair.

## Current tree and tracker drift

The design is grounded on `origin/ios` `de7f0d91220008b0f37aa2f130b63e2b46f8e98f`.

`TrackVisitDateEditorView` currently receives one `TrackVisit` and renders the summary, `SELECTED VISIT`, the compact date picker, delete, and save/cancel actions. It does not load or show any other visit. The live view also omits the frozen mockups' `After save` block; #641 records that fidelity defect. On the grounded baseline, `ios/App/Sources/Map/MapScreen.swift:6126-6138` places Cancel/Save inside the `ScrollView`, while every frozen #221 Visit date variant fixes that bar to the bottom. The planner ruled this footer mismatch folded into #435 as ratified-design drift, not as a new taste decision.

#454 landed as `f106d7afef8c12931139f7b06f4b034ed02ee873`. It added the shared `VisitDateEditPolicy`, clamps legacy future selections, limits the picker to the end of today, and rejects future days at the database boundary. It changed no authored resting copy or hierarchy. Its issue-only mockup exception therefore does not cover this amendment, while its date validity behavior remains binding.

## Options and ruling

### A. Other visits to the same place — adopted

Show the selected place's other visit events, excluding the selected `visits.id`, newest first. These rows answer the direct editing question: what else is recorded here?

### B. Other visits on the pending day — rejected

The content would change as the unsaved picker selection changes and visually imply same-day reorder semantics. That would front-run unresolved #361 and make a read-only focused screen look like it owns a complete day sequence.

### C. Prior edits to this visit — rejected

The product stores visit events, not an audit log. Adding a schema and migration for an unstated need is disproportionate.

## Ruled behavior

### Identity, membership, and order

- The selected event remains identified by `visits.id`.
- Context membership is exact `place_id` equality with the selected event.
- The selected event is excluded by `visits.id`, not by date or place deduplication.
- Every other event remains distinct, including two visits recorded at the same instant.
- Context rows are ordered newest first by the existing stable visit chronology reversed; ties retain the existing visit identity tie-break.
- Loved is not rendered on context rows because current loved semantics are place-level, not evidence about a particular historical event.

### Presentation and interaction

The existing summary and selected-visit card remain the editing focus. Immediately below them, an `OTHER VISITS HERE` section lists every other event for the place. Each row shows only the recorded local date and time with a quiet history glyph. Rows have no chevron, button trait, swipe action, drag handle, heart, or tap behavior.

When no other visit exists, the section is omitted. The absence of history does not need an empty-state card on a focused correction form.

The restored `AFTER SAVE` block follows the history section. Its copy states that changing the day appends the visit to the target local day's order and that ordering is managed from the full My tracks list. It does not promise an exact time or focused-screen reorder.

The authored content remains vertically scrollable above a fixed Cancel/Save footer. The default render shows the normal entry state. The accessibility render shows the same screen after the user has scrolled the summary out of view, proving that the selected item, context rows, `After save`, and fixed actions remain usable at large text sizes.

The reproducible packet is:

- `docs/design/visit-edit-context/visit-edit-context-default.png` — 390×844 default text
- `docs/design/visit-edit-context/visit-edit-context-ax.png` — 390×844 accessibility text, scrolled context state
- paired HTML, shared CSS, render script, hashes, and measurement notes in the same directory

### Data flow

The editor uses the existing asynchronous, snapshot-backed `TrackVisit` derivation. It loads the current all-visits result off the main actor through `MapScreenModel`, then a pure context projection filters by `placeID`, excludes the selected `id`, and reverses the stable chronology for newest-first display. No schema, migration, write API, or network access is added.

Context loading is observational. A load failure or missing model produces no context section and does not disable date editing. Save and delete retain their existing success/error paths and dismiss behavior.

### #454 invariants retained

- `VisitDateEditPolicy` remains the single picker range/clamp policy.
- Today and earlier remain selectable; tomorrow and later remain unavailable and rejected at storage.
- The selected visit's original time-of-day remains preserved when its day changes.
- Context rows reflect persisted visits and do not change when the pending picker day changes.

## Testing design

- A pure projection test pins same-place membership, selected-ID exclusion, newest-first order, stable ties, and separation of two events sharing a timestamp.
- View tests pin conditional section omission, the read-only accessibility contract, the two other-visit rows, restored `After save` copy, and unchanged picker maximum wiring.
- A UI test opens a repeated-place fixture at default and accessibility text sizes and proves the selected card, context header/rows, after-save block, and actions are reachable without exposing reorder or row-edit controls.
- Mutation evidence separately removes the place filter, selected-ID exclusion, reverse ordering, read-only trait, after-save block, and picker maximum; each mutation must turn a named test red.

## Scope boundaries

- No edit-audit schema or migration.
- No same-day neighbor view or #361 reorder semantics.
- No editing, deleting, loving, or opening an alternate visit from a context row.
- No changes to My tracks row layout, track replay, place snapshots, visit writes, or #454 validation.
- No new empty state, pagination, count cap, or network behavior.

## Approval gates

The HTML/PNG packet is authored by the builder, independently validated against this design, then routed through planner to Rob for taste ruling. Swift implementation starts only after that ruling. The eventual app-target PR must carry the ruled renders and preserve their content hashes.
