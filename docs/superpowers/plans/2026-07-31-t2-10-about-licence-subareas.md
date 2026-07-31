# T2.10 About Licence Subareas Implementation Plan

> **For Codex:** Use the executing-plans workflow task by task. Preserve
> RED/GREEN order, use only the `codex3` simulator seat through
> `scripts/sim-lock.sh`, and stop if preserving the licence inventory would
> require changing licence content.

**Goal:** Rebuild About to the Rob-approved W-2 hierarchy while preserving
every software and data licence entry, build metadata, privacy promise, and
OSM link behavior.

**Architecture:** Keep About in its existing `MapScreen.swift` ownership
region and introduce one small value-model seam, `AboutLicenceInventory`,
which is consumed by the UI and exposes the exact software and data entries
for compliance tests. The About root remains inside the door's existing
`MaterialSheet`/`NavigationStack`; two DS-1 navigation rows push focused
Software licences and Data licences scroll destinations without system
`List` chrome.

**Tech stack:** Swift 6, SwiftUI, DesignSystem, XCTest/XCUITest, XcodeGen.

**Approved design:** Rob's 2026-07-31 W-2 ruling, rendered in
`docs/design/design-system/w2-about.png` and `w2-about-ax.png` at pinned
digests `543a6b57…` and `c8d5f412…`.

## Global constraints

- The opening hierarchy is eyebrow, About title/subtitle, “The map is fresh
  snow.” story, then “Private by construction” and the exact saved-activity
  sentence from `OnboardingCopy.savedActivityPrivacy`.
- Software licences and Data licences are separate tap-through DS-1
  destination rows in one raised card, with W-2's exact titles and summaries.
- Software renders all four entries loaded through
  `OSSCreditsManifest.load()`, in manifest order, including every full
  acknowledgement, category/version, HTTPS licence action, and verbatim
  notice text. The pinned names are GRDB.swift, MapLibre Native iOS /
  maplibre-gl-native-distribution, Newsreader, and Noto Sans glyph PBF mirror.
- Data renders the fixed OpenStreetMap contributor text and copyright HTTPS
  action, followed by every handed-in `Attribution`, in input order, with
  source, licence, and text verbatim.
- Version and build commit remain on About. Existing identifiers for version,
  build, privacy, OSM, manifest data entries, and OSS entries remain valid.
- Use Snow material tokens, Typography roles, `MaterialRaisedCardRow`, and
  `MaterialHairlineRow`; do not introduce a system `List`.
- Default and AX layouts must scroll, wrap, preserve 44pt destination targets,
  and expose each row's title, summary value, and navigation action without
  relying on colour or motion.
- T2.9 owns the Settings region of `MapScreen.swift`; do not edit it.

## Task 1: Pin the compliance inventory before restructuring the UI

**Files:**

- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`

### Step 1: Add the inventory RED tests

Add focused tests that construct `AboutLicenceInventory` from the production
manifest and sentinel data attributions. Assert:

- the software count is exactly four and the names exactly match the four
  pinned manifest names in order;
- each inventory software entry keeps its acknowledgement, category/version,
  HTTPS licence URL, and full notice text from the loader;
- the data count is the handed-in attribution count plus the fixed OSM entry;
- the data names are `OpenStreetMap` followed by all sentinel source names in
  order, and each licence/text field is unchanged;
- the OSM entry owns the existing copyright URL and contributor sentence.

Run under the assigned seat:

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=AC60FA71-9449-4F15-A259-5E4A3E832839' \
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=AC60FA71-9449-4F15-A259-5E4A3E832839' \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksTests/AppShellTests/testAboutLicenceInventoryPreservesEverySoftwareEntry \
  -only-testing:MakingTracksTests/AppShellTests/testAboutLicenceInventoryPreservesOSMAndEveryDataEntry
```

Expected RED: compilation fails because `AboutLicenceInventory` does not yet
exist. Confirm that is the only intended failure.

### Step 2: Implement the minimal inventory seam

In the existing About ownership region, add:

- `AboutLicenceInventory`, initialized from software credits and attribution;
- a fixed OSM `AboutDataLicenceEntry` carrying the existing contributor text,
  title, and copyright URL;
- projected data entries that retain `Attribution` source/licence/text exactly.

Make `AboutView` construct this inventory from
`OSSCreditsManifest.load()?.credits ?? []` and its handed-in attribution. Do
not change rendering yet beyond consuming the inventory in the old sections.

### Step 3: Prove the inventory GREEN

Run the same focused app-test command. Temporarily replace one projected
software notice with an empty string and run the first test to prove it turns
red; restore it and rerun green.

### Step 4: Commit the compliance seam

Run `git diff --check`, stage only the two owned files, and commit:

```text
Pin About licence inventory
```

## Task 2: Rebuild About and both licence destinations test-first

**Files:**

- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`

### Step 1: Re-point the existing UI tests for RED

Update `testDoorInventoriesAboutCreditsAndMapAttributionIsInert` and
`testCreditsStayGroupedAtAccessibilityTextSize` rather than deleting them.
Before production changes, require:

- About root story/privacy copy and the exact W-2 subtitle;
- `about.software-licences` and `about.data-licences` buttons with the exact
  summary accessibility values;
- navigation into Software licences, where all four manifest names and a
  licence action remain reachable;
- navigation back and into Data licences, where the OSM action and handed-in
  attribution remain reachable;
- version/build metadata on the About root;
- no “Open source acknowledgements” flat heading on the root;
- reachable, non-overlapping 44pt navigation targets at default and AX.

Run only those two UI tests through `sim-lock.sh`. Expected RED: the two new
destination identifiers do not exist.

### Step 2: Implement the W-2 root

Replace the flat About scroll content with:

- W-2 eyebrow/title/subtitle;
- a raised story card;
- a raised privacy card with a decorative lock, exact promise copy, and the
  existing privacy link;
- a LICENCES label and one raised group containing two hairline navigation
  rows using the exact W-2 titles and summaries;
- the existing version and build values at the bottom.

Use the existing parent NavigationStack. Give each destination row a combined
title/value/action accessibility representation and a 44pt minimum target.

### Step 3: Implement the focused destinations

Add `SoftwareLicencesView` and `DataLicencesView`, both Snow-token ScrollViews:

- Software iterates `inventory.software` without filtering and reuses the
  existing OSS credit presentation and identifiers.
- Data iterates `inventory.data`, retaining the existing OSM link identifier
  and manifest credit identifiers.
- Both use raised/hairline material rows and verbatim text; neither uses
  `List` or truncates notices.

### Step 4: Prove focused UI GREEN

Run both focused UI tests. Confirm the default test visits both destinations
and the AX test scrolls to every software/data endpoint with no overlap. Then
run the focused AppShellTests from Task 1 again.

### Step 5: Commit the W-2 implementation

Run `git diff --check`, stage the two owned files, and commit:

```text
Rebuild About licence subareas
```

## Task 3: Export and inspect the six required implementation renders

**Files:**

- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Create: `docs/design/design-system/t2.10-about.png`
- Create: `docs/design/design-system/t2.10-software-licences.png`
- Create: `docs/design/design-system/t2.10-data-licences.png`
- Create: `docs/design/design-system/t2.10-about-ax.png`
- Create: `docs/design/design-system/t2.10-software-licences-ax.png`
- Create: `docs/design/design-system/t2.10-data-licences-ax.png`
- Modify: `docs/design/design-system/README.md`

### Step 1: Add deterministic screenshot exports

Add six names to `screenshotExportNames`. Have the two re-pointed UI tests
attach/export the root and both destinations at their respective default/AX
sizes. Capture a destination only after its title and representative final
entry are reachable; scroll back to a useful full-surface composition before
capturing when necessary.

### Step 2: Export through the simulator lock

Run both UI tests with
`MAKING_TRACKS_EXPORT_UI_TEST_SCREENSHOTS=1`, the literal codex3 destination,
parallel testing disabled, and every simulator interaction wrapped by
`scripts/sim-lock.sh`. Copy the six non-empty PNGs from
`/private/tmp/making-tracks-artifacts/` to the tracked paths above.

### Step 3: Inspect original-resolution evidence

Inspect all six PNGs. Verify Snow surfaces, ruled hierarchy, no clipping or
overlap, readable story/privacy hierarchy, distinct licence destinations,
Newsreader and Noto Sans visibility, OSM/data visibility, and AX wrapping.
Record the six assets as T2.10 implementation evidence in the design README.

### Step 4: Commit evidence

Run `git diff --check`, stage only the six renders, UI-test export map, and
README row, then commit:

```text
Add T2.10 About implementation evidence
```

## Task 4: Verify, review, and publish the exact tree

### Step 1: Re-ground before the expensive gate

Fetch `origin/ios`. If it advanced, merge it without rewriting history,
resolve only the T2.10 region, and rerun the two focused app/UI tests.

### Step 2: Run complete verification

Run `swift test` from `ios` and restore any resolver-only Package.resolved
change. Then export the codex3 destination and run exactly:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Record exact host, app, and UI counts plus duration from the successful
post-merge tree.

### Step 3: Push and run adversarial review

Push the exact verified head. Dispatch independent reviewers for spec/content
fidelity, UI/accessibility/test quality, and architecture/security/coherence.
Fix every load-bearing finding test-first, rerun affected checks, repush, and
repeat review against the new exact head. Record raised/fixed/survived counts.

### Step 4: Open the PR and obtain clearance

Open a draft PR to `ios`, name issue #472 and T2.10, link all six renders,
include exact counts, W-2 ruling provenance, adversarial accounting, and a
`## Taste guesses` section stating there are none beyond Rob's approved W-2
frames. Apply `sourcery-review`, `track-b-ios`, and `wp` only. Update T2.10's
ledger status and AMQ at each allowed checkpoint. Request the assigned
reviewer's exact-head/tree clearance and do not self-merge.
