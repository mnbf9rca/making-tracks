# Invalid Region-Index Publish Version Fail-Closed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `OfflineRegionCatalog` drop and diagnose a directly constructed region-index entry whose search path does not exactly match its entry ID and publish-version contract instead of crashing the app.

**Architecture:** Keep strict network decoding unchanged and harden the next trust boundary: catalog projection. Convert only the catalog's entry projection from `map` to `compactMap`; retain an entry only for `<entry.id>/[0-9]{8}T[0-9]{6}Z/search/compact.json`, otherwise write one privacy-scoped diagnostic record and return `nil`, while valid sibling entries continue to produce zones and download rows. Define known row IDs from zones actually reachable from `rootZones`, so local state for a valid child orphaned by a dropped parent is surfaced as unavailable cleanup data.

**Tech Stack:** Swift 6, SwiftUI app target, OSLog-backed Making Tracks diagnostic file sink, XCTest, iOS 18+

## Global Constraints

- Branch from a freshly fetched `origin/ios`; never modify the shared `ios` checkout.
- Preserve PR #318's stale/unknown-current, cache fallback, and installed-pack behavior.
- Do not change `RegionIndex.decode(_:)`, UI copy, layout, or download state rules.
- Preserve cleanup visibility for installed, paused, and quarantined state whose retained
  zone cannot be reached from `rootZones`.
- Treat region-index content as hostile upstream data under `docs/PRINCIPLES.md` Data 10 and the approved design §5.5.
- Record a dropped zone through the existing `MakingTracksLog.file` sink: region ID as an object field and the fixed reason as public.
- Run every app-target build or test through `scripts/sim-lock.sh`; host `swift test` takes no simulator lock.
- Reuse `/private/tmp/dd-codex1` for all focused `xcodebuild` runs and leave no `.xcresult` bundles.
- The final `origin/ios` baseline is `8bfdc5e9`; require the 385-test host suite to be green.
- Signing and SSH have recovered. Create the normal signed commit, push, and PR after the required gates; fable owns that delivery.

---

### Task 1: Pin malformed-entry drop and diagnostic behavior

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Include: `docs/superpowers/specs/2026-07-24-invalid-region-index-fail-closed-design.md`
- Include: `docs/superpowers/plans/2026-07-24-invalid-region-index-fail-closed.md`

**Interfaces:**
- Consumes: `RegionIndex`, `RegionIndex.Entry`, `RegionIndex.SearchCompact`, `OfflineRegionCatalog.init(regionIndex:)`, `DiagnosticLogStore`, `MakingTracksLog.configureDiagnosticLogStore(_:)`.
- Produces: unchanged `OfflineRegionCatalog.init(regionIndex:)`; invalid entries are omitted and produce `downloads error region catalog entry dropped` with `region` and `reason` fields.

- [ ] **Step 1: Expose the package's internal memberwise constructors to the app test target**

Change the existing import in `ios/App/Tests/AppShellTests.swift`:

```swift
@testable import MakingTracksTiles
```

Keep the existing `@testable import MakingTracks` line unchanged.

- [ ] **Step 2: Add a direct-construction fixture**

Add this helper beside `appRegionIndexV3Object()`:

```swift
private func appConstructedRegionIndexWithMalformedSearchCompactPath() -> RegionIndex {
    let validSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei/20260719T125813Z/search/compact.json",
        sha256: String(repeating: "a", count: 64),
        bytes: 208,
        schemaVersion: 1
    )
    let malformedSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei_kl/search/compact.json",
        sha256: String(repeating: "b", count: 64),
        bytes: 197,
        schemaVersion: 1
    )
    let wrongPathIDSearchCompact = RegionIndex.SearchCompact(
        path: "wrong-region/20260719T125813Z/search/compact.json",
        sha256: String(repeating: "c", count: 64),
        bytes: 196,
        schemaVersion: 1
    )
    let invalidVersionSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei_invalid-version/not-a-publish-version/search/compact.json",
        sha256: String(repeating: "d", count: 64),
        bytes: 195,
        schemaVersion: 1
    )
    let trailingExtraSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei_trailing-extra/20260719T125813Z/search/compact.json/extra",
        sha256: String(repeating: "e", count: 64),
        bytes: 194,
        schemaVersion: 1
    )
    let nondigitVersionSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei_nondigit-version/2026071XT125813Z/search/compact.json",
        sha256: String(repeating: "f", count: 64),
        bytes: 193,
        schemaVersion: 1
    )
    return RegionIndex(
        schemaVersion: 3,
        minReaderVersion: 1,
        generatedAt: "2026-07-20T12:00:00Z",
        regions: [
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei",
                displayName: "Malaysia, Singapore, and Brunei",
                parent: nil,
                bbox: BBox(minLon: 99.0, minLat: -1.5, maxLon: 120.0, maxLat: 7.5),
                publishVersion: "20260719T125813Z",
                searchCompact: validSearchCompact,
                basemapBytes: 4_000_000,
                tileCount: 12,
                bytesWithoutThumbnails: 228_849_472,
                bytesWithThumbnails: 240_582_030
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_kl",
                displayName: "Kuala Lumpur",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 101.4, minLat: 2.8, maxLon: 101.9, maxLat: 3.4),
                publishVersion: "20260719T125813Z",
                searchCompact: malformedSearchCompact,
                basemapBytes: 1_000_000,
                tileCount: 4,
                bytesWithoutThumbnails: 33_000_000,
                bytesWithThumbnails: 41_000_000
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_wrong-path-id",
                displayName: "Wrong Path ID",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 101.0, minLat: 2.0, maxLon: 102.0, maxLat: 3.0),
                publishVersion: "20260719T125813Z",
                searchCompact: wrongPathIDSearchCompact,
                basemapBytes: 900_000,
                tileCount: 3,
                bytesWithoutThumbnails: 32_000_000,
                bytesWithThumbnails: 40_000_000
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_invalid-version",
                displayName: "Invalid Version",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 102.0, minLat: 3.0, maxLon: 103.0, maxLat: 4.0),
                publishVersion: "20260719T125813Z",
                searchCompact: invalidVersionSearchCompact,
                basemapBytes: 800_000,
                tileCount: 2,
                bytesWithoutThumbnails: 31_000_000,
                bytesWithThumbnails: 39_000_000
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_trailing-extra",
                displayName: "Trailing Extra",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 103.0, minLat: 4.0, maxLon: 104.0, maxLat: 5.0),
                publishVersion: "20260719T125813Z",
                searchCompact: trailingExtraSearchCompact,
                basemapBytes: 700_000,
                tileCount: 2,
                bytesWithoutThumbnails: 30_000_000,
                bytesWithThumbnails: 38_000_000
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_nondigit-version",
                displayName: "Nondigit Version",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 104.0, minLat: 5.0, maxLon: 105.0, maxLat: 6.0),
                publishVersion: "20260719T125813Z",
                searchCompact: nondigitVersionSearchCompact,
                basemapBytes: 600_000,
                tileCount: 1,
                bytesWithoutThumbnails: 29_000_000,
                bytesWithThumbnails: 37_000_000
            ),
        ]
    )
}
```

Add a second directly constructed fixture with a malformed `orphan-parent` path and a
decoder-valid `orphan-parent_child` whose `parent` is `orphan-parent`. The parent must be
dropped while the child remains in `zones` but cannot be reached from `rootZones`.

- [ ] **Step 3: Add the fail-closed catalog regression**

Place this test beside `testOfflineRegionCatalogDerivesRowsFromDecodedRegionIndex()`:

```swift
func testOfflineRegionCatalogDropsConstructedZoneWithMalformedSearchCompactPath() {
    let catalog = OfflineRegionCatalog(
        regionIndex: appConstructedRegionIndexWithMalformedSearchCompactPath()
    )

    XCTAssertEqual(catalog.zones.map(\.id), ["malaysia-singapore-brunei"])
    XCTAssertEqual(catalog.zone(id: "malaysia-singapore-brunei")?.searchCompactPublishVersion, "20260719T125813Z")
    XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_kl"))
    XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_wrong-path-id"))
    XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_invalid-version"))
    XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_trailing-extra"))
    XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_nondigit-version"))
    let rows = catalog.rows(
        installed: [:],
        availablePublishVersions: [
                "malaysia-singapore-brunei": "20260719T125813Z",
                "malaysia-singapore-brunei_kl": "20260719T125813Z",
                "malaysia-singapore-brunei_wrong-path-id": "20260719T125813Z",
                "malaysia-singapore-brunei_invalid-version": "not-a-publish-version",
                "malaysia-singapore-brunei_trailing-extra": "20260719T125813Z",
                "malaysia-singapore-brunei_nondigit-version": "2026071XT125813Z",
        ],
        activeProgress: nil,
        quarantines: []
    )
    XCTAssertEqual(rows.map(\.zone.id), ["malaysia-singapore-brunei"])
    XCTAssertEqual(rows.map(\.state), [.notInstalled])
}
```

Add `testOfflineRegionRowsSurfaceInstalledValidChildOfDroppedParentForCleanup`. Construct
the malformed-parent/valid-child fixture, install the child, and require one child row
whose state is `.unavailable` and whose `hasUnavailableLocalData` is true.

- [ ] **Step 4: Add the diagnostic-record regression**

Add a separate test so removal of the diagnostic write fails independently:

```swift
func testOfflineRegionCatalogRecordsDroppedMalformedZoneInDiagnostics() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("OfflineRegionCatalogDropLogs-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = DiagnosticLogStore(root: root)
    MakingTracksLog.configureDiagnosticLogStore(store)
    defer { MakingTracksLog.configureDiagnosticLogStore(nil) }

    _ = OfflineRegionCatalog(
        regionIndex: appConstructedRegionIndexWithMalformedSearchCompactPath()
    )

    let droppedLines = try store.snapshotLines(window: .everything).filter {
        $0.contains("downloads error region catalog entry dropped")
    }
    XCTAssertEqual(droppedLines.count, 5)
    for region in [
        "malaysia-singapore-brunei_kl",
        "malaysia-singapore-brunei_wrong-path-id",
        "malaysia-singapore-brunei_invalid-version",
        "malaysia-singapore-brunei_trailing-extra",
        "malaysia-singapore-brunei_nondigit-version",
    ] {
        let line = try XCTUnwrap(droppedLines.first { $0.contains("region=\(region)") })
        XCTAssertTrue(line.contains("reason=invalid-search-compact-publish-version"), line)
    }
}
```

- [ ] **Step 5: Run the new tests and verify RED**

Run from the repository root:

```bash
./scripts/sim-lock.sh sh -ec '
  UDID=C4A64D49-24A2-4429-B6E2-AD9A14142A99
  xcrun simctl bootstatus "$UDID" -b
  xcodebuild \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "platform=iOS Simulator,id=$UDID" \
    -parallel-testing-enabled NO \
    -disable-concurrent-destination-testing \
    -derivedDataPath /private/tmp/dd-codex1 \
    -only-testing:MakingTracksTests/AppShellTests/testOfflineRegionCatalogDropsConstructedZoneWithMalformedSearchCompactPath \
    -only-testing:MakingTracksTests/AppShellTests/testOfflineRegionCatalogRecordsDroppedMalformedZoneInDiagnostics \
    -only-testing:MakingTracksTests/AppShellTests/testOfflineRegionRowsSurfaceInstalledValidChildOfDroppedParentForCleanup \
    test
'
```

Expected: the orphan-row test fails against the current all-zones known-ID calculation;
the two strict-path regressions remain green against the already-exact validator. This
establishes the reachability defect without changing `RegionIndex.decode(_:)`.

Observed RED: 3 total, 2 passed, 1 failed. Only the orphan cleanup regression failed:
its rows were `[]` instead of `["orphan-parent_child"]`.

- [ ] **Step 6: Implement the minimal fail-closed projection**

Replace the catalog projection in `OfflineRegionCatalog.init(regionIndex:)` with:

```swift
init(regionIndex: RegionIndex) {
    self.zones = regionIndex.regions.compactMap { entry in
        guard let searchPublishVersion = Self.publishVersion(
            fromSearchCompactPath: entry.searchCompact.path,
            matchingEntryID: entry.id
        ) else {
            MakingTracksLog.file(
                category: .downloads,
                level: .error,
                "region catalog entry dropped",
                fields: [
                    .object("region", entry.id),
                    .public("reason", "invalid-search-compact-publish-version"),
                ]
            )
            return nil
        }
        return OfflineRegionCatalogZone(
            id: entry.id,
            displayName: entry.displayName,
            parentID: entry.parent,
            bbox: entry.bbox,
            publishVersion: searchPublishVersion,
            searchCompactPublishVersion: searchPublishVersion,
            bytesWithoutThumbnails: entry.bytesWithoutThumbnails,
            bytesWithThumbnails: entry.bytesWithThumbnails
        )
    }
}

private static func publishVersion(
    fromSearchCompactPath path: String,
    matchingEntryID entryID: String
) -> String? {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 4,
          parts[0] == entryID,
          parts[2] == "search",
          parts[3] == "compact.json",
          Self.isPublishVersion(parts[1])
    else { return nil }
    return String(parts[1])
}

private static func isPublishVersion(_ value: Substring) -> Bool {
    let bytes = Array(value.utf8)
    return bytes.count == 16
        && bytes[0..<8].allSatisfy(Self.isASCIIDigit)
        && bytes[8] == 84 // T
        && bytes[9..<15].allSatisfy(Self.isASCIIDigit)
        && bytes[15] == 90 // Z
}

private static func isASCIIDigit(_ byte: UInt8) -> Bool {
    (48...57).contains(byte)
}
```

In `rows(...)`, pass `Set(catalogRows.map(\.zone.id))` to `unavailableLocalRows`.
Reachability, rather than mere presence in `zones`, defines whether local state already
has a normal catalog row.

- [ ] **Step 7: Rerun the three tests and verify GREEN**

Run the exact focused command from Step 5.

Expected: all three focused tests pass; the valid contract-shaped direct entry remains
while all five malformed entries are omitted and diagnosed, and the orphan child is
surfaced as unavailable cleanup data.

Observed final focused GREEN: 3 total, 3 passed, 0 failed after every mutation was restored.

- [ ] **Step 8: Prove test teeth**

Temporarily restore `map` plus `preconditionFailure`, run only
`testOfflineRegionCatalogDropsConstructedZoneWithMalformedSearchCompactPath`, and confirm the crash returns.
Restore the approved implementation.

Temporarily remove only `MakingTracksLog.file(...)`, run only
`testOfflineRegionCatalogRecordsDroppedMalformedZoneInDiagnostics`, and confirm it fails because
`droppedLines.count` is `0` where the regression expects `5`. Restore the approved implementation.

Then temporarily change only `parts.count == 4` to `parts.count >= 4` (leaving the
decoder and all other predicates unchanged), run only the catalog behavior regression,
and confirm it fails because the trailing-extra entry is retained. Restore the exact
component count.

Temporarily replace only `Self.isPublishVersion(parts[1])` with
`parts[1].utf8.count == 16`, run the same catalog behavior test, and confirm the
nondigit-version entry is retained. Restore the ASCII timestamp grammar.

Temporarily restore `Set(zones.map(\.id))` as the known-ID calculation and run only the
orphan cleanup regression. Confirm the child row disappears. Restore the reachable-row
known-ID calculation, then rerun all three focused tests to green.

Observed teeth: the original crash and diagnostic-removal checks remained established.
Each new isolated mutation produced 1 total, 0 passed, 1 failed: all-zones known IDs
removed the orphan child row; `parts.count >= 4` retained the trailing-extra entry; and
byte-count-only timestamp validation retained the nondigit-version entry. The restored
focused suite was 3 total, 3 passed, 0 failed.

- [ ] **Step 9: Run the affected app test suite**

Run under `scripts/sim-lock.sh` with the same destination and derived-data arguments:

```bash
./scripts/sim-lock.sh sh -ec '
  UDID=C4A64D49-24A2-4429-B6E2-AD9A14142A99
  xcrun simctl bootstatus "$UDID" -b
  xcodebuild \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "platform=iOS Simulator,id=$UDID" \
    -parallel-testing-enabled NO \
    -disable-concurrent-destination-testing \
    -derivedDataPath /private/tmp/dd-codex1 \
    -only-testing:MakingTracksTests/AppShellTests \
    test
'
```

Capture the actual executed count and require zero failures.

Observed final suite: 152 `AppShellTests` executed, 152 passed, 0 failed, 0 skipped.

- [ ] **Step 10: Run adversarial review and full gates**

Run independent critics for spec fidelity, hostile-input/logging privacy, and test teeth. Cross-examine each
finding, fix only those that survive, and rerun the focused teeth checks after any change.

Refresh `origin/ios`. If #446 has landed, merge the fresh target as a separate mutation and run:

```bash
cd ios
swift test
```

Require the final host suite to be green. Then run the full app host gate:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Capture the Release build result and exact app-unit/UI-test counts. Require zero new warnings and zero
failures. Confirm no `.xcresult` bundles remain from this task.

- [ ] **Step 11: Re-ground, update the issue ledger, and stage without committing**

Verify the fresh target is an ancestor and review the exact staged-ready tree diff:

```bash
git merge-base --is-ancestor origin/ios HEAD
git diff --stat origin/ios
git diff --check origin/ios
```

Rewrite issue #319's body so its Status records the staged implementation, diagnostic behavior, and exact
tests. Then stage only:

```bash
git add \
  docs/superpowers/specs/2026-07-24-invalid-region-index-fail-closed-design.md \
  docs/superpowers/plans/2026-07-24-invalid-region-index-fail-closed.md \
  ios/App/Sources/Map/MapScreen.swift \
  ios/App/Tests/AppShellTests.swift
```

Verify with `git diff --cached --check`, `git diff --cached --stat`, and `git status --short`.

After signing and SSH recovery, create the signed commit, push, and PR. Report the staged worktree path, imperative commit message
`Fail closed on malformed region catalog entries`, full verification counts, and adversarial-review accounting
to fable.
