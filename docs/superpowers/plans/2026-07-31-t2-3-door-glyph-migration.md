# T2.3 Door-Glyph Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the #520 door-row glyph and Explore quiet-destination glyph to their ratified semantic icon roles, remove only the retired quiet-destination geometry member, and close Phase 1 acceptance at 35/35 with device evidence.

**Architecture:** Pass `.rowRaised` or `.rowQuiet` from each owning door-row wrapper through `MapDoorRowLabel` to the shared glyph. Extract the Explore destination's leading glyph, adopt `.rowQuiet`, and pin medium weight locally so T2.3 preserves the ruled no-pulse behavior. Point-of-use app tests protect both paths; simulator renders and the full release gate protect the visible app-target migration.

**Tech Stack:** Swift 6, SwiftUI, XCTest/XCUITest, Xcode iOS simulator gate, GitHub PR evidence.

## Global Constraints

- Authoritative base: `origin/ios` at `2105250df98b89c73aacf12450a8be0022865314`.
- T2.3 owns sites 1 and 3 only: `MapDoorRowIconGlyph` and `ExploreQuietDestinationRow`.
- Do not edit `ExploreScopeControlGlyph`, `ExploreSurfaceIconGeometry.scopeControl`, or its `.body` anchor; T2.8 owns them.
- Raised row glyphs use `.rowRaised`; quiet/hairline row glyphs use `.rowQuiet`.
- Preserve `ExploreQuietDestinationRow`'s current no-pulse medium weight and document the delegated planner ruling at the site.
- Remove only `ExploreSurfaceIconGeometry.quietDestination` after its app consumer migrates.
- Keep navigation, copy, row-title typography, accessibility identifiers, and button styles unchanged.
- Simulator destination: `platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6`; every simulator operation goes through `scripts/sim-lock.sh`.
- Full host baseline: 514 tests, 0 failures.

---

### Task 1: Capture exact-base before evidence

**Files:**
- Read: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Produce temporarily: `/private/tmp/t2-3-before-default.png`
- Produce temporarily: `/private/tmp/t2-3-before-ax.png`

**Interfaces:**
- Consumes: existing screenshot exports `explore-door-default` and `explore-door-ax`.
- Produces: immutable before images retained outside the worktree until Task 4 assembles the evidence packet.

- [ ] **Step 1: Run the two existing Explore render tests on the exact base**

Run from the repository worktree root:

```bash
MAKING_TRACKS_EXPORT_UI_TEST_SCREENSHOTS=1 \
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6' \
./scripts/sim-lock.sh xcodebuild \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6' \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testMapHomeExposesBothDoorsAndExploreOpensScopeDirectly \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testDoorsRemainTappableAtAX5InDarkAppearance \
  test
```

Expected: both tests pass and `/private/tmp/making-tracks-artifacts/explore-door-{default,ax}.png` exist.

- [ ] **Step 2: Freeze the base images and record their hashes**

```bash
cp /private/tmp/making-tracks-artifacts/explore-door-default.png /private/tmp/t2-3-before-default.png
cp /private/tmp/making-tracks-artifacts/explore-door-ax.png /private/tmp/t2-3-before-ax.png
shasum -a 256 /private/tmp/t2-3-before-default.png /private/tmp/t2-3-before-ax.png
```

Expected: two non-empty files with different SHA-256 digests.

---

### Task 2: Write point-of-use tests and observe RED

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift:1111-1312`
- Test later: `ios/App/Sources/Map/MapDoorShell.swift:674-718,1185-1255`

**Interfaces:**
- Consumes: `IconRole.rowRaised`, `IconRole.rowQuiet`, `firstDescendant(of:in:)`, and `descendants(of:in:)`.
- Produces: app-target tests that fail if either row owner passes the wrong role, the Explore row bypasses its glyph wrapper, or the wrapper bypasses `.rowQuiet`/medium weight.

- [ ] **Step 1: Add the failing shared-row point-of-use test**

Add a fixture presentation and assert through each real owner:

```swift
@MainActor
func testDoorRowOwnersWireTheirRatifiedIconRolesAtPointOfUse() throws {
    let presentation = MapDoorRowPresentation(
        title: "Settings",
        subtitle: "preferences",
        systemImage: "gearshape",
        accessibilityIdentifier: "explore.row.settings"
    )

    XCTAssertEqual(
        try XCTUnwrap(
            firstDescendant(
                of: IconRole.self,
                in: MapDoorRaisedRow(presentation: presentation, action: {}).body
            )
        ),
        .rowRaised
    )
    XCTAssertEqual(
        try XCTUnwrap(
            firstDescendant(
                of: IconRole.self,
                in: MapDoorHairlineRow(presentation: presentation, action: {}).body
            )
        ),
        .rowQuiet
    )
}
```

Production mutation caught: a row wrapper omits the role or passes the other row class.

- [ ] **Step 2: Add the failing Explore quiet-destination point-of-use test**

```swift
@MainActor
func testExploreQuietDestinationWiresRowQuietWithFixedMediumWeight() throws {
    let presentation = ExploreDoorRow.settings.presentation
    let row = ExploreQuietDestinationRow(
        presentation: presentation,
        prominent: true,
        action: {}
    )

    XCTAssertEqual(
        descendants(
            of: ExploreQuietDestinationIconGlyph.self,
            in: row.body
        ).count,
        1
    )

    let glyphBody = ExploreQuietDestinationIconGlyph(
        systemName: presentation.systemImage
    ).body
    XCTAssertEqual(
        try XCTUnwrap(firstDescendant(of: IconRole.self, in: glyphBody)),
        .rowQuiet
    )
    XCTAssertEqual(
        try XCTUnwrap(firstDescendant(of: Font.Weight.self, in: glyphBody)),
        .medium
    )
}
```

Production mutations caught: the row returns to a hand-rolled leading image, the glyph uses the wrong semantic role, or the preserve-ruling weight override disappears.

- [ ] **Step 3: Re-point the existing glyph tests to explicit roles**

Update every `MapDoorRowIconGlyph` construction to pass a role. Extend the hostile-ambient and rendered-glyph tables with both `.rowRaised` and `.rowQuiet`, and replace `RatifiedMapDoorRowIcon` with:

```swift
private struct RatifiedMapDoorRowIcon: View {
    let systemName: String
    let role: IconRole

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Image(systemName: systemName)
            .iconRole(role)
            .foregroundStyle(tokens.accent.swiftUIColor)
    }
}
```

Expected values are the literal `.rowRaised` and `.rowQuiet` contracts; no production mapping computes the expected role.

- [ ] **Step 4: Run the focused app tests and confirm RED**

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6' \
./scripts/sim-lock.sh xcodebuild \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6' \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksTests/AppShellTests/testDoorRowOwnersWireTheirRatifiedIconRolesAtPointOfUse \
  -only-testing:MakingTracksTests/AppShellTests/testExploreQuietDestinationWiresRowQuietWithFixedMediumWeight \
  test
```

Expected: compile failure because the two row wrappers are file-private, `MapDoorRowIconGlyph` has no role parameter, and `ExploreQuietDestinationIconGlyph` does not exist.

- [ ] **Step 5: Commit the RED tests**

```bash
git add ios/App/Tests/AppShellTests.swift
git commit -m "test(ios): require semantic door row icon roles"
```

---

### Task 3: Implement the two-site migration

**Files:**
- Modify: `ios/App/Sources/Map/MapDoorShell.swift:674-718,1185-1255`
- Modify: `ios/Sources/DesignSystem/Iconography.swift:53-58`
- Test: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Consumes: `View.iconRole(_:)`, `.rowRaised`, and `.rowQuiet` from T2.2.
- Produces: role-aware `MapDoorRowIconGlyph(systemName:role:)` and `ExploreQuietDestinationIconGlyph(systemName:)`; no public API.

- [ ] **Step 1: Pass the owning role through the shared door-row path**

Make the wrappers module-internal and wire their literal roles:

```swift
struct MapDoorRaisedRow: View {
    let presentation: MapDoorRowPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MaterialRaisedCardRow {
                MapDoorRowLabel(
                    presentation: presentation,
                    iconRole: .rowRaised
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

struct MapDoorHairlineRow: View {
    let presentation: MapDoorRowPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MaterialHairlineRow {
                MapDoorRowLabel(
                    presentation: presentation,
                    iconRole: .rowQuiet
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}
```

Add `let iconRole: IconRole` to `MapDoorRowLabel`, forward it, and replace the pending-ruling literal:

```swift
struct MapDoorRowIconGlyph: View {
    let systemName: String
    let role: IconRole

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Image(systemName: systemName)
            .iconRole(role)
            .foregroundStyle(tokens.accent.swiftUIColor)
    }
}
```

- [ ] **Step 2: Extract and wire the Explore destination glyph**

Make `ExploreQuietDestinationRow` module-internal, remove its `@ScaledMetric`, and replace its leading `Image` with:

```swift
ExploreQuietDestinationIconGlyph(
    systemName: presentation.systemImage
)
.foregroundStyle(
    prominent
        ? tokens.accent.swiftUIColor
        : tokens.muted.swiftUIColor
)
.frame(width: 24)
.accessibilityHidden(true)
```

Add the glyph immediately beside the row:

```swift
struct ExploreQuietDestinationIconGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .iconRole(.rowQuiet)
            // T2.3 preserve ruling: destination rows adopt rowQuiet's
            // size/anchor but do not join A5's weight-pulse family yet.
            .fontWeight(.medium)
    }
}
```

- [ ] **Step 3: Remove only the retired geometry member**

Delete `ExploreSurfaceIconGeometry.quietDestination` from `Iconography.swift`. Leave this exact surviving API unchanged:

```swift
public enum ExploreSurfaceIconGeometry {
    public static let scopeControl: CGFloat = 20
}
```

- [ ] **Step 4: Run focused app tests and confirm GREEN**

Re-run the exact focused command from Task 2 Step 4.

Expected: both tests pass. If `Font.Weight` is not reflectable as assumed, replace only that assertion with a rendered comparison against a locally medium-weight reference; do not weaken or remove the preserve-ruling check.

- [ ] **Step 5: Run all `AppShellTests`**

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6' \
./scripts/sim-lock.sh xcodebuild \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6' \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksTests/AppShellTests \
  test
```

Expected: all AppShell tests pass, including default and AX role-backed glyph rendering.

- [ ] **Step 6: Run the host package suite**

```bash
cd ios && swift test
```

Expected: at least the 514-test baseline passes. Restore only SwiftPM's known host-only `Package.resolved` MapLibre pin drift with `apply_patch`.

- [ ] **Step 7: Commit the implementation**

```bash
git add ios/App/Sources/Map/MapDoorShell.swift ios/Sources/DesignSystem/Iconography.swift
git commit -m "fix(ios): migrate door row glyphs to semantic roles"
```

---

### Task 4: Record ownership, capture after evidence, and run the full gate

**Files:**
- Modify: `docs/superpowers/phases/phase-2/tasks.md:230-260,436-455`
- Create: `docs/design/design-system/t2.3-door-glyph-before-default.png`
- Create: `docs/design/design-system/t2.3-door-glyph-before-ax.png`
- Create: `docs/design/design-system/t2.3-door-glyph-after-default.png`
- Create: `docs/design/design-system/t2.3-door-glyph-after-ax.png`
- Create: `docs/design/design-system/t2.3-door-glyph-evidence.md`
- Modify: `docs/design/design-system/README.md`

**Interfaces:**
- Consumes: Task 1 before images, existing Explore screenshot tests, exact implementation head, and codex1 simulator seat.
- Produces: reviewable default/AX before-after packet, the carried A5 question, exact gate evidence, and #520 closeout record.

- [ ] **Step 1: Correct and update the T2.3 ledger row**

Change the row to owner `codex1`, branch `wp-t2-3-door-glyph`, and current status. Replace “Three sites and one enum” with a note that the merged target-state spec supersedes it: T2.3 owns sites 1 and 3; T2.8 owns Scope/site 2. Do not edit the T2.8 row.

- [ ] **Step 2: Add the carried designer question**

Add one bullet under `## Carried — not claimable this phase`:

```markdown
- **Should quiet destination rows join A5's symbol-weight press-pulse family?** T2.3 adopts `IconRole.rowQuiet` for semantic size and Dynamic Type anchoring but deliberately pins medium weight to preserve shipped behavior. Removing that override requires a designer family ruling and default/pressed render evidence; it is not an incidental cleanup.
```

- [ ] **Step 3: Capture exact-head after screenshots**

Re-run Task 1 Step 1 on the implementation head, then copy the exported images:

```bash
cp /private/tmp/making-tracks-artifacts/explore-door-default.png /private/tmp/t2-3-after-default.png
cp /private/tmp/making-tracks-artifacts/explore-door-ax.png /private/tmp/t2-3-after-ax.png
```

- [ ] **Step 4: Create exact 390×844 evidence images**

```bash
sips -z 844 390 /private/tmp/t2-3-before-default.png --out docs/design/design-system/t2.3-door-glyph-before-default.png
sips -z 844 390 /private/tmp/t2-3-before-ax.png --out docs/design/design-system/t2.3-door-glyph-before-ax.png
sips -z 844 390 /private/tmp/t2-3-after-default.png --out docs/design/design-system/t2.3-door-glyph-after-default.png
sips -z 844 390 /private/tmp/t2-3-after-ax.png --out docs/design/design-system/t2.3-door-glyph-after-ax.png
sips -g pixelWidth -g pixelHeight docs/design/design-system/t2.3-door-glyph-*.png
```

Expected: all four files report exactly 390×844 pixels. Inspect each at original detail; confirm Settings/About remain visible and unclipped.

- [ ] **Step 5: Write the measurement record**

Create `t2.3-door-glyph-evidence.md` with:

- exact base and candidate heads;
- SHA-256 for all four images;
- before measurement: 17pt headline/medium for the shared door literal and 18pt body-anchored/medium for Explore destinations;
- after measurement: raised 20pt relative to `.headline`, quiet 18pt relative to `.subheadline`, and Explore medium weight preserved;
- a statement that the assigned seat capture is resampled from its native screenshot to the ruled 390×844 evidence canvas without cropping;
- a visual inspection result for default and AX, and the semantic-not-numeric Scope boundary.

Add the packet to `docs/design/design-system/README.md`.

- [ ] **Step 6: Run the mandatory full release gate**

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6' \
  ./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: Release build, host tests, app tests, and UI tests all pass. Record exact suite counts and duration from the gate output. Do not classify a red as infrastructure unless all ledger conditions are met.

- [ ] **Step 7: Final mutation and scope checks**

Verify mentally and with the focused suite that these mutations fail: raised/hairline role swap, Explore role removal, Explore glyph-wrapper bypass, and medium override removal. Run:

```bash
rg -n 'quietDestination|MapDoorRowIconGlyph|ExploreQuietDestinationIconGlyph|ExploreScopeControlGlyph|scopeControl' ios
git diff --check
git diff --stat origin/ios...HEAD
git status --short
```

Expected: no `quietDestination`; Scope source unchanged; no unintentional lockfile drift.

- [ ] **Step 8: Commit evidence and ledger**

```bash
git add docs/superpowers/phases/phase-2/tasks.md docs/design/design-system
git commit -m "docs(ios): record T2.3 door glyph evidence"
```

---

### Task 5: Publish and request exact-head review

**Files:**
- Read: complete branch diff.
- External: draft PR into `ios`.

**Interfaces:**
- Consumes: green exact head, committed evidence packet, reviewer tier, and issue #520.
- Produces: draft PR labelled `track-b-ios`, `wp`, and `sourcery-review`, plus exact-head AMQ review request.

- [ ] **Step 1: Rebase onto freshly fetched `origin/ios` before publication**

```bash
git fetch origin ios
git rebase origin/ios
```

If the rebase changes the source head, rerun the focused app tests and full release gate before publishing.

- [ ] **Step 2: Push and open the draft PR**

```bash
git push -u origin wp-t2-3-door-glyph
gh pr create --draft --base ios --head wp-t2-3-door-glyph --title "T2.3: migrate door row glyphs to semantic roles" --body-file /private/tmp/t2-3-pr-body.md
```

The PR body must state:

- merged spec note wins over the stale three-site phrase; sites 1 and 3 changed, Scope/site 2 untouched for T2.8;
- row-role mapping and the preserve/no-pulse ruling;
- RED–GREEN and full-gate counts;
- before/after default/AX evidence paths and measurements;
- Phase 1 acceptance completes at 35/35 and `Closes #520`.

- [ ] **Step 3: Apply and verify labels**

```bash
gh pr edit --add-label track-b-ios --add-label wp --add-label sourcery-review
gh pr view --json headRefOid,isDraft,baseRefName,labels,statusCheckRollup,url
```

- [ ] **Step 4: Request reviewer clearance over AMQ**

Send the exact full SHA, PR URL, test/gate counts, render hashes, role mapping, preserve ruling, carried question, and explicit no-Scope diff to `reviewer`. Notify `planner` that T2.8 may rebase only after T2.3 merges.

- [ ] **Step 5: Merge only after all required gates and exact-head reviewer clearance**

Do not mark ready or merge on stale approval. After merge, verify the merge SHA, close #520 through the PR, and notify planner that T2.8 is unblocked.
