import Foundation
import XCTest
@testable import MakingTracksMapStyle

final class DiscoveryScopeStoreTests: XCTestCase {
    func testDefaultsAndEffectiveScopeDifferenceIncludeEveryChoice() {
        XCTAssertEqual(
            DiscoveryScope.defaults,
            DiscoveryScope(
                visibleCategoryIDs: nil,
                includeHidden: false,
                showSaved: true,
                showCoverageShading: true
            )
        )
        XCTAssertFalse(DiscoveryScope.defaults.differsFromDefault)
        XCTAssertTrue(DiscoveryScope(visibleCategoryIDs: []).differsFromDefault)
        XCTAssertTrue(DiscoveryScope(includeHidden: true).differsFromDefault)
        XCTAssertTrue(DiscoveryScope(showSaved: false).differsFromDefault)
        XCTAssertTrue(DiscoveryScope(showCoverageShading: false).differsFromDefault)
    }

    func testSaveAndLoadRoundTripAllChoicesWithDeterministicCategoryOrder() throws {
        try withStore { defaults, store in
            let scope = DiscoveryScope(
                visibleCategoryIDs: ["museum", "history"],
                includeHidden: true,
                showSaved: false,
                showCoverageShading: false
            )

            store.save(scope)

            XCTAssertEqual(store.load(), scope)
            let data = try XCTUnwrap(defaults.data(forKey: DiscoveryScopeStore.storageKey))
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            XCTAssertEqual(object["version"] as? Int, 1)
            XCTAssertEqual(
                object["visibleCategoryIDs"] as? [String],
                ["history", "museum"]
            )
        }
    }

    func testNewerRecordDegradesToDefaultsWithoutReadingUnknownFields() throws {
        try withStore { defaults, store in
            defaults.set(
                Data(
                    """
                    {"version":2,"visibleCategoryIDs":[],"includeHidden":true,"showSaved":false,"showCoverageShading":false}
                    """.utf8
                ),
                forKey: DiscoveryScopeStore.storageKey
            )

            XCTAssertEqual(store.load(), .defaults)
        }
    }

    func testVersionZeroMigratesDeterministicallyAndRewritesVersionOne() throws {
        try withStore { defaults, store in
            defaults.set(
                Data(
                    """
                    {"version":0,"categories":["museum"],"showHiddenPlaces":true,"showSavedPlaces":false,"showCoverageShading":false}
                    """.utf8
                ),
                forKey: DiscoveryScopeStore.storageKey
            )

            XCTAssertEqual(
                store.load(),
                DiscoveryScope(
                    visibleCategoryIDs: ["museum"],
                    includeHidden: true,
                    showSaved: false,
                    showCoverageShading: false
                )
            )

            let migratedData = try XCTUnwrap(
                defaults.data(forKey: DiscoveryScopeStore.storageKey)
            )
            let migratedObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
            )
            XCTAssertEqual(migratedObject["version"] as? Int, 1)
            XCTAssertEqual(
                migratedObject["visibleCategoryIDs"] as? [String],
                ["museum"]
            )
        }
    }

    func testMalformedRecordDegradesToDefaultsRatherThanEmptyScope() throws {
        try withStore { defaults, store in
            defaults.set(
                Data(#"{"version":1,"visibleCategoryIDs":"#.utf8),
                forKey: DiscoveryScopeStore.storageKey
            )

            let loaded = store.load()

            XCTAssertEqual(loaded, .defaults)
            XCTAssertNil(loaded.visibleCategoryIDs)
        }
    }

    func testInvalidCategoryIdentifierDegradesToDefaultsButExplicitEmptyPersists() throws {
        try withStore { defaults, store in
            defaults.set(
                Data(
                    """
                    {"version":1,"visibleCategoryIDs":[""],"includeHidden":true,"showSaved":false,"showCoverageShading":false}
                    """.utf8
                ),
                forKey: DiscoveryScopeStore.storageKey
            )
            XCTAssertEqual(store.load(), .defaults)

            let empty = DiscoveryScope(visibleCategoryIDs: [])
            store.save(empty)
            XCTAssertEqual(store.load(), empty)
            XCTAssertEqual(store.load().visibleCategoryIDs, [])
        }
    }

    func testOversizeRecordDegradesToDefaultsBeforeDecoding() throws {
        try withStore { defaults, store in
            defaults.set(
                Data(repeating: 0x20, count: 65_537),
                forKey: DiscoveryScopeStore.storageKey
            )

            XCTAssertEqual(store.load(), .defaults)
        }
    }

    func testCategoryArrayCapAppliesBeforeDuplicateIdentifiersAreCollapsed() throws {
        try withStore { defaults, store in
            let object: [String: Any] = [
                "version": 1,
                "visibleCategoryIDs": Array(
                    repeating: "museum",
                    count: 129
                ),
                "includeHidden": true,
                "showSaved": false,
                "showCoverageShading": false,
            ]
            defaults.set(
                try JSONSerialization.data(withJSONObject: object),
                forKey: DiscoveryScopeStore.storageKey
            )

            XCTAssertEqual(store.load(), .defaults)
        }
    }

    func testLegacyCoverageValuesBothMigrateWithoutLosingFalse() throws {
        for legacyValue in [false, true] {
            try withStore { defaults, store in
                defaults.set(
                    legacyValue,
                    forKey: DiscoveryScopeStore.legacyCoverageShadingKey
                )

                let loaded = store.load()

                XCTAssertEqual(
                    loaded,
                    DiscoveryScope(showCoverageShading: legacyValue)
                )
                XCTAssertNotNil(
                    defaults.data(forKey: DiscoveryScopeStore.storageKey)
                )
                XCTAssertNil(
                    defaults.object(
                        forKey: DiscoveryScopeStore.legacyCoverageShadingKey
                    )
                )
            }
        }
    }

    func testResetRemovesCurrentAndLegacyRecords() throws {
        try withStore { defaults, store in
            store.save(DiscoveryScope(includeHidden: true))
            defaults.set(
                false,
                forKey: DiscoveryScopeStore.legacyCoverageShadingKey
            )

            store.reset()

            XCTAssertNil(defaults.object(forKey: DiscoveryScopeStore.storageKey))
            XCTAssertNil(
                defaults.object(
                    forKey: DiscoveryScopeStore.legacyCoverageShadingKey
                )
            )
        }
    }

    private func withStore(
        _ body: (UserDefaults, DiscoveryScopeStore) throws -> Void
    ) throws {
        let suiteName = "DiscoveryScopeStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try body(defaults, DiscoveryScopeStore(userDefaults: defaults))
    }
}
