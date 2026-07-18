import Foundation
import XCTest
import MakingTracksData
@testable import MakingTracksCore

final class PlaceCardModelTests: XCTestCase {
    func testSnapshotPathDropsUnsafeTextAndUsesSafeSnapshotFallbacks() throws {
        let snapshot = makeSnapshot(
            name: "Safe fallback",
            category: "attraction",
            snapshotJSON: jsonString([
                "place_id": "mt1_00000000000000000000000000",
                "name": "safe\u{202E}evil",
                "lat": 51.5,
                "lon": -0.12,
                "category": "attraction",
                "tier": 2,
                "score": 0.72,
                "source_refs": ["wd:Q42"],
            ])
        )

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(model?.name, "Safe fallback")
        XCTAssertEqual(model?.category, "attraction")
    }

    func testSnapshotPathIgnoresLegacyImageURLAndKeepsMarkdownBlurbInertForVerbatimRendering() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": ["wd:Q42"],
            "image_url": "https://evil.example/track.jpg",
            "blurb": "[tap me](https://evil.example) %@",
        ]))

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: true, visit: .visited))

        XCTAssertNil(model?.photo)
        XCTAssertEqual(model?.blurb, "[tap me](https://evil.example) %@")
        XCTAssertEqual(model?.pinState, PinState(saved: true, visit: .visited))
    }

    func testSnapshotPathValidatesSourceRefsPatternBeforePrefixAndDropsUnknowns() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": [
                "Historic England:1",
                "colonless",
                "evil:payload",
                "wd:Q42",
                "wp:Big_Ben",
                "osm:node/1",
                "open_plaques:123",
                "historic_england:abc",
            ],
        ]))

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(
            model?.sourceNames,
            ["Historic England", "Open Plaques", "OpenStreetMap", "Wikidata", "Wikipedia"]
        )
    }

    func testOversizeSnapshotJSONFallsBackToSnapshotColumnsAndDoesNotParsePayload() throws {
        let snapshot = makeSnapshot(
            name: "Snapshot name",
            category: "oddity",
            snapshotJSON: String(repeating: "x", count: PlaceCardModel.maxSnapshotJSONBytes + 1)
        )

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .loved))

        XCTAssertEqual(model?.name, "Snapshot name")
        XCTAssertEqual(model?.category, "oddity")
        XCTAssertEqual(model?.sourceNames, [])
        XCTAssertNil(model?.photo)
        XCTAssertEqual(model?.pinState, PinState(saved: false, visit: .loved))
    }

    func testSnapshotJSONWithMismatchedPlaceIDIgnoresJSONDisplayFields() throws {
        let snapshot = makeSnapshot(
            name: "Snapshot name",
            category: "snapshot-category",
            snapshotJSON: jsonString([
                "place_id": "mt1_11111111111111111111111111",
                "name": "Wrong safe name",
                "lat": 51.5,
                "lon": -0.12,
                "category": "wrong-category",
                "tier": 1,
                "score": 0.9,
                "source_refs": ["osm:node/1"],
                "image_url": "https://upload.wikimedia.org/wrong.jpg",
                "blurb": "Wrong blurb",
            ])
        )

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(model?.name, "Snapshot name")
        XCTAssertEqual(model?.category, "snapshot-category")
        XCTAssertNil(model?.blurb)
        XCTAssertNil(model?.photo)
        XCTAssertEqual(model?.sourceNames, [])
    }

    func testSnapshotJSONWithUnknownKeysIgnoresJSONDisplayFields() throws {
        let snapshot = makeSnapshot(
            name: "Snapshot name",
            category: "snapshot-category",
            snapshotJSON: jsonString([
                "place_id": "mt1_00000000000000000000000000",
                "name": "Safe name",
                "lat": 51.5,
                "lon": -0.12,
                "category": "historic_building",
                "tier": 1,
                "score": 0.9,
                "source_refs": ["wd:Q42"],
                "unexpected": "safe but not contracted",
            ])
        )

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(model?.name, "Snapshot name")
        XCTAssertEqual(model?.category, "snapshot-category")
        XCTAssertEqual(model?.sourceNames, [])
    }
}

private func makeSnapshot(
    name: String = "Clock",
    category: String = "historic_building",
    snapshotJSON: String
) -> PlaceSnapshot {
    PlaceSnapshot(
        placeID: "mt1_00000000000000000000000000",
        name: name,
        lat: 51.5,
        lon: -0.12,
        category: category,
        tier: 1,
        snapshotJSON: snapshotJSON,
        snapshotSchemaVersion: 1,
        fetchedAt: Date(timeIntervalSince1970: 0)
    )
}

private func jsonString(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}
