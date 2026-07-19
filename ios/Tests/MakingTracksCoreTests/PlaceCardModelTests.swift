import Foundation
import XCTest
import MakingTracksData
import MakingTracksTiles
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

    func testPlaceImageEnrichesCardPhotoWithoutLegacyImageURL() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": ["wd:Q42"],
            "image_url": "https://upload.wikimedia.org/legacy.jpg",
            "blurb": "Clock tower",
        ]))
        let base = try XCTUnwrap(PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none)))
        let image = PlaceImage(
            placeID: "mt1_00000000000000000000000000",
            thumbSHA256: String(repeating: "a", count: 64),
            bytes: 12345,
            width: 640,
            height: 480,
            attribution: PlaceImageAttribution(
                creator: "Alice Example",
                licenseCode: "CC-BY-4.0",
                licenseName: "Creative Commons Attribution 4.0",
                licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!,
                sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Clock.jpg")!,
                modified: true
            )
        )

        let enriched = base.enriching(photo: PlaceCardPhoto(placeName: base.name, image: image))

        XCTAssertEqual(enriched.photo?.thumbURL?.absoluteString, "https://tiles.making-tracks.app/thumbs/aa/\(String(repeating: "a", count: 64)).webp")
        XCTAssertEqual(enriched.photo?.thumbSHA256, String(repeating: "a", count: 64))
        XCTAssertEqual(enriched.photo?.width, 640)
        XCTAssertEqual(enriched.photo?.height, 480)
        XCTAssertEqual(enriched.photo?.accessibilityLabel, "Photo of Clock")
        XCTAssertEqual(enriched.photo?.attribution, "Alice Example / Creative Commons Attribution 4.0 / modified")
        XCTAssertEqual(enriched.sourceArticleLink, base.sourceArticleLink)
    }

    func testSourceArticleLinkPrefersCanonicalWikipediaPageIDProvenanceWithKnownHTTPSHost() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": ["osm:node/1", "wp:12345"],
            "wikipedia_title": "Clock tower",
        ]))

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(model?.sourceArticleLink?.label, "Source article")
        XCTAssertEqual(model?.sourceArticleLink?.sourceName, "Wikipedia")
        XCTAssertEqual(model?.sourceArticleLink?.url.absoluteString, "https://en.wikipedia.org/?curid=12345")
    }

    func testSourceArticleLinkDropsUnsafeWikipediaTitleWithoutCanonicalSourceRefFallback() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": ["evil:payload"],
            "wikipedia_title": "safe\u{202E}evil",
        ]))

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertNil(model?.sourceArticleLink)
    }

    func testSourceArticleLinkUsesSafeWikipediaTitleFallback() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": ["evil:payload"],
            "wikipedia_title": "Clock tower",
        ]))

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(model?.sourceArticleLink?.sourceName, "Wikipedia")
        XCTAssertEqual(model?.sourceArticleLink?.url.absoluteString, "https://en.wikipedia.org/wiki/Clock_tower")
    }

    func testSourceArticleLinkUsesCanonicalOpenPlaquesRef() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": ["plaque:openplaques/9876"],
        ]))

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(model?.sourceArticleLink?.sourceName, "Open Plaques")
        XCTAssertEqual(model?.sourceArticleLink?.url.absoluteString, "https://openplaques.org/plaques/9876")
    }

    func testSourceArticleLinkUsesDirectOpenPlaquesRef() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": ["open_plaques:4321"],
        ]))

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(model?.sourceArticleLink?.sourceName, "Open Plaques")
        XCTAssertEqual(model?.sourceArticleLink?.url.absoluteString, "https://openplaques.org/plaques/4321")
    }

    func testSourceArticleLinkUsesCanonicalOpenDataRefs() throws {
        let cases: [(sourceRef: String, sourceName: String, url: String)] = [
            ("osm:node/12", "OpenStreetMap", "https://www.openstreetmap.org/node/12"),
            ("osm:way/34", "OpenStreetMap", "https://www.openstreetmap.org/way/34"),
            ("osm:relation/56", "OpenStreetMap", "https://www.openstreetmap.org/relation/56"),
            (
                "hehle:1234567",
                "Historic England",
                "https://historicengland.org.uk/listing/the-list/list-entry/1234567"
            ),
        ]

        for testCase in cases {
            let snapshot = makeSnapshot(snapshotJSON: jsonString([
                "place_id": "mt1_00000000000000000000000000",
                "name": "Clock",
                "lat": 51.5,
                "lon": -0.12,
                "category": "historic_building",
                "tier": 1,
                "score": 0.9,
                "source_refs": [testCase.sourceRef],
            ]))

            let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

            XCTAssertEqual(model?.sourceArticleLink?.sourceName, testCase.sourceName, testCase.sourceRef)
            XCTAssertEqual(model?.sourceArticleLink?.url.absoluteString, testCase.url, testCase.sourceRef)
        }
    }

    func testSourceArticleLinkUsesWikidataRef() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": ["wd:Q42"],
        ]))

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(model?.sourceArticleLink?.sourceName, "Wikidata")
        XCTAssertEqual(model?.sourceArticleLink?.url.absoluteString, "https://www.wikidata.org/wiki/Q42")
    }

    func testSourceArticleLinkUsesHistoricEnglandRef() throws {
        let snapshot = makeSnapshot(snapshotJSON: jsonString([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Clock",
            "lat": 51.5,
            "lon": -0.12,
            "category": "historic_building",
            "tier": 1,
            "score": 0.9,
            "source_refs": ["historic_england:1234567"],
        ]))

        let model = PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))

        XCTAssertEqual(model?.sourceArticleLink?.sourceName, "Historic England")
        XCTAssertEqual(model?.sourceArticleLink?.url.absoluteString, "https://historicengland.org.uk/listing/the-list/list-entry/1234567")
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
