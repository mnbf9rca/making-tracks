# T2.3 Door-Glyph Migration Design

## Context and authority

T2.3 closes #520 by replacing the last declared non-compliant Phase 1 row-glyph font literal with the ratified icon vocabulary. The implementation starts from `ios` head `2105250df98b89c73aacf12450a8be0022865314`, after T2.2 added `IconRole.rowRaised` and `IconRole.rowQuiet`.

The merged target-state note in `docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md` is authoritative over the older “three sites” wording in the T2.3 builder brief. T2.3 owns sites 1 and 3 only:

1. `MapDoorRowIconGlyph`, with the role supplied by its raised or quiet row owner.
2. `ExploreQuietDestinationRow`, migrated from `ExploreSurfaceIconGeometry.quietDestination` to `IconRole.rowQuiet`.

`ExploreScopeControlGlyph` and `ExploreSurfaceIconGeometry.scopeControl` remain untouched for T2.8. Numeric equality between `scopeControl` and `rowRaised` does not make them the same semantic figure.

## Considered approaches

### 1. Semantic roles with preserved quiet weight behavior — chosen

Pass `IconRole.rowRaised` or `.rowQuiet` from the owning row into the shared door-row label and glyph. Extract the Explore destination's leading icon into a small glyph view using `.iconRole(.rowQuiet)`, then explicitly pin `.fontWeight(.medium)` at that site. The override and an adjacent ruling comment preserve the pre-existing no-pulse behavior while adopting the ratified size and Dynamic Type anchor.

This is the smallest design that closes #520, expresses both row identities, and satisfies the planner's delegated behavior ruling.

### 2. Enrol the quiet destination in A5's weight pulse — rejected

Using the environment-driven role weight without an override would allow a surrounding quiet material control to promote the glyph from medium to semibold while pressed. That may be desirable, but whether destination rows belong to A5's pulse family is an unresolved designer question. T2.3 must not answer it accidentally.

### 3. Keep the hand-rolled size and anchor — invalid

Retaining `.font(.headline.weight(.medium))` or the `@ScaledMetric(relativeTo: .body)` migration constant preserves current mechanics but fails the ruled vocabulary migration. It cannot close #520 or AC2.4.

## Source design

### Shared door-row glyph

`MapDoorRowIconGlyph` gains an `IconRole` input and applies `.iconRole(role)` instead of the literal headline font. `MapDoorRowLabel` accepts the same role and forwards it to the glyph. `MapDoorRaisedRow` supplies `.rowRaised`; `MapDoorHairlineRow` supplies `.rowQuiet`.

The two row wrappers become module-internal rather than file-private so the app test target can inspect their actual bodies. This is a testability-only visibility change inside the app module; it does not create a public API.

The pending-ruling/non-compliance source comment is deleted because the vocabulary now carries the ratified figures.

### Explore quiet destination

The leading destination icon moves into a module-internal `ExploreQuietDestinationIconGlyph`. It applies `.iconRole(.rowQuiet)` and then the explicit medium-weight override required by the planner's preserve ruling. A short code comment names the deliberate divergence: T2.3 adopts the semantic size and anchor but does not decide whether destination rows join A5's press-pulse family.

`ExploreQuietDestinationRow` uses the new glyph and drops its body-anchored `@ScaledMetric`. Once that app consumer compiles through `rowQuiet`, `ExploreSurfaceIconGeometry.quietDestination` is removed. `scopeControl` and its consumer do not change.

## Point-of-use coverage

Tests must fail when a consumer bypasses the new vocabulary; definition-only `IconRole` tests are insufficient.

- Render and structurally inspect both `MapDoorRaisedRow` and `MapDoorHairlineRow`, asserting that their body trees carry `.rowRaised` and `.rowQuiet` respectively through the real label/glyph path.
- Assert that `ExploreQuietDestinationRow` owns one `ExploreQuietDestinationIconGlyph`, and that the glyph body carries `.rowQuiet` plus the explicit medium-weight override.
- Re-point the existing hostile-ambient and rendered-glyph tests from the old literal reference view to role-backed expectations at default and Accessibility 5 Dynamic Type.
- Keep the existing Scope-control code and contract untouched; diff inspection and the app/full gate protect the hand-off to T2.8.

The new tests follow RED–GREEN: first reference the required role parameters and extracted Explore glyph so compilation fails on the old implementation; then add the minimum production wiring.

## Visual and gate evidence

This is a visible migration. Evidence includes before/after 390×844 simulator renders at default Dynamic Type and an Accessibility Dynamic Type variant, with measured glyph dimensions beside the images. The before evidence is captured from the exact base; after evidence is captured from the exact candidate head using the codex1 simulator seat.

The final gate is:

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6' \
  ./scripts/sim-lock.sh ./scripts/release-gate.sh
```

The PR records the exact test counts, gate result, render paths and measurements. It states that the merged spec note narrows T2.3 to sites 1 and 3, that Phase 1 acceptance reaches 35/35 on the `MapDoorRowIconGlyph` migration, and that the PR closes #520.

## Carried designer question

The Phase 2 ledger gains one Carried bullet: should quiet destination rows participate in A5's symbol-weight press pulse? T2.3 deliberately preserves medium weight while adopting `rowQuiet`; a later design session may remove that override only with an explicit family ruling and render evidence.

## Failure handling and scope limits

There is no runtime failure path or new data flow. Build failures are expected if the enum member is removed before its app consumer migrates, so removal happens only after point-of-use tests and source wiring are green. T2.3 does not change row titles, button styles, Scope geometry, Scope anchoring, navigation, accessibility identifiers, or the place-card press-inset obligation in #575.
