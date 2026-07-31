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

            XCTAssertTrue(store.save(scope))

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

    func testVersionZeroDegradesToDefaultsWithoutRewritingTheRecord() throws {
        try withStore { defaults, store in
            let versionZero = Data(
                """
                {"version":0,"categories":["museum"],"showHiddenPlaces":true,"showSavedPlaces":false,"showCoverageShading":false}
                """.utf8
            )
            defaults.set(
                versionZero,
                forKey: DiscoveryScopeStore.storageKey
            )

            XCTAssertEqual(store.load(), .defaults)
            XCTAssertEqual(
                defaults.data(forKey: DiscoveryScopeStore.storageKey),
                versionZero
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
            XCTAssertTrue(store.save(empty))
            XCTAssertEqual(store.load(), empty)
            XCTAssertEqual(store.load().visibleCategoryIDs, [])
        }
    }

    func testCategoryIdentifierByteBoundaryRejectsOnlyOversizeValues() throws {
        try withStore { defaults, store in
            let validIdentifier = String(repeating: "a", count: 128)
            defaults.set(
                try recordData(visibleCategoryIDs: [validIdentifier]),
                forKey: DiscoveryScopeStore.storageKey
            )
            XCTAssertEqual(
                store.load().visibleCategoryIDs,
                [validIdentifier]
            )

            let oversizeIdentifier = String(repeating: "a", count: 129)
            defaults.set(
                try recordData(visibleCategoryIDs: [oversizeIdentifier]),
                forKey: DiscoveryScopeStore.storageKey
            )
            XCTAssertEqual(store.load(), .defaults)
        }
    }

    func testNonDataStoredObjectDegradesToDefaults() throws {
        try withStore { defaults, store in
            defaults.set(
                ["unexpected"],
                forKey: DiscoveryScopeStore.storageKey
            )

            XCTAssertEqual(store.load(), .defaults)
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

    func testInvalidSaveReportsFailureWithoutReplacingValidRecord() throws {
        try withStore { _, store in
            let valid = DiscoveryScope(includeHidden: true)
            XCTAssertTrue(store.save(valid))

            let invalid = DiscoveryScope(
                visibleCategoryIDs: Set(
                    (0 ... 128).map { "category-\($0)" }
                )
            )
            XCTAssertFalse(store.save(invalid))
            XCTAssertEqual(store.load(), valid)
        }
    }

    func testResetRemovesCurrentRecord() throws {
        try withStore { defaults, store in
            XCTAssertTrue(store.save(DiscoveryScope(includeHidden: true)))

            store.reset()

            XCTAssertNil(defaults.object(forKey: DiscoveryScopeStore.storageKey))
        }
    }

    private func recordData(visibleCategoryIDs: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "visibleCategoryIDs": visibleCategoryIDs,
            "includeHidden": true,
            "showSaved": false,
            "showCoverageShading": false,
        ])
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
