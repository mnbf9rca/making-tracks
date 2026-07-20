# WP-B6 build — retrace rebuild and the #266 unification

Build spec for the ratified Retrace design. Serves #17, #257 and #266.

**Design authority:** `2026-07-18-wp-b6-tracks.md` §1a (continuity, filter re-indexing, autoplay) and §1b (the four
render-derived amendments). **Visual authority:** `docs/design/retrace/`, ratified by Rob and merged in #295.
This document does not re-decide any of that. It says what to build, in what order, and what proves it.

Grounded against `ios` @ `1569659`. Every file:line below was read on that tree.

---

## 0. What is already right — do not rebuild it

Five PRs shipped since the design was written and a rebuild that ignores them will regress working behaviour.
These are correct and load-bearing; leave them alone except where a slice below says otherwise.

- **Autoplay is already event-paced.** `startMapTrackAutoplay` (`MapScreen.swift:2277-2295`) steps
  `autoplayStep(after:)` → `index + 1` and sleeps a fixed `0.85 s` beat. It is not a rate animation. The trap in
  §1a is already avoided and there is a comment at `:732` saying so. **Do not "improve" this into a slider
  animation.**
- **Arrival is already appearance-plus-pulse.** `TrackReplayPinPresentation` regrades unreached pins to `.none`
  (`MapScreen.swift:665-706`) and `PinLayers.trackReplayPulseExpression` scales `1.28` on the arriving pin
  (`PinLayers.swift:75-100`). That is §1b amendment 3, already built. No colour-pop exists to remove.
- **Arcs are real Béziers and the maths is sound.** `FeatureEncoding.trackArcCoordinates`
  (`FeatureEncoding.swift:179-219`) works in cos(lat)-scaled space with exact endpoints and antimeridian
  handling (#270). Curvature consistency is tested (`PinLayersTests.swift:478`).
- **Continuity is real.** `trackSegmentSummary` connects every consecutive valid pair and
  `suppressedBurstConnectorCount` is hardcoded `0` (`FeatureEncoding.swift:145`). §1a is honoured in code.
- **Same-day reordering is shipped and guarded.** `reorderVisitsWithinDay` (`Interactions.swift:239-261`)
  validates the ID set before writing `visit_order`.

---

## 1. Slice 1 — the unification (#266). Do this first.

Everything else has to land somewhere, and right now there are two somewheres.

### What is actually duplicated

The recon found the duplication is worse than #266 describes. It is not two surfaces — it is **two surfaces
and three scrubbers.**

| | `menu > Tracks` (#248) | `Lists > My tracks` (#263) |
| --- | --- | --- |
| Entry | `AppMenuRootView` row `MapScreen.swift:3687-3693` → `MenuDestination.tracks` | row `:3679-3685` → `ListsView` → `ListDetailView` → "Show on map" `:4361` |
| View | `TracksView` `MapScreen.swift:3745-4170` | no dedicated type; `ActiveListMap` `:3069-3078`, `usesTrackReplay` |
| Replay | **its own** `startAutoplay` `:4029-4047`, slider `:3910-3924` — highlights rows, no map | `startMapTrackAutoplay` `:2277-2295`, slider `:2229-2237` — drives map geometry |
| Filter | `TracksVisitFilter` `:6417-6425`, loved-only, **UI-side** | none |
| Editing | verdict `:4091`, date `:4103`, reorder `:4115`, delete `:4129` | none |

`TracksView` owns the editing; the list route owns the map. Neither is a superset, which is why this has to be
a fold rather than a deletion.

### Build

1. **`menu > Tracks` routes to the `My tracks` list detail surface.** Keep the menu row — it is the
   discoverable entry and #17 wants it — but `MenuDestination.tracks` resolves to the same destination the
   Lists route reaches. One screen, reached two ways.
2. **Fold `TracksView`'s editing into the track-mode list detail**: verdict, date, reorder, delete, operating on
   **visit-event rows**. The row model must stay visit events, not deduplicated places — a place visited three
   times is three rows in a chronology and one row in a place list, and collapsing them destroys the feature.
   The system-list write guard (`canRemoveStoredMembership` `:6411-6415`) blocks *membership* changes; it must
   not block verdict edits. There is already a test asserting the guard
   (`AppShellTests.swift:689`) — add the converse.
3. **Delete `TracksView` and its private replay copy** (`:4029-4071`, `:3898-3930`). Not deprecate. A second
   scrubber that highlights rows while the real one drives the map is how the two drift.
4. **`TracksVisitFilter` moves into the derivation** — see slice 2. It cannot stay a UI-side filter.

### Teeth

- A UI test drives `menu > Tracks` and `menu > Lists > My tracks` and asserts they reach the **same** screen
  identity, not two instances. Neutering the route fold must red it.
- Verdict edit from a visit row succeeds while a membership write on the same list still throws. Both
  assertions in one test, or the guard can be loosened to make the first pass.
- Existing `MakingTracksCoreLoopUITests.swift:357` covers surface A and `:411` covers surface B. When A dies,
  `:357` must be rewritten against the unified surface, **not deleted** — it is the only coverage of the
  chronology rows.

---

## 2. Slice 2 — filtering re-indexes the timeline, and the bridge readout dies

### The defect

Rob ruled that filtering produces a **shorter track that is itself continuous** (§1a). The code does the
opposite twice over.

**a. The loved filter is applied in the UI, after the timeline is built.** `TracksVisitFilter.visibleVisits`
(`MapScreen.swift:6417-6425`) filters rows; `TrackTimelineModel` and the map snapshot are built from the
unfiltered `trackVisits()`. So the counter, the markers, the autoplay steps and the arcs all still run over the
whole log while the list shows a subset. That is precisely the "track with holes" the ruling rejects.

**b. `filteredBridgeCount` is the retired readout, shipped.** `TrackGeometryContext`
(`Derivations.swift:27-32`) computes the count of visits dropped between rendered ones, and
`AppShellTests.swift:156` asserts a user-facing string explaining it —
`testTrackConnectionReadoutExplainsFilteredBridges`. **#287 retired this.** Under re-indexing there is no gap
to report.

### Build

1. Move loved-filtering into `trackGeometryContext` (`Derivations.swift:135-183`) alongside the existing
   hidden-place and list-scope filtering, so **one filtered ordered set** feeds rows, timeline and geometry.
2. `TrackTimelineModel`, the slider range, date markers, `autoplayStep` and `TrackReplaySnapshotCache` all
   build from that set. The counter reads *within* the filter: `Visit 4 of 11` where 11 is the filtered total.
3. **Delete `filteredBridgeCount`, its readout, and `AppShellTests.swift:156`.** Delete
   `DerivationsTests.swift:269` (`testFilteredTrackBridgeCountIncludesListScopeAndHiddenOmissions`) with it.
4. **Hidden places keep bridging silently.** Unchanged: no marker, no count, ever. `Derivations.swift:153,175`
   stays exactly as it is. Keep the code comment at the derivation point saying the omission is deliberate —
   without it someone reads the silent bridge as a bug.

### The distinction, because deleting one and keeping the other looks arbitrary

**Filtering is a scope the user chose and can see; hiding is a removal the user chose not to see.** A
"3 places hidden by your filters" readout describes an absence relative to a track the user is not looking at.
A hidden-place count re-exposes exactly what hiding removed.

### Teeth

- Filter to a subset and assert the slider's upper bound, the date-marker positions, the autoplay step count
  **and** the arc count all move to the filtered set. Neutering the derivation change must red it — a test that
  only checks the row list passes the broken version.
- Hide a place between two visible ones and assert one connector spans them, with no count anywhere in the
  rendered output.

---

## 3. Slice 3 — dotted, bold, and one source for the styling

### The trap in this slice, stated first

`TrackLayers.swift` is a **declarative style spec in `JSONValue` form** with no MapLibre dependency. The live
layer is built separately and imperatively in `addTrackLine(style:)`
(`MLNMapViewRepresentable.swift:990-1006`). **The styling constants are therefore applied twice through two
code paths.**

`PinLayersTests.swift:138` (`testTrackLayerUsesSeparateDashedLineSourceBelowPins`) tests the JSON form. That is
the same shape as the `PinLayers.pinLayers()` mirror trap already recorded in
`docs/process/gate-lessons.md` §5: **a change to the dash pattern can go green in the host tests while the
shipped map still draws the old line.** Every reviewer of this slice must check the imperative path by eye.

### Build

1. **Single-source the constants.** `TrackLayers` stays the only place the numbers live;
   `addTrackLine(style:)` reads them rather than restating them. Only genuinely cosmetic MapLibre-only
   properties may differ, and that split must be stated in a comment.
2. **Dotted, not dashed** (§1b amendment 1). Today: `lineDashPatternValues = [1.6, 1.2]`
   (`TrackLayers.swift:10`). A dot is a zero-length dash with a round cap — set `lineCap = .round` and a dash
   pattern whose "on" length is ~0, with the gap carrying the rhythm. **`lineDashPattern` in MapLibre is in
   units of line width**, so the gap value must be recomputed when the width changes below, not carried over.
3. **Bold and clear** (§1b amendment 2). Today: `lineWidth = 3.0`, `lineOpacity = 0.82`
   (`TrackLayers.swift:8-9`). The ratified render is dots at ~6.2/9 dash units, opacity ~0.76 on a 390pt
   canvas. Those are **starting points, not ordained values** — §257 requires width, opacity, gap and bend
   ratio be visible tunables, not silent magic numbers. Tune against the render, not against the SVG's
   arithmetic.
4. **Read the qualification correctly.** Commitment 6 ("points dominate, line recedes") is a **hierarchy
   statement, not an opacity budget** (§1b). The pins must remain the subject; the path must still be
   confidently traceable. If tuning makes the line disappear at map zoom, it has gone the wrong way —
   subordinate is not the same as faint.
5. Contrast against the paper background is already tested (`PinLayersTests.swift:155`) — re-run it against the
   new values rather than adjusting the threshold.

### Teeth

- **Assert the imperative path, not only the JSON.** A test that reads `TrackLayers.lineDashPatternValues` and a
  test that inspects the constructed `MLNLineStyleLayer` are different tests. At minimum, a host test that both
  paths derive from the same constant, plus a reviewer confirming `addTrackLine` by eye.
- **This slice changes what the app renders, so it runs the full release gate** — `gate-lessons.md` §5. Host
  tests cannot prove the rendered output changed, because they never render anything.

---

## 4. Slice 4 — motion. Where the real gap is.

Three behaviours look identical in a still frame and differ only in motion, which is why they are specced
together and must be reviewed together. §1b carries them as one block.

### a. Scrub must animate. It currently teleports.

`setSelectedTrackReplayEventIndex` (`MapScreen.swift:2303-2320`) swaps in a **precomputed** snapshot from
`TrackReplaySnapshotCache` (`:708-725`). The geometry appears instantly at the new index. Rob:

> "Fast or slow, paths still draw and pins still animate. Just that you may be doing a LOT or a few at a time."

So a scrub across eight visits must draw eight arcs and pulse eight pins — quickly, batched, but drawn. **An
implementation that sets state directly at the scrub target is wrong however correct the still frame looks.**

The precomputed cache is a good optimisation and should survive; what is missing is that a jump from index *i*
to index *j* plays the intervening states rather than skipping to *j*. Batch size scales with scrub velocity;
the per-step visual does not change.

### b. Velocity-sensitive zoom does not exist.

Not built at all. Coarse movement covers many events; slowing expands the local cluster for precise selection
without changing event order. **Zoom changes events per pixel — never a time window.** Adjacent visits stay
equally spaced whether they are minutes or months apart, at every zoom level. Date labels decimate by
available width.

### c. Autoplay stays as it is.

Already correct (§0). It advances the event index. It must never become a constant-rate slider animation.

### Teeth — one block, because they fail the same way

1. Autoplay advances the **event index** — never animates the slider at a constant rate.
2. Zoom expands **event spacing** — never a time window.
3. Scrub animates through every reached arc and pin — **never teleports state**, at any speed.

For (3): assert that a multi-index jump produces intermediate rendered states, not one. A test that checks only
the final state passes the teleporting implementation — that is the whole trap.

For (2): a fixture with one pair minutes apart and one pair months apart must show equal spacing at both zoom
levels. A test that only asserts "zoom changed something" is ranking-blind.

---

## 5. Slice 5 — remove the dead parameters

§1a struck gap-threshold and burst-suppression, and the ratification is now in the tree. The API surface still
carries them as inert:

- `TrackLayers.defaultMaxConnectorGap` (`:13`) and `defaultBurstWindow` (`:15`), both commented as retained but
  unused.
- `FeatureEncoding.swift:135` — `_ = maxConnectorGap`, a parameter explicitly discarded.
- `suppressedBurstConnectorCount` hardcoded `0` (`:145`).

Delete them. A dead parameter that reads as a tuning knob is an invitation to re-derive a decision Rob has
already made — and `_ = maxConnectorGap` is a live signature that a future maintainer will reasonably assume is
wired.

Keep `connectorGap` itself (`FeatureEncoding.swift:239-242`). It is not gap suppression: it gates negative
deltas and emits `gap_seconds`. **Note the interaction** — it returns `nil` on a negative gap, and same-day
reordering can produce one, which would silently drop a connector from a track the design says is continuous.
Fix that as part of this slice: ordering is `visit_order`-first (`Derivations.swift:243-251`), so the pair
validity test must follow the sort, not the timestamp.

`PinLayersTests.swift:615` (`testTrackSegmentSummaryDoesNotSuppressBurstConnectors`) stays. It is the guard
that stops suppression coming back.

---

## 6. Build order

1. Unification (#266) — everything else needs one place to land.
2. Filter re-indexing + bridge-readout removal.
3. Dead parameters + the negative-gap fix. Small, and it clears the ground.
4. Line character. Ships a visible change; runs the full gate.
5. Motion. Largest and least constrained by existing code.

Slices 2 and 3 are independent and can run in parallel after 1.

---

## 7. Open, and deliberately not decided here

- Autoplay beat is `0.85 s` (`MapScreen.swift:733`). Ruled uniform, not ruled *how fast*. Tunable.
- Scrub velocity thresholds and batch sizes. No ruling exists; pick defaults, expose them as tunables, and
  bring the numbers to Rob with a render rather than asking in prose.
- `MapScreen.swift` is over 7000 lines and the replay UI is inline `@ViewBuilder` methods inside it. Extraction
  is justified but it is **not in this spec's scope** — folding two surfaces into one while also moving them
  into new files makes the diff unreviewable. Propose it separately once slice 1 has landed.
