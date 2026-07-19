import CryptoKit
import Foundation
import XCTest
import zlib
@testable import MakingTracksTiles

final class MakingTracksTilesTests: XCTestCase {
    func testVersionGateTruthTableIncludesReaderFloorBranches() {
        XCTAssertEqual(VersionGate.schema(readerMax: 1, dataVersion: 1, minSupported: 1), .ok)
        XCTAssertEqual(VersionGate.schema(readerMax: 1, dataVersion: 2, minSupported: 1), .tooNew)
        XCTAssertEqual(VersionGate.schema(readerMax: 1, dataVersion: 0, minSupported: 1), .tooOld)
        XCTAssertEqual(VersionGate.reader(readerVersion: 2, minReaderVersion: 3, hasReadableCache: true), .updateAvailable)
        XCTAssertEqual(VersionGate.reader(readerVersion: 2, minReaderVersion: 3, hasReadableCache: false), .updateRequired)
        XCTAssertEqual(VersionGate.reader(readerVersion: 2, minReaderVersion: 2, hasReadableCache: false), .ok)
    }

    func testHTTPFetcherRejectsWrongHostsAndCrossHostRedirects() async throws {
        XCTAssertThrowsError(try HTTPTileFetcher.validateOrigin(URL(string: "https://evil.example/uk/current.json")!))
        XCTAssertThrowsError(try HTTPTileFetcher.validateOrigin(URL(string: "http://tiles.making-tracks.app/uk/current.json")!))
        XCTAssertThrowsError(try HTTPTileFetcher.validateOrigin(URL(string: "https://tiles.making-tracks.app:8443/uk/current.json")!))
        XCTAssertNoThrow(try HTTPTileFetcher.validateOrigin(URL(string: "https://tiles.making-tracks.app/uk/current.json")!))
        XCTAssertNoThrow(try HTTPTileFetcher.validateOrigin(URL(string: "https://tiles.making-tracks.app:443/uk/current.json")!))
        XCTAssertThrowsError(
            try HTTPTileFetcher.validateRedirect(
                from: URL(string: "https://tiles.making-tracks.app/uk/current.json")!,
                to: URL(string: "https://evil.example/uk/current.json")!
            )
        )
        XCTAssertNoThrow(
            try HTTPTileFetcher.validateRedirect(
                from: URL(string: "https://tiles.making-tracks.app/uk/current.json")!,
                to: URL(string: "https://tiles.making-tracks.app/uk/current-v2.json")!
            )
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectURLProtocol.self]
        let fetcher = HTTPTileFetcher(configuration: configuration)
        RedirectURLProtocol.reset()
        defer { RedirectURLProtocol.reset() }
        RedirectURLProtocol.mode = .status(302, location: "https://evil.example/uk/current.json")
        do {
            _ = try await fetcher.fetch(URL(string: "https://tiles.making-tracks.app/uk/current.json")!)
            XCTFail("302 redirect response unexpectedly succeeded")
        } catch TileError.httpStatus(302) {
        } catch {
            XCTFail("expected httpStatus(302), got \(error)")
        }

        RedirectURLProtocol.mode = .status(500, location: nil)
        do {
            _ = try await fetcher.fetch(URL(string: "https://tiles.making-tracks.app/uk/current.json")!)
            XCTFail("non-2xx fetch unexpectedly succeeded")
        } catch TileError.httpStatus(500) {
        } catch {
            XCTFail("expected httpStatus(500), got \(error)")
        }
    }

    func testManifestPinsCurrentAndExposesAttributionBasemapAndIntegrity() async throws {
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(attributionSources: ["osm"]),
        ])
        let cache = try temporaryCache()
        let client = ManifestClient(region: "uk", fetcher: fetcher, cache: cache)

        let pin = await client.refresh()

        XCTAssertEqual(pin.state, .ok)
        XCTAssertEqual(pin.publish?.publishVersion, "20260716T155409Z")
        XCTAssertEqual(pin.publish?.manifest.attribution.map(\.source), ["osm"])
        XCTAssertEqual(pin.publish?.basemapURL?.absoluteString, "https://tiles.making-tracks.app/uk/20260716T155409Z/uk.pmtiles")
        XCTAssertEqual(pin.publish?.basemapIntegrity?.sha256, String(repeating: "1", count: 64))
        XCTAssertEqual(pin.publish?.basemapIntegrity?.bytes, 1234)
    }

    func testManifestCurrentPublishVersionFetchesOnlyCurrentPointer() async throws {
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/malaysia/current.json": jsonData([
                "schema_version": 1,
                "publish_version": "20260716T155035Z",
            ]),
        ])

        let version = try await ManifestClient.currentPublishVersion(region: "malaysia", fetcher: fetcher)

        XCTAssertEqual(version, "20260716T155035Z")
        XCTAssertEqual(fetcher.requestedURLs, [
            "https://tiles.making-tracks.app/malaysia/current.json",
        ])
    }

    func testManifestRefusesAttributionAllOfViolationAndColdInvalidIsUnavailable() async throws {
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(minReaderVersion: 1, attributionSources: ["osm"]),
        ])
        let client = ManifestClient(region: "uk", fetcher: fetcher, cache: try temporaryCache())

        let pin = await client.refresh()

        XCTAssertNil(pin.publish)
        XCTAssertEqual(pin.state, .unavailable)
    }

    func testManifestInvalidWithCacheKeepsCachedPublishButSurfacesManifestInvalid() async throws {
        let cache = try temporaryCache()
        try cache.recordVerifiedPublish(region: "uk", publish: cachedPublish("20260715T000000Z", attributionSources: ["osm"]))
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(minReaderVersion: 1, attributionSources: ["osm"]),
        ])
        let pin = await ManifestClient(region: "uk", fetcher: fetcher, cache: cache).refresh()

        XCTAssertEqual(pin.state, .manifestInvalid)
        XCTAssertEqual(pin.publish?.publishVersion, "20260715T000000Z")
    }

    func testNewerManifestWithReadableCacheBecomesUpdateAvailable() async throws {
        let cache = try temporaryCache()
        try cache.recordVerifiedPublish(region: "uk", publish: cachedPublish("20260715T000000Z", attributionSources: ["osm"]))
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(minReaderVersion: 3, attributionSources: ["osm"]),
        ])
        let client = ManifestClient(region: "uk", fetcher: fetcher, cache: cache)

        let pin = await client.refresh()

        XCTAssertEqual(pin.state, .updateAvailable)
        XCTAssertEqual(pin.publish?.publishVersion, "20260715T000000Z")

        let cold = await ManifestClient(region: "uk", fetcher: fetcher, cache: try temporaryCache()).refresh()
        XCTAssertEqual(cold.state, .updateRequired)
        XCTAssertNil(cold.publish)
    }

    func testManifestRefusesRegionPublishMismatchAndNestedSchemaExtras() async throws {
        let mismatch = ManifestClient(region: "uk", fetcher: StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(region: "malaysia", attributionSources: []),
        ]), cache: try temporaryCache())
        let mismatchResult = await mismatch.refresh()
        XCTAssertEqual(mismatchResult.state, .unavailable)

        var object = manifestObject(attributionSources: [])
        object["counts"] = ["total": -1, "by_tier": [1, 0, 0, 0], "extra": true]
        XCTAssertThrowsError(try Manifest.decode(jsonData(object)))
    }

    func testCodecVerifiesShaInflatesAndRejectsTamperingBombsAndTrailingGarbage() throws {
        let tile = tileObject(places: [validPlace()])
        let gz = try gzipJSON(tile)
        let sha = sha256(gz)
        let inflated = try TileCodec.decode(gzipped: gz, expectedSHA256: sha, expectedBytes: gz.count)
        XCTAssertTrue(String(decoding: inflated, as: UTF8.self).contains("\"places\""))

        var flipped = gz
        flipped[10] ^= 0xff
        XCTAssertThrowsError(try TileCodec.decode(gzipped: flipped, expectedSHA256: sha, expectedBytes: flipped.count)) {
            XCTAssertEqual($0 as? TileError, .checksumMismatch)
        }

        var trailing = gz
        trailing.append(0)
        XCTAssertThrowsError(try TileCodec.decode(gzipped: trailing, expectedSHA256: sha256(trailing), expectedBytes: trailing.count)) {
            XCTAssertEqual($0 as? TileError, .invalidGzip)
        }

        let bomb = try gzipData(Data(repeating: 0x41, count: TileCodec.maxUncompressedBytes + 1))
        XCTAssertLessThanOrEqual(bomb.count, TileCodec.maxCompressedBytes)
        XCTAssertThrowsError(try TileCodec.decode(gzipped: bomb, expectedSHA256: sha256(bomb), expectedBytes: bomb.count)) {
            XCTAssertEqual($0 as? TileError, .inflatedTooLarge)
        }
    }

    func testPlaceDecoderDropsEveryInvalidCapButKeepsValidPlacesAndNullsBadImageHosts() throws {
        var badCases: [[String: Any]] = [
            validPlace(["place_id": "mt1_short"]),
            validPlace(["name": String(repeating: "a", count: 201)]),
            validPlace(["name": "safe\u{202E}evil"]),
            validPlace(["category": String(repeating: "a", count: 65)]),
            validPlace(["blurb": String(repeating: "a", count: 601)]),
            validPlace(["wikipedia_title": String(repeating: "a", count: 301)]),
            validPlace(["alt_names": Array(repeating: "A", count: 9)]),
            validPlace(["source_refs": ["wd:Q42", "wd:Q42"]]),
            validPlace(["source_refs": []]),
            validPlace(["source_refs": (0..<65).map { "wd:Q\($0)" }]),
            validPlace(["source_refs": [String(repeating: "a", count: 129)]]),
            validPlace(["source_refs": ["OSM:way/123"]]),
            validPlace(["tier": 5]),
            validPlace(["score": 1.1]),
            validPlace(["lat": 91.0]),
            validPlace(["lon": 181.0]),
            validPlace(["image_url": "http://upload.wikimedia.org/file.jpg"]),
            validPlace(["image_url": "https://upload.wikimedia.org/" + String(repeating: "a", count: 2_050)]),
            validPlace(["alt_names": [String(repeating: "a", count: 201)]]),
            validPlace(["category": "safe\u{202E}evil"]),
            validPlace(["blurb": "safe\u{202E}evil"]),
            validPlace(["wikipedia_title": "safe\u{202E}evil"]),
            validPlace(["name": "e" + String(repeating: "\u{301}", count: 200)]),
        ]
        let imageHostPlace = validPlace(["place_id": "mt1_00000000000000000000000001", "image_url": "https://example.com/file.jpg", "source_refs": ["osm:node/5", "wd:Q42"]])
        badCases.append(imageHostPlace)
        let tile = tileObject(places: [validPlace()] + badCases)

        let decoded = try PlaceDecoder.decode(tileData: jsonData(tile), expected: TileCoordinate(z: 10, x: 511, y: 340), attributionSources: ["wd"])

        XCTAssertEqual(decoded.places.map(\.mapPlace.id), ["mt1_00000000000000000000000000", "mt1_00000000000000000000000001"])
        XCTAssertEqual(decoded.places.first?.mapPlace.category, "historic_building")
        XCTAssertNil(decoded.places.last?.imageURL)
        XCTAssertEqual(decoded.places.last?.sourceRefs, ["osm:node/5", "wd:Q42"])
        XCTAssertFalse(decoded.places.last?.placeRef.rawJSON.contains("https://example.com/file.jpg") ?? true)
    }

    func testPlaceDecoderRejectsMislabeledTileAndReportsMissingAttributionSource() throws {
        XCTAssertThrowsError(
            try PlaceDecoder.decode(
                tileData: jsonData(tileObject(places: [validPlace()], x: 512)),
                expected: TileCoordinate(z: 10, x: 511, y: 340),
                attributionSources: ["wd"]
            )
        )

        let decoded = try PlaceDecoder.decode(
            tileData: jsonData(tileObject(places: [validPlace(["source_refs": ["osm:node/5"]])])),
            expected: TileCoordinate(z: 10, x: 511, y: 340),
            attributionSources: []
        )
        XCTAssertEqual(decoded.missingAttributionSources, ["osm"])
    }

    func testLiveCapturedUKTileFixtureRoundTripsThroughCodecAndDecoder() throws {
        let gz = Data(base64Encoded: liveTile489310Base64)!
        let raw = try TileCodec.decode(
            gzipped: gz,
            expectedSHA256: "3a7428ea238572e19ee284e9662b1db40f18672f260e2d257ad96751def3d9e8",
            expectedBytes: 214
        )
        let decoded = try PlaceDecoder.decode(tileData: raw, expected: TileCoordinate(z: 10, x: 489, y: 310), attributionSources: [])

        XCTAssertEqual(decoded.places.map(\.mapPlace.id), ["mt1_3MBHTKMAFVPJWMQRF79PW6J0TW"])
        XCTAssertEqual(decoded.places.first?.mapPlace.tier, 4)
        XCTAssertEqual(decoded.places.first?.mapPlace.category, "historic_building")
        XCTAssertEqual(decoded.missingAttributionSources, [])
    }

    func testTileCoverageMatchesReferenceAndAddsOneTileRing() {
        XCTAssertEqual(TileCoverage.lonLatToZ10(lat: 51.5, lon: -0.12), TileCoordinate(z: 10, x: 511, y: 340))
        XCTAssertEqual(TileCoverage.lonLatToZ10(lat: 3.139, lon: 101.6869), TileCoordinate(z: 10, x: 801, y: 503))

        let visible = BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51)
        let tiles = TileCoverage.tiles(for: visible, prefetchRadius: 1)

        XCTAssertTrue(tiles.contains(TileCoordinate(z: 10, x: 511, y: 340)))
        XCTAssertTrue(tiles.contains(TileCoordinate(z: 10, x: 510, y: 339)))
        XCTAssertEqual(Set(tiles).count, tiles.count)
    }

    func testTileClientPinsSessionServesCacheOfflineAndRejectsAttributionStripping() async throws {
        let tile = try gzipJSON(tileObject(places: [validPlace(["source_refs": ["osm:node/5"]])]))
        let sha = sha256(tile)
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(tileSHA: sha, tileBytes: tile.count, attributionSources: ["osm"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz": tile,
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache())

        try await client.refreshPin()
        let first = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)
        let firstState = await client.loadState
        let firstPresent = await client.isPresentInCurrentTiles("mt1_00000000000000000000000000")
        let firstRef = await client.placeRef(for: "mt1_00000000000000000000000000")
        let firstAttribution = await client.attribution

        XCTAssertEqual(first.map(\.id), ["mt1_00000000000000000000000000"])
        XCTAssertEqual(firstState, .ok)
        XCTAssertTrue(firstPresent)
        XCTAssertNotNil(firstRef)
        XCTAssertEqual(firstAttribution, [Attribution(source: "osm", license: "ODbL-1.0", text: "OSM credit")])

        fetcher.routes["https://tiles.making-tracks.app/uk/current.json"] = jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"])
        fetcher.routes["https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json"] = manifestData(tileSHA: sha, tileBytes: tile.count, attributionSources: ["osm"])
        let stillPinned = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)
        XCTAssertEqual(stillPinned.map(\.id), ["mt1_00000000000000000000000000"])

        fetcher.routes.removeAll()
        let offline = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)
        let offlineState = await client.loadState
        XCTAssertEqual(offline.map(\.id), ["mt1_00000000000000000000000000"])
        XCTAssertEqual(offlineState, .stale)

        let strippedFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(tileSHA: sha, tileBytes: tile.count, attributionSources: []),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz": tile,
        ])
        let strippedClient = TileClient(region: "uk", fetcher: strippedFetcher, cache: try temporaryCache())
        try await strippedClient.refreshPin()
        let stripped = await strippedClient.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)
        let strippedState = await strippedClient.loadState
        let strippedAttribution = await strippedClient.attribution
        let strippedPresent = await strippedClient.isPresentInCurrentTiles("mt1_00000000000000000000000000")
        XCTAssertEqual(stripped, [])
        XCTAssertEqual(strippedState, .manifestInvalid)
        XCTAssertEqual(strippedAttribution, [])
        XCTAssertFalse(strippedPresent)
    }

    func testTileClientSkipsOrdinaryCorruptTilesWithoutRevokingManifest() async throws {
        var corrupt = try gzipJSON(tileObject(places: [validPlace()]))
        corrupt[10] ^= 0xff
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(tileSHA: String(repeating: "0", count: 64), tileBytes: corrupt.count, attributionSources: []),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz": corrupt,
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache())

        try await client.refreshPin()
        let places = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)
        let state = await client.loadState
        let attribution = await client.attribution

        XCTAssertEqual(places, [])
        XCTAssertEqual(state, .unavailable)
        XCTAssertEqual(attribution, [])
    }

    func testTileClientServesVerifiedCacheWhenRefreshStartsOfflineAndClearsOnRepoint() async throws {
        let cache = try temporaryCache()
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let sha = sha256(tile)
        try cache.recordVerifiedPublish(region: "uk", publish: cachedPublish("20260715T000000Z", tileSHA: sha, tileBytes: tile.count, attributionSources: []))
        try cache.storeTile(region: "uk", publishVersion: "20260715T000000Z", coordinate: TileCoordinate(z: 10, x: 511, y: 340), sha256: sha, data: tile)
        let offlineClient = TileClient(region: "uk", fetcher: StubFetcher(routes: [:]), cache: cache)

        try await offlineClient.refreshPin()
        let offline = await offlineClient.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)
        let offlineState = await offlineClient.loadState

        XCTAssertEqual(offline.map(\.id), ["mt1_00000000000000000000000000"])
        XCTAssertEqual(offlineState, .stale)

        let repointTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])]))
        let repointSHA = sha256(repointTile)
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(tileSHA: repointSHA, tileBytes: repointTile.count, attributionSources: []),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz": repointTile,
        ])
        let repointClient = TileClient(region: "uk", fetcher: fetcher, cache: cache)
        try await repointClient.refreshPin()
        _ = await repointClient.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)
        let oldPresent = await repointClient.isPresentInCurrentTiles("mt1_00000000000000000000000000")
        let newPresent = await repointClient.isPresentInCurrentTiles("mt1_00000000000000000000000001")
        XCTAssertFalse(oldPresent)
        XCTAssertTrue(newPresent)
    }

    func testTileClientCanLoadInitialViewportFromLocalPinWithoutManifestRefresh() async throws {
        let cache = try temporaryCache()
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let sha = sha256(tile)
        try cache.recordVerifiedPublish(
            region: "uk",
            publish: cachedPublish("20260715T000000Z", tileSHA: sha, tileBytes: tile.count, attributionSources: [])
        )
        try cache.storeTile(
            region: "uk",
            publishVersion: "20260715T000000Z",
            coordinate: TileCoordinate(z: 10, x: 511, y: 340),
            sha256: sha,
            data: tile
        )
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: cache)

        let places = await client.places(
            inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51),
            zoom: 16,
            allowManifestRefresh: false
        )
        let state = await client.loadState

        XCTAssertEqual(places.map(\.id), ["mt1_00000000000000000000000000"])
        XCTAssertEqual(state, .stale)
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/current.json"))
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260715T000000Z/manifest.json"))
    }

    func testTileClientKeepsOnlyCurrentViewportPlaceRefsInMemory() async throws {
        let londonID = "mt1_00000000000000000000000000"
        let unusedLondonID = "mt1_00000000000000000000000002"
        let klID = "mt1_00000000000000000000000001"
        let londonTile = try gzipJSON(tileObject(places: [
            validPlace(["place_id": londonID]),
            validPlace([
                "place_id": unusedLondonID,
                "name": "Unused London Place",
                "lat": 51.501,
                "lon": -0.125,
            ]),
        ]))
        let klTile = try gzipJSON(tileObject(
            places: [validPlace([
                "place_id": klID,
                "name": "KL Tower",
                "lat": 3.1528,
                "lon": 101.7037,
            ])],
            x: 801,
            y: 503
        ))
        let londonSHA = sha256(londonTile)
        let klSHA = sha256(klTile)
        var manifest = manifestObject(tileSHA: londonSHA, tileBytes: londonTile.count, attributionSources: [])
        manifest["tiles"] = [
            ["x": 511, "y": 340, "sha256": londonSHA, "bytes": londonTile.count],
            ["x": 801, "y": 503, "sha256": klSHA, "bytes": klTile.count],
        ]
        manifest["counts"] = ["total": 3, "by_tier": [3, 0, 0, 0]]
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": jsonData(manifest),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz": londonTile,
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/801/503.json.gz": klTile,
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache())

        try await client.refreshPin()
        let london = await client.places(
            inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51),
            zoom: 16
        )
        let londonPresent = await client.isPresentInCurrentTiles(londonID)
        let selectedLondonRef = await client.placeRef(for: londonID)
        XCTAssertEqual(london.map(\.id), [londonID, unusedLondonID])
        XCTAssertTrue(londonPresent)
        XCTAssertNotNil(selectedLondonRef)

        let kl = await client.places(
            inViewport: BBox(minLon: 101.68, minLat: 3.13, maxLon: 101.70, maxLat: 3.15),
            zoom: 16
        )
        let oldPresent = await client.isPresentInCurrentTiles(londonID)
        let unusedOldPresent = await client.isPresentInCurrentTiles(unusedLondonID)
        let oldRef = await client.placeRef(for: londonID)
        let unusedOldRef = await client.placeRef(for: unusedLondonID)
        let currentPresent = await client.isPresentInCurrentTiles(klID)
        let currentRef = await client.placeRef(for: klID)
        XCTAssertEqual(kl.map(\.id), [klID])
        XCTAssertFalse(oldPresent)
        XCTAssertFalse(unusedOldPresent)
        XCTAssertNotNil(oldRef)
        XCTAssertNil(unusedOldRef)
        XCTAssertTrue(currentPresent)
        XCTAssertNotNil(currentRef)
    }

    func testTileClientBoundsRecentlyRequestedPlaceRefs() async throws {
        let selectedIDs = (0..<129).map { String(format: "mt1_%026d", $0) }
        let londonTile = try gzipJSON(tileObject(places: selectedIDs.enumerated().map { index, placeID in
            validPlace([
                "place_id": placeID,
                "name": "Selected Place \(index)",
                "lat": 51.49 + Double(index) * 0.00001,
                "lon": -0.13 + Double(index) * 0.00001,
            ])
        }))
        let klID = "mt1_00000000000000000000000129"
        let klTile = try gzipJSON(tileObject(
            places: [validPlace([
                "place_id": klID,
                "name": "KL Tower",
                "lat": 3.1528,
                "lon": 101.7037,
            ])],
            x: 801,
            y: 503
        ))
        let londonSHA = sha256(londonTile)
        let klSHA = sha256(klTile)
        var manifest = manifestObject(tileSHA: londonSHA, tileBytes: londonTile.count, attributionSources: [])
        manifest["tiles"] = [
            ["x": 511, "y": 340, "sha256": londonSHA, "bytes": londonTile.count],
            ["x": 801, "y": 503, "sha256": klSHA, "bytes": klTile.count],
        ]
        manifest["counts"] = ["total": 130, "by_tier": [130, 0, 0, 0]]
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": jsonData(manifest),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz": londonTile,
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/801/503.json.gz": klTile,
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache())

        try await client.refreshPin()
        _ = await client.places(
            inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51),
            zoom: 16
        )
        for placeID in selectedIDs {
            let selectedRef = await client.placeRef(for: placeID)
            XCTAssertNotNil(selectedRef)
        }
        _ = await client.places(
            inViewport: BBox(minLon: 101.68, minLat: 3.13, maxLon: 101.70, maxLat: 3.15),
            zoom: 16
        )
        let oldestRef = await client.placeRef(for: selectedIDs[0])
        let nextRef = await client.placeRef(for: selectedIDs[1])
        let newestRef = await client.placeRef(for: selectedIDs[128])

        XCTAssertNil(oldestRef)
        XCTAssertNotNil(nextRef)
        XCTAssertNotNil(newestRef)
    }

    func testTileCacheEvictsLeastRecentlyUsedTileBlobsOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MakingTracksTilesTests-\(UUID().uuidString)", isDirectory: true)
        let cache = try TileCache(directory: directory, maxBytes: 25)
        let coord1 = TileCoordinate(z: 10, x: 1, y: 1)
        let coord2 = TileCoordinate(z: 10, x: 2, y: 2)
        let coord3 = TileCoordinate(z: 10, x: 3, y: 3)
        let data = Data(repeating: 1, count: 10)
        try cache.storeTile(region: "uk", publishVersion: "20260716T155409Z", coordinate: coord1, sha256: String(repeating: "1", count: 64), data: data)
        try cache.storeTile(region: "uk", publishVersion: "20260716T155409Z", coordinate: coord2, sha256: String(repeating: "2", count: 64), data: data)
        XCTAssertNotNil(cache.tile(region: "uk", publishVersion: "20260716T155409Z", coordinate: coord1, sha256: String(repeating: "1", count: 64)))
        let reopened = try TileCache(directory: directory, maxBytes: 25)
        try reopened.storeTile(region: "uk", publishVersion: "20260716T155409Z", coordinate: coord3, sha256: String(repeating: "3", count: 64), data: data)

        XCTAssertNotNil(reopened.tile(region: "uk", publishVersion: "20260716T155409Z", coordinate: coord1, sha256: String(repeating: "1", count: 64)))
        XCTAssertNil(reopened.tile(region: "uk", publishVersion: "20260716T155409Z", coordinate: coord2, sha256: String(repeating: "2", count: 64)))
        XCTAssertNotNil(reopened.tile(region: "uk", publishVersion: "20260716T155409Z", coordinate: coord3, sha256: String(repeating: "3", count: 64)))
    }

    func testRegionIndexRejectsUnsafeIDsBeforeFetchPathComposition() throws {
        var object = regionIndexObject()
        object["regions"] = [
            regionIndexEntry(["id": "../uk"]),
        ]

        XCTAssertThrowsError(try RegionIndex.decode(jsonData(object))) {
            XCTAssertEqual($0 as? TileError, .invalidRegionIndex)
        }
    }

    func testRegionIndexRejectsHostileShapesAndFutureReaders() throws {
        var duplicate = regionIndexObject()
        duplicate["regions"] = [regionIndexEntry(), regionIndexEntry()]
        var unknownKey = regionIndexObject()
        unknownKey["extra"] = true
        var badParent = regionIndexObject()
        badParent["regions"] = [regionIndexEntry(["parent": "missing"])]
        var badBBox = regionIndexObject()
        badBBox["regions"] = [regionIndexEntry(["bbox": [1.0, 49.84, -8.65, 60.86]])]
        var badNumbers = regionIndexObject()
        badNumbers["regions"] = [regionIndexEntry(["bytes_with_thumbnails": 1_000_000])]
        var unsafeText = regionIndexObject()
        unsafeText["regions"] = [regionIndexEntry(["display_name": "United\u{202E}Kingdom"])]
        var futureReader = regionIndexObject()
        futureReader["min_reader_version"] = VersionGate.readerVersion + 1

        for object in [duplicate, unknownKey, badParent, badBBox, badNumbers, unsafeText, futureReader] {
            XCTAssertThrowsError(try RegionIndex.decode(jsonData(object))) {
                XCTAssertEqual($0 as? TileError, .invalidRegionIndex)
            }
        }
        XCTAssertThrowsError(try RegionIndex.decode(Data(repeating: 0x20, count: RegionIndex.maxBytes + 1))) {
            XCTAssertEqual($0 as? TileError, .invalidRegionIndex)
        }
    }

    func testRegionIndexAcceptsPublishVersionsAndBoundedFootprints() throws {
        let index = try RegionIndex.decode(jsonData(regionIndexObject()))

        XCTAssertEqual(index.regions.map(\.id), ["uk"])
        XCTAssertEqual(index.regions.first?.publishVersion, "20260716T155409Z")
        XCTAssertEqual(index.regions.first?.bbox, BBox(minLon: -8.65, minLat: 49.84, maxLon: 1.77, maxLat: 60.86))
        XCTAssertEqual(index.regions.first?.bytesWithThumbnails, 2_500_000)
    }

    func testOfflinePackInstallRejectsTileShaMismatchWithoutInstallingPack() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let goodTile = try gzipJSON(tileObject(places: [validPlace()]))
        var badTile = goodTile
        badTile[10] ^= 0xff
        let basemap = Data("basemap".utf8)
        let publish = cachedPublish(
            "20260716T155409Z",
            tileSHA: sha256(goodTile),
            tileBytes: goodTile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )

        XCTAssertThrowsError(try store.install(publish: publish, tiles: [TileCoordinate(z: 10, x: 511, y: 340): badTile], basemap: basemap)) {
            XCTAssertEqual($0 as? TileError, .checksumMismatch)
        }
        XCTAssertNil(try store.installedPublish(region: "uk"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: sha256(goodTile)).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineBasemapObjectURL(root: root, sha: sha256(basemap)).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("tmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineCurrentPackURL(root: root, region: "uk").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.packURL(region: "uk", publishVersion: "20260716T155409Z").path))
    }

    func testOfflinePackInstallRejectsBasemapShaMismatchWithoutInstallingPack() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let publish = cachedPublish(
            "20260716T155409Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: String(repeating: "9", count: 64),
            basemapBytes: basemap.count,
            attributionSources: []
        )

        XCTAssertThrowsError(try store.install(publish: publish, tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile], basemap: basemap)) {
            XCTAssertEqual($0 as? TileError, .checksumMismatch)
        }
        XCTAssertNil(try store.installedPublish(region: "uk"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineCurrentPackURL(root: root, region: "uk").path))
    }

    func testOfflinePackPlanReusesUnchangedTileShaAcrossPublishVersions() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let tileSHA = sha256(tile)
        let newTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let newTileSHA = sha256(newTile)
        let basemap = Data("basemap".utf8)
        let basemapSHA = sha256(basemap)
        let installed = cachedPublish(
            "20260716T155409Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: basemapSHA,
            basemapBytes: basemap.count,
            attributionSources: []
        )
        try store.install(publish: installed, tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile], basemap: basemap)

        var targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: basemapSHA,
            basemapBytes: basemap.count,
            attributionSources: []
        )
        targetObject["tiles"] = [
            ["x": 511, "y": 340, "sha256": tileSHA, "bytes": tile.count],
            ["x": 512, "y": 340, "sha256": newTileSHA, "bytes": newTile.count],
        ]
        targetObject["counts"] = ["total": 2, "by_tier": [2, 0, 0, 0]]
        let targetManifest = try Manifest.decode(jsonData(targetObject))
        let target = PinnedPublish(region: "uk", publishVersion: "20260717T000000Z", manifest: targetManifest)

        let plan = try store.updatePlan(for: target)

        XCTAssertEqual(plan.reusedTileCount, 1)
        XCTAssertEqual(plan.tilesToFetch, [OfflineTileFetch(coordinate: TileCoordinate(z: 10, x: 512, y: 340), sha256: newTileSHA, bytes: newTile.count)])
        XCTAssertFalse(plan.basemapNeedsFetch)

        try store.install(publish: target, tiles: [TileCoordinate(z: 10, x: 512, y: 340): newTile], basemap: nil)
        XCTAssertEqual(try store.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
        XCTAssertNotNil(store.tile(region: "uk", publishVersion: "20260717T000000Z", coordinate: TileCoordinate(z: 10, x: 511, y: 340), sha256: tileSHA))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.packURL(region: "uk", publishVersion: "20260716T155409Z").path))
    }

    func testOfflinePackDirectoryIsExcludedFromBackupAndDeleteRemovesRegion() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let publish = cachedPublish(
            "20260716T155409Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )

        try store.install(publish: publish, tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile], basemap: basemap)
        let pack = store.packURL(region: "uk", publishVersion: "20260716T155409Z")
        let values = try pack.resourceValues(forKeys: Set<URLResourceKey>([.isExcludedFromBackupKey]))
        XCTAssertEqual(values.isExcludedFromBackup, true)

        try store.delete(region: "uk")
        XCTAssertNil(try store.installedPublish(region: "uk"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.regionURL(region: "uk").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: sha256(tile)).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineBasemapObjectURL(root: root, sha: sha256(basemap)).path))
    }

    func testDiscardInProgressDownloadsPreservesInstalledPack() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let tileSHA = sha256(tile)
        let basemap = Data("basemap".utf8)
        let basemapSHA = sha256(basemap)
        let publish = cachedPublish(
            "20260716T155409Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: basemapSHA,
            basemapBytes: basemap.count,
            attributionSources: []
        )
        try store.install(publish: publish, tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile], basemap: basemap)
        let inProgressIndex = offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z")
        try FileManager.default.createDirectory(at: inProgressIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: inProgressIndex)
        let abandonedObject = Data("abandoned".utf8)
        let abandonedSHA = sha256(abandonedObject)
        try FileManager.default.createDirectory(at: offlineTileObjectURL(root: root, sha: abandonedSHA).deletingLastPathComponent(), withIntermediateDirectories: true)
        try abandonedObject.write(to: offlineTileObjectURL(root: root, sha: abandonedSHA))

        try store.discardInProgressDownloads(region: "uk")

        XCTAssertEqual(try store.installedPublish(region: "uk")?.publishVersion, "20260716T155409Z")
        XCTAssertFalse(FileManager.default.fileExists(atPath: inProgressIndex.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: tileSHA).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineBasemapObjectURL(root: root, sha: basemapSHA).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: abandonedSHA).path))
    }

    func testOfflinePackInstallReplacesCorruptExistingObjectsByHash() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let tileSHA = sha256(tile)
        let basemapSHA = sha256(basemap)
        try FileManager.default.createDirectory(at: offlineTileObjectURL(root: root, sha: tileSHA).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: offlineBasemapObjectURL(root: root, sha: basemapSHA).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: offlineTileObjectURL(root: root, sha: tileSHA))
        try Data("corrupt".utf8).write(to: offlineBasemapObjectURL(root: root, sha: basemapSHA))
        let publish = cachedPublish(
            "20260716T155409Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: basemapSHA,
            basemapBytes: basemap.count,
            attributionSources: []
        )

        try store.install(publish: publish, tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile], basemap: basemap)

        XCTAssertEqual(try Data(contentsOf: offlineTileObjectURL(root: root, sha: tileSHA)), tile)
        XCTAssertEqual(try Data(contentsOf: offlineBasemapObjectURL(root: root, sha: basemapSHA)), basemap)
    }

    func testOfflineStoreTileStagingDoesNotLeaveCorruptFinalObjectOnVerifyFailure() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let goodTile = try gzipJSON(tileObject(places: [validPlace()]))
        var corruptTile = goodTile
        corruptTile[10] ^= 0xff
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("MakingTracksCorruptTileStage-\(UUID().uuidString).json.gz")
        try corruptTile.write(to: source, options: .atomic)

        XCTAssertThrowsError(try store.stageDownloadedTileObject(source, sha256: sha256(goodTile), bytes: corruptTile.count))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: sha256(goodTile)).path))
    }

    func testOfflineStoreDeferredMaintenanceSweepsHiddenBasemapTempsAndRootTmpDirs() throws {
        let root = temporaryOfflineRoot()
        let hiddenBasemapTemp = root.appendingPathComponent("objects/basemaps/.\(UUID().uuidString).pmtiles.tmp")
        let hiddenTileTemp = root.appendingPathComponent("objects/tiles/.\(UUID().uuidString).json.gz.tmp")
        let installTemp = root.appendingPathComponent("tmp/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenBasemapTemp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stranded".utf8).write(to: hiddenBasemapTemp)
        try FileManager.default.createDirectory(at: hiddenTileTemp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stranded".utf8).write(to: hiddenTileTemp)
        try FileManager.default.createDirectory(at: installTemp, withIntermediateDirectories: true)
        try Data("stranded".utf8).write(to: installTemp.appendingPathComponent("pack-index.json"))

        let store = try OfflineRegionStore(root: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: hiddenBasemapTemp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: hiddenTileTemp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installTemp.path))

        try store.performDeferredMaintenance()

        XCTAssertFalse(FileManager.default.fileExists(atPath: hiddenBasemapTemp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hiddenTileTemp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installTemp.path))
    }

    func testOfflineStoreDeferredMaintenanceKeepsRegisteredLiveBasemapTemp() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let liveTemp = root.appendingPathComponent("objects/basemaps/.\(UUID().uuidString).pmtiles.tmp")
        let strandedTemp = root.appendingPathComponent("objects/basemaps/.\(UUID().uuidString).pmtiles.tmp")
        try FileManager.default.createDirectory(at: liveTemp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("live".utf8).write(to: liveTemp)
        try Data("stranded".utf8).write(to: strandedTemp)

        try store.withRegisteredLiveTemporaryObjectForTesting(liveTemp) {
            try store.performDeferredMaintenance()
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: liveTemp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: strandedTemp.path))
    }

    func testOfflineStoreDeferredMaintenanceRecoversSameVersionReinstallBackupWindow() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let publish = cachedPublish(
            "20260716T155409Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        try store.install(publish: publish, tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile], basemap: basemap)
        let final = store.packURL(region: "uk", publishVersion: "20260716T155409Z")
        let backup = offlineInstallBackupURL(root: root)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: final, to: backup)

        let relaunched = try OfflineRegionStore(root: root)

        XCTAssertThrowsError(try relaunched.installedPublish(region: "uk"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: final.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))

        try relaunched.performDeferredMaintenance()

        XCTAssertEqual(try relaunched.installedPublish(region: "uk")?.publishVersion, "20260716T155409Z")
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testOfflineStoreDeferredMaintenanceDeletesStaleDecodableBackupWhenCurrentPointsElsewhere() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let oldTile = try gzipJSON(tileObject(places: [validPlace()]))
        let oldBasemap = Data("old-basemap".utf8)
        let oldPublish = cachedPublish(
            "20260716T155409Z",
            tileSHA: sha256(oldTile),
            tileBytes: oldTile.count,
            basemapSHA: sha256(oldBasemap),
            basemapBytes: oldBasemap.count,
            attributionSources: []
        )
        try store.install(publish: oldPublish, tiles: [TileCoordinate(z: 10, x: 511, y: 340): oldTile], basemap: oldBasemap)
        let newTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let newBasemap = Data("new-basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260717T000000Z",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(newTile),
                tileBytes: newTile.count,
                basemapSHA: sha256(newBasemap),
                basemapBytes: newBasemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): newTile],
            basemap: newBasemap
        )
        let oldFinal = store.packURL(region: "uk", publishVersion: "20260716T155409Z")
        let backup = offlineInstallBackupURL(root: root)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: oldFinal, to: backup)

        let relaunched = try OfflineRegionStore(root: root)
        try relaunched.performDeferredMaintenance()

        XCTAssertEqual(try relaunched.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFinal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testOfflineStoreLaunchSkipsCorruptCurrentPackIndexAndStillOpens() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let tileSHA = sha256(tile)
        let basemapSHA = sha256(basemap)
        try store.install(
            publish: cachedPublish("20260716T155409Z", tileSHA: tileSHA, tileBytes: tile.count, basemapSHA: basemapSHA, basemapBytes: basemap.count, attributionSources: []),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile],
            basemap: basemap
        )
        try Data("{".utf8).write(to: offlinePackIndexURL(root: root, region: "uk", publishVersion: "20260716T155409Z"))

        let relaunched = try OfflineRegionStore(root: root)
        let resolution = try relaunched.installedTileResolution(intersecting: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51))

        XCTAssertEqual(resolution.tiles, [])
        XCTAssertEqual(resolution.quarantinedPacks.map(\.region), ["uk"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: tileSHA).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineBasemapObjectURL(root: root, sha: basemapSHA).path))
    }

    func testOfflineStoreDeferredMaintenanceSkipsFinalObjectGCWhenCurrentMetadataCannotBeRead() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let tileSHA = sha256(tile)
        let basemapSHA = sha256(basemap)
        let unreferencedTileSHA = String(repeating: "a", count: 64)
        let unreferencedBasemapSHA = String(repeating: "b", count: 64)
        let hiddenTileTemp = root.appendingPathComponent("objects/tiles/.\(UUID().uuidString).json.gz.tmp")
        try store.install(
            publish: cachedPublish("20260716T155409Z", tileSHA: tileSHA, tileBytes: tile.count, basemapSHA: basemapSHA, basemapBytes: basemap.count, attributionSources: []),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile],
            basemap: basemap
        )
        let unreferencedTile = offlineTileObjectURL(root: root, sha: unreferencedTileSHA)
        let unreferencedBasemap = offlineBasemapObjectURL(root: root, sha: unreferencedBasemapSHA)
        try Data("unreferenced tile".utf8).write(to: unreferencedTile)
        try Data("unreferenced basemap".utf8).write(to: unreferencedBasemap)
        try FileManager.default.createDirectory(at: hiddenTileTemp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stranded".utf8).write(to: hiddenTileTemp)
        try Data("{".utf8).write(to: offlineCurrentPackURL(root: root, region: "uk"))

        let relaunched = try OfflineRegionStore(root: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: hiddenTileTemp.path))

        try relaunched.performDeferredMaintenance()

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: tileSHA).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineBasemapObjectURL(root: root, sha: basemapSHA).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unreferencedTile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unreferencedBasemap.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hiddenTileTemp.path))
    }

    func testOfflineStoreDeferredMaintenanceSkipsFinalObjectGCWhenManifestSnapshotCannotBeRead() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let tileSHA = sha256(tile)
        let basemapSHA = sha256(basemap)
        let unreferencedTileSHA = String(repeating: "c", count: 64)
        let unreferencedBasemapSHA = String(repeating: "d", count: 64)
        let hiddenTileTemp = root.appendingPathComponent("objects/tiles/.\(UUID().uuidString).json.gz.tmp")
        try store.install(
            publish: cachedPublish("20260716T155409Z", tileSHA: tileSHA, tileBytes: tile.count, basemapSHA: basemapSHA, basemapBytes: basemap.count, attributionSources: []),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile],
            basemap: basemap
        )
        let unreferencedTile = offlineTileObjectURL(root: root, sha: unreferencedTileSHA)
        let unreferencedBasemap = offlineBasemapObjectURL(root: root, sha: unreferencedBasemapSHA)
        try Data("unreferenced tile".utf8).write(to: unreferencedTile)
        try Data("unreferenced basemap".utf8).write(to: unreferencedBasemap)
        try FileManager.default.createDirectory(at: hiddenTileTemp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stranded".utf8).write(to: hiddenTileTemp)
        try Data("{".utf8).write(
            to: root.appendingPathComponent("packs/uk/20260716T155409Z/manifest-snapshot.json")
        )

        let relaunched = try OfflineRegionStore(root: root)
        try relaunched.performDeferredMaintenance()

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: tileSHA).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineBasemapObjectURL(root: root, sha: basemapSHA).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unreferencedTile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unreferencedBasemap.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hiddenTileTemp.path))
    }

    func testOfflineStoreDeferredMaintenanceKeepsUndecodableBackupDirectory() throws {
        let root = temporaryOfflineRoot()
        let backup = offlineInstallBackupURL(root: root)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: backup.appendingPathComponent("manifest-snapshot.json"))

        let store = try OfflineRegionStore(root: root)
        try store.performDeferredMaintenance()

        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    func testOfflineDownloaderBeginDownloadSweepsNewStrandedTemps() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let hiddenBasemapTemp = root.appendingPathComponent("objects/basemaps/.\(UUID().uuidString).pmtiles.tmp")
        let hiddenTileTemp = root.appendingPathComponent("objects/tiles/.\(UUID().uuidString).json.gz.tmp")
        let installTemp = root.appendingPathComponent("tmp/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenBasemapTemp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stranded".utf8).write(to: hiddenBasemapTemp)
        try FileManager.default.createDirectory(at: hiddenTileTemp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stranded".utf8).write(to: hiddenTileTemp)
        try FileManager.default.createDirectory(at: installTemp, withIntermediateDirectories: true)
        try Data("stranded".utf8).write(to: installTemp.appendingPathComponent("pack-index.json"))
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
        ])
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded without object routes")
        } catch let error as URLError where error.code == .notConnectedToInternet {
        } catch {
            XCTFail("expected object fetch failure, got \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hiddenBasemapTemp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hiddenTileTemp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installTemp.path))
    }

    func testBackgroundDownloadConfigurationIsWifiPreferredAndSendsLaunchEvents() {
        let configuration = OfflineDownloadSession.backgroundConfiguration(identifier: "app.making-tracks.tests.offline")

        XCTAssertEqual(configuration.identifier, "app.making-tracks.tests.offline")
        XCTAssertTrue(configuration.sessionSendsLaunchEvents)
        XCTAssertFalse(configuration.isDiscretionary)
        XCTAssertTrue(configuration.waitsForConnectivity)
        XCTAssertFalse(configuration.allowsExpensiveNetworkAccess)
        XCTAssertFalse(configuration.allowsConstrainedNetworkAccess)
        XCTAssertNil(configuration.httpAdditionalHeaders)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
    }

    func testOfflineDownloadConfigurationsCanAllowCellularWhenUserOptedIn() {
        let foreground = OfflineDownloadSession.foregroundConfiguration(allowsCellularDownloads: true)
        let background = OfflineDownloadSession.backgroundConfiguration(
            identifier: "app.making-tracks.tests.offline.cellular",
            allowsCellularDownloads: true
        )

        XCTAssertTrue(foreground.allowsExpensiveNetworkAccess)
        XCTAssertTrue(foreground.allowsConstrainedNetworkAccess)
        XCTAssertTrue(background.allowsExpensiveNetworkAccess)
        XCTAssertTrue(background.allowsConstrainedNetworkAccess)
        XCTAssertEqual(background.identifier, "app.making-tracks.tests.offline.cellular")
    }

    func testForegroundDownloadConfigurationWaitsForConnectivityAndCarriesNoAmbientState() {
        let configuration = OfflineDownloadSession.foregroundConfiguration()

        XCTAssertNil(configuration.identifier)
        XCTAssertTrue(configuration.waitsForConnectivity)
        XCTAssertFalse(configuration.allowsExpensiveNetworkAccess)
        XCTAssertFalse(configuration.allowsConstrainedNetworkAccess)
        XCTAssertNil(configuration.httpAdditionalHeaders)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
    }

    func testOfflineDownloaderSurfacesConnectivityWaitingProgress() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let tileSHA = sha256(tile)
        let basemapSHA = sha256(basemap)
        let manifest = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: basemapSHA,
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let fetcher = ConnectivityWaitingFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(manifest),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let recorder = ProgressRecorder()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        _ = try await downloader.downloadCurrentRegion { progress in
            recorder.append(progress)
        }

        XCTAssertTrue(recorder.events.contains(where: { $0.isWaitingForConnectivity }))
        let metadataWait = try XCTUnwrap(recorder.events.first)
        XCTAssertTrue(metadataWait.isWaitingForConnectivity)
        XCTAssertEqual(metadataWait.publishVersion, "")
        XCTAssertEqual(metadataWait.completedBytes, 0)
        XCTAssertEqual(metadataWait.totalBytes, 0)
        XCTAssertEqual(metadataWait.completedObjectCount, 0)
        XCTAssertEqual(metadataWait.totalObjectCount, 0)
        XCTAssertEqual(recorder.events.last?.isWaitingForConnectivity, false)
    }

    func testOfflineDownloaderClearsConnectivityWaitingWhenTransferReceivesBytes() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let tileSHA = sha256(tile)
        let basemapSHA = sha256(basemap)
        let manifest = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: basemapSHA,
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let fetcher = ConnectivityWaitingFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(manifest),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let recorder = ProgressRecorder()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        _ = try await downloader.downloadCurrentRegion { progress in
            recorder.append(progress)
        }

        let transition = recorder.events.map(\.isWaitingForConnectivity)
        XCTAssertEqual(Array(transition.prefix(4)), [true, false, true, false])
    }

    func testOfflineDownloaderReportsBytesDuringLargeObjectTransfer() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data(repeating: 0x42, count: 1_000)
        let tileSHA = sha256(tile)
        let basemapSHA = sha256(basemap)
        let manifest = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: basemapSHA,
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let fetcher = ProgressReportingFetcher(
            routes: [
                "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
                "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(manifest),
                "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
                "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
            ],
            downloadProgress: [
                "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": [250, 500, 750],
            ]
        )
        let recorder = ProgressRecorder()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        _ = try await downloader.downloadCurrentRegion { progress in
            recorder.append(progress)
        }

        let totalBytes = tile.count + basemap.count
        XCTAssertTrue(recorder.events.contains {
            $0.completedBytes == tile.count + 250
                && $0.totalBytes == totalBytes
                && $0.completedObjectCount == 1
                && $0.totalObjectCount == 2
        })
        XCTAssertTrue(recorder.events.contains {
            $0.completedBytes == tile.count + 750
                && $0.fractionComplete < 1
        })
        XCTAssertEqual(recorder.events.last?.completedBytes, totalBytes)
    }

    func testOfflineBackgroundFetcherUsesBackgroundConfigurationIdentifier() {
        let fetcher = HTTPTileFetcher.offlineBackground(identifier: "app.making-tracks.tests.offline")

        XCTAssertEqual(fetcher.configurationIdentifier, "app.making-tracks.tests.offline")
    }

    func testOfflineBackgroundFetcherDownloadStartsWithoutAsyncConvenienceAPI() async throws {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        let configuration = OfflineDownloadSession.backgroundConfiguration(identifier: identifier)
        configuration.timeoutIntervalForRequest = 1
        configuration.timeoutIntervalForResource = 1
        configuration.connectionProxyDictionary = [
            "HTTPEnable": true,
            "HTTPProxy": "192.0.2.1",
            "HTTPPort": 9,
            "HTTPSEnable": true,
            "HTTPSProxy": "192.0.2.1",
            "HTTPSPort": 9,
        ]
        let fetcher = HTTPTileFetcher(configuration: configuration)
        defer { OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier) }
        let task = Task {
            try await fetcher.download(URL(string: "https://tiles.making-tracks.app/uk/current.json")!)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("background download unexpectedly completed before cancellation")
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            XCTFail("expected cancellation after background task startup, got \(error)")
        }
    }

    func testOfflineBackgroundFetcherRefusesMetadataFetchWithoutAsyncConvenienceAPI() async throws {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        let fetcher = HTTPTileFetcher.offlineBackground(identifier: identifier)
        defer { OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier) }

        do {
            _ = try await fetcher.fetch(URL(string: "https://tiles.making-tracks.app/uk/current.json")!)
            XCTFail("background fetch unexpectedly reached the URLSession data task path")
        } catch TileError.invalidBackgroundFetch {
        } catch {
            XCTFail("expected invalidBackgroundFetch, got \(error)")
        }
    }

    func testSingleFetcherDownloaderRefusesBackgroundFetcherForMetadata() async throws {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        let fetcher = HTTPTileFetcher.offlineBackground(identifier: identifier)
        defer { OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier) }
        let downloader = OfflineRegionDownloader(
            region: "uk",
            fetcher: fetcher,
            store: try OfflineRegionStore(root: temporaryOfflineRoot()),
            availableBytes: { 10_000_000_000 }
        )

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("single-fetcher downloader unexpectedly used a background fetcher for metadata")
        } catch TileError.invalidBackgroundFetch {
        } catch {
            XCTFail("expected invalidBackgroundFetch, got \(error)")
        }
    }

    func testOfflineBackgroundFetcherReusesSessionForIdentifier() {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        defer { OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier) }

        let first = HTTPTileFetcher.offlineBackground(identifier: identifier)
        let second = HTTPTileFetcher.offlineBackground(identifier: identifier)

        XCTAssertTrue(first.sharesSession(with: second))
    }

    func testOfflineBackgroundFetcherUsesPreparedPolicyAfterIdleSessionPolicyChange() async {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        defer { OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier) }

        let wifiOnly = HTTPTileFetcher.offlineBackground(
            identifier: identifier,
            allowsCellularDownloads: false
        )
        await OfflineDownloadSession.prepareBackgroundSessionForPolicyChange(
            identifier: identifier,
            allowsCellularDownloads: true
        )
        let cellularAllowed = HTTPTileFetcher.offlineBackground(
            identifier: identifier,
            allowsCellularDownloads: true
        )

        XCTAssertFalse(wifiOnly.allowsCellularDownloadsForTesting)
        XCTAssertTrue(cellularAllowed.allowsCellularDownloadsForTesting)
        XCTAssertEqual(cellularAllowed.configurationIdentifier, identifier)
    }

    func testBackgroundPolicyPrepareDoesNotInvalidateLeasedSessionBetweenObjectTasks() async {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        defer { OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier) }

        await OfflineDownloadSession.prepareBackgroundSessionForPolicyChange(
            identifier: identifier,
            allowsCellularDownloads: true
        )
        await OfflineDownloadSession.withBackgroundSessionUse(identifier: identifier) {
            let cellularAllowed = HTTPTileFetcher.offlineBackground(
                identifier: identifier,
                allowsCellularDownloads: true
            )
            await OfflineDownloadSession.prepareBackgroundSessionForPolicyChange(
                identifier: identifier,
                allowsCellularDownloads: false
            )
            let stillCellularAllowed = HTTPTileFetcher.offlineBackground(
                identifier: identifier,
                allowsCellularDownloads: false
            )

            XCTAssertTrue(cellularAllowed.sharesSession(with: stillCellularAllowed))
            XCTAssertTrue(stillCellularAllowed.allowsCellularDownloadsForTesting)
        }

        await OfflineDownloadSession.prepareBackgroundSessionForPolicyChange(
            identifier: identifier,
            allowsCellularDownloads: false
        )
        let wifiOnly = HTTPTileFetcher.offlineBackground(
            identifier: identifier,
            allowsCellularDownloads: false
        )
        XCTAssertFalse(wifiOnly.allowsCellularDownloadsForTesting)
    }

    func testBackgroundPolicyPrepareDoesNotInvalidateSessionWithAdoptableSystemTask() async {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        defer { OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier) }
        let wifiOnly = HTTPTileFetcher.offlineBackground(
            identifier: identifier,
            allowsCellularDownloads: false
        )
        let task = wifiOnly.downloadTaskForTesting(
            URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles")!
        )
        defer { task.cancel() }

        await OfflineDownloadSession.prepareBackgroundSessionForPolicyChange(
            identifier: identifier,
            allowsCellularDownloads: true
        )
        let stillWifiOnly = HTTPTileFetcher.offlineBackground(
            identifier: identifier,
            allowsCellularDownloads: true
        )

        XCTAssertTrue(wifiOnly.sharesSession(with: stillWifiOnly))
        XCTAssertFalse(stillWifiOnly.allowsCellularDownloadsForTesting)
    }

    func testBackgroundPolicyPrepareDoesNotInvalidateSessionWithPendingEventsHandler() async throws {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        let wifiOnly = HTTPTileFetcher.offlineBackground(
            identifier: identifier,
            allowsCellularDownloads: false
        )
        let counter = CallbackCounter()
        OfflineDownloadSession.handleEvents(for: identifier) {
            counter.increment()
        }
        defer {
            OfflineDownloadSession.finishEvents(for: identifier)
            OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier)
        }

        await OfflineDownloadSession.prepareBackgroundSessionForPolicyChange(
            identifier: identifier,
            allowsCellularDownloads: true
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        let stillWifiOnly = HTTPTileFetcher.offlineBackground(
            identifier: identifier,
            allowsCellularDownloads: true
        )

        XCTAssertTrue(wifiOnly.sharesSession(with: stillWifiOnly))
        XCTAssertFalse(stillWifiOnly.allowsCellularDownloadsForTesting)
        XCTAssertEqual(counter.count, 0)
    }

    func testDelegateTreatsAdoptedBackgroundTaskAsTrackedForPolicyIdleness() {
        let delegate = RedirectDelegate()
        let requestURL = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles")!

        delegate.markAdoptedForTesting(taskIdentifier: 42, url: requestURL)

        XCTAssertTrue(delegate.hasTrackedTasks())
    }

    func testBackgroundDownloadStagerMovesDelegateTempFileToOwnedPath() throws {
        let root = temporaryOfflineRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let delegateTempURL = root.appendingPathComponent("delegate.tmp")
        try Data("background body".utf8).write(to: delegateTempURL)

        let stagedURL = try BackgroundDownloadFileStager.stage(delegateTempURL)
        defer { try? FileManager.default.removeItem(at: stagedURL) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: delegateTempURL.path))
        XCTAssertEqual(try Data(contentsOf: stagedURL), Data("background body".utf8))
    }

    func testBackgroundDownloadCompletionValidatesStagedFile() throws {
        let root = temporaryOfflineRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stagedURL = root.appendingPathComponent("staged.tmp")
        try Data("background body".utf8).write(to: stagedURL)
        let response = HTTPURLResponse(
            url: URL(string: "https://tiles.making-tracks.app/uk/current.json")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try BackgroundDownloadCompletion.validate(
            stagedURL: stagedURL,
            response: response,
            taskError: nil,
            stagingError: nil
        )

        XCTAssertEqual(result, stagedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    func testBackgroundDownloadCompletionRemovesStagedFileOnMissingResponseAndHTTPFailure() throws {
        let root = temporaryOfflineRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let missingResponseURL = root.appendingPathComponent("missing-response.tmp")
        try Data("body".utf8).write(to: missingResponseURL)

        XCTAssertThrowsError(
            try BackgroundDownloadCompletion.validate(
                stagedURL: missingResponseURL,
                response: nil,
                taskError: nil,
                stagingError: nil
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingResponseURL.path))

        let httpFailureURL = root.appendingPathComponent("http-failure.tmp")
        try Data("body".utf8).write(to: httpFailureURL)
        let response = HTTPURLResponse(
            url: URL(string: "https://tiles.making-tracks.app/uk/current.json")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!

        XCTAssertThrowsError(
            try BackgroundDownloadCompletion.validate(
                stagedURL: httpFailureURL,
                response: response,
                taskError: nil,
                stagingError: nil
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: httpFailureURL.path))
    }

    func testBackgroundDownloadCompletionRemovesStagedFileOnTaskOrStagingError() throws {
        let root = temporaryOfflineRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let taskErrorURL = root.appendingPathComponent("task-error.tmp")
        try Data("body".utf8).write(to: taskErrorURL)

        XCTAssertThrowsError(
            try BackgroundDownloadCompletion.validate(
                stagedURL: taskErrorURL,
                response: nil,
                taskError: URLError(.cancelled),
                stagingError: nil
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskErrorURL.path))

        let stagingErrorURL = root.appendingPathComponent("staging-error.tmp")
        try Data("body".utf8).write(to: stagingErrorURL)
        XCTAssertThrowsError(
            try BackgroundDownloadCompletion.validate(
                stagedURL: stagingErrorURL,
                response: nil,
                taskError: nil,
                stagingError: CocoaError(.fileNoSuchFile)
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingErrorURL.path))
    }

    func testCompletedAttachFailsWhenDelegateAlreadyDeliveredAndStoreIsEmpty() async throws {
        let identifier = "app.making-tracks.tests.offline.completed-empty-\(UUID().uuidString)"
        let requestURL = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles")!
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier)
        }
        let delegate = RedirectDelegate()
        let task = syntheticCompletedDownloadTask(request: URLRequest(url: requestURL), on: session)
        defer { task.cancel() }
        let result = LockedAsyncResult<URL>()

        let attachTask = Task {
            do {
                result.store(.success(try await delegate.attach(to: task, request: URLRequest(url: requestURL), on: session)))
            } catch {
                result.store(.failure(error))
            }
        }
        defer { attachTask.cancel() }

        for _ in 0..<20 where result.load() == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        switch result.load() {
        case .failure(TileError.invalidBackgroundFetch):
            break
        case .failure(let error):
            XCTFail("expected invalidBackgroundFetch, got \(error)")
        case .success(let url):
            XCTFail("completed attach unexpectedly returned \(url)")
        case nil:
            XCTFail("completed attach hung after delegate terminal delivery with no staged file")
        }
    }

    func testCompletedAttachWaitsForPendingDelegateDeliveryWhenAdoptionMarkerRemains() async throws {
        let identifier = "app.making-tracks.tests.offline.completed-pending-\(UUID().uuidString)"
        let requestURL = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles")!
        let body = Data("delegate basemap".utf8)
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier)
        }
        let response = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let delegate = RedirectDelegate()
        let task = syntheticCompletedDownloadTask(
            request: URLRequest(url: requestURL),
            on: session,
            response: response
        )
        defer { task.cancel() }
        delegate.markAdoptedForTesting(taskIdentifier: task.taskIdentifier, url: requestURL)
        let result = LockedAsyncResult<URL>()

        let attachTask = Task {
            do {
                result.store(.success(try await delegate.attach(to: task, request: URLRequest(url: requestURL), on: session)))
            } catch {
                result.store(.failure(error))
            }
        }
        defer { attachTask.cancel() }

        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertNil(result.load())

        delegate.urlSession(session, downloadTask: task, didFinishDownloadingTo: try stagedObjectFile(body))
        delegate.urlSession(session, task: task, didCompleteWithError: nil)

        for _ in 0..<20 where result.load() == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        switch result.load() {
        case .success(let url):
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertEqual(try Data(contentsOf: url), body)
        case .failure(let error):
            XCTFail("expected delegated completion success, got \(error)")
        case nil:
            XCTFail("completed attach did not resume after pending delegate delivery")
        }
    }

    func testCompletedAttachDoesNotWaitOnStaleMarkerAfterTerminalDelivery() async throws {
        let identifier = "app.making-tracks.tests.offline.completed-stale-\(UUID().uuidString)"
        let requestURL = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles")!
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier)
        }
        let delegate = RedirectDelegate()
        let task = syntheticCompletedDownloadTask(request: URLRequest(url: requestURL), on: session)
        defer { task.cancel() }

        delegate.urlSession(session, task: task, didCompleteWithError: nil)
        delegate.markAdoptedForTesting(taskIdentifier: task.taskIdentifier, url: requestURL)
        let result = LockedAsyncResult<URL>()

        let attachTask = Task {
            do {
                result.store(.success(try await delegate.attach(to: task, request: URLRequest(url: requestURL), on: session)))
            } catch {
                result.store(.failure(error))
            }
        }
        defer { attachTask.cancel() }

        for _ in 0..<20 where result.load() == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        switch result.load() {
        case .failure(TileError.invalidBackgroundFetch):
            break
        case .failure(let error):
            XCTFail("expected invalidBackgroundFetch, got \(error)")
        case .success(let url):
            XCTFail("completed attach unexpectedly returned \(url)")
        case nil:
            XCTFail("completed attach waited on a stale adoption marker after terminal delivery")
        }
    }

    func testUntrackedCompletedBackgroundTaskClearsAdoptionMarkerForPolicyIdleness() {
        let identifier = "app.making-tracks.tests.offline.completed-marker-\(UUID().uuidString)"
        let requestURL = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles")!
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delegate = RedirectDelegate()
        let task = syntheticCompletedDownloadTask(request: URLRequest(url: requestURL), on: session)
        defer { task.cancel() }

        delegate.markAdoptedForTesting(taskIdentifier: task.taskIdentifier, url: requestURL)
        delegate.urlSession(session, task: task, didCompleteWithError: nil)

        XCTAssertFalse(delegate.hasTrackedTasks())
    }

    func testCompletedAttachConsumesStoredCompletedDownload() async throws {
        let identifier = "app.making-tracks.tests.offline.completed-stored-\(UUID().uuidString)"
        let requestURL = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles")!
        let body = Data("stored basemap".utf8)
        try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: identifier,
            url: requestURL,
            fileURL: stagedObjectFile(body),
            response: HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier)
        }
        let delegate = RedirectDelegate()
        let task = syntheticCompletedDownloadTask(request: URLRequest(url: requestURL), on: session)
        defer { task.cancel() }

        let fileURL = try await delegate.attach(to: task, request: URLRequest(url: requestURL), on: session)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(try Data(contentsOf: fileURL), body)
        XCTAssertNil(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: requestURL))
    }

    func testCompletedBackgroundDownloadStoreRejectsHTTPFailures() throws {
        let identifier = "app.making-tracks.tests.offline.completed-failure"
        let url = URL(string: "https://tiles.making-tracks.app/uk/current.json")!
        let stagedURL = try stagedObjectFile(Data("failed body".utf8))
        let response = HTTPURLResponse(
            url: url,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        defer { OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier) }

        XCTAssertThrowsError(try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: identifier,
            url: url,
            fileURL: stagedURL,
            response: response
        )) {
            XCTAssertEqual($0 as? TileError, .httpStatus(500))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertNil(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: url))
    }

    func testCompletedBackgroundDownloadStoreResetsCorruptIndexAndOrphans() throws {
        let identifier = "app.making-tracks.tests.offline.completed-corrupt"
        let url = URL(string: "https://tiles.making-tracks.app/uk/current.json")!
        let orphanName = "123E4567-E89B-12D3-A456-426614174000.download"
        try OfflineDownloadSession.createCompletedDownloadFileForTesting(named: orphanName, data: Data("orphan".utf8))
        try OfflineDownloadSession.replaceCompletedDownloadsIndexForTesting(Data(repeating: 0x7b, count: 1_048_577))
        defer { OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier) }

        XCTAssertNil(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: url))
        XCTAssertFalse(OfflineDownloadSession.hasCompletedDownloadFileForTesting(named: orphanName))
    }

    func testCompletedBackgroundDownloadStoreCapAllowsLargestManifestBasemap() {
        XCTAssertGreaterThanOrEqual(
            OfflineDownloadSession.completedDownloadStoreMaxBytesForTesting,
            3_221_225_472
        )
    }

    func testCompletedBackgroundDownloadStoreCanRestoreConsumedEntry() throws {
        let identifier = OfflineDownloadSession.backgroundIdentifier(region: "uk")
        let url = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: identifier,
            url: url,
            fileURL: stagedObjectFile(Data("basemap".utf8)),
            response: response
        )
        defer { OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier) }
        let consumedURL = try XCTUnwrap(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: url))

        OfflineDownloadSession.restoreConsumedCompletedDownload(identifier: identifier, url: url, fileURL: consumedURL)

        let restoredURL = try XCTUnwrap(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: url))
        XCTAssertEqual(restoredURL, consumedURL)
        try? FileManager.default.removeItem(at: restoredURL)
    }

    func testBackgroundSessionFinishEventsCallCompletionOnMainThread() {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        defer { OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier) }
        let expectation = expectation(description: "completion called")
        OfflineDownloadSession.handleEvents(for: identifier) {
            XCTAssertTrue(Thread.isMainThread)
            expectation.fulfill()
        }
        XCTAssertTrue(OfflineDownloadSession.hasBackgroundSessionForTesting(identifier: identifier))

        OfflineDownloadSession.finishEvents(for: identifier)

        wait(for: [expectation], timeout: 2)
    }

    func testBackgroundHandleEventsBeforeFetcherReusesRegisteredSession() {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        defer { OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier) }
        OfflineDownloadSession.handleEvents(for: identifier) {}

        let first = HTTPTileFetcher.offlineBackground(identifier: identifier)
        let second = HTTPTileFetcher.offlineBackground(identifier: identifier)

        XCTAssertTrue(first.sharesSession(with: second))
    }

    func testBackgroundSessionFinishEventsIgnoreWrongIdentifierAndCallOnce() {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        let fetcher = HTTPTileFetcher.offlineBackground(identifier: identifier)
        defer {
            _ = fetcher
            OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier)
        }
        let expectation = expectation(description: "completion called once")
        expectation.assertForOverFulfill = true
        OfflineDownloadSession.handleEvents(for: identifier) {
            expectation.fulfill()
        }

        OfflineDownloadSession.finishEvents(for: "app.making-tracks.tests.other")
        fetcher.finishBackgroundEventsForTesting()
        fetcher.finishBackgroundEventsForTesting()

        wait(for: [expectation], timeout: 2)
    }

    func testBackgroundSessionDelegateFinishEventsCallStoredCompletion() {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        let fetcher = HTTPTileFetcher.offlineBackground(identifier: identifier)
        defer {
            _ = fetcher
            OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier)
        }
        let expectation = expectation(description: "completion called")
        OfflineDownloadSession.handleEvents(for: identifier) {
            XCTAssertTrue(Thread.isMainThread)
            expectation.fulfill()
        }

        fetcher.finishBackgroundEventsForTesting()

        wait(for: [expectation], timeout: 2)
    }

    func testBackgroundSessionInvalidationFinishesStoredEvents() {
        let identifier = "app.making-tracks.tests.offline.\(UUID().uuidString)"
        _ = HTTPTileFetcher.offlineBackground(identifier: identifier)
        let expectation = expectation(description: "completion called")
        OfflineDownloadSession.handleEvents(for: identifier) {
            expectation.fulfill()
        }

        OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: identifier)

        wait(for: [expectation], timeout: 2)
    }

    func testOfflineFetcherDownloadTaskPathReturnsResponseBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectURLProtocol.self]
        let fetcher = HTTPTileFetcher(configuration: configuration)
        RedirectURLProtocol.reset()
        RedirectURLProtocol.mode = .status(200, location: nil)
        RedirectURLProtocol.responseBody = Data("offline body".utf8)
        defer { RedirectURLProtocol.reset() }

        let fileURL = try await fetcher.download(URL(string: "https://tiles.making-tracks.app/uk/current.json")!)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let data = try Data(contentsOf: fileURL)

        XCTAssertEqual(String(data: data, encoding: .utf8), "offline body")
    }

    func testOfflineFetcherFetchReportsConnectivityAvailableWhenDataArrives() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectURLProtocol.self]
        let fetcher = HTTPTileFetcher(configuration: configuration)
        let availability = CallbackCounter()
        RedirectURLProtocol.reset()
        RedirectURLProtocol.mode = .status(200, location: nil)
        RedirectURLProtocol.responseBody = Data("metadata".utf8)
        defer { RedirectURLProtocol.reset() }

        let data = try await fetcher.fetch(
            URL(string: "https://tiles.making-tracks.app/uk/current.json")!,
            connectivityWaiting: nil,
            connectivityAvailable: {
                availability.increment()
            }
        )

        XCTAssertEqual(String(data: data, encoding: .utf8), "metadata")
        XCTAssertEqual(availability.count, 1)
    }

    func testOfflineFetcherDownloadReportsConnectivityAvailableWhenBytesAreWritten() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectURLProtocol.self]
        let fetcher = HTTPTileFetcher(configuration: configuration)
        let availability = CallbackCounter()
        RedirectURLProtocol.reset()
        RedirectURLProtocol.mode = .status(200, location: nil)
        RedirectURLProtocol.responseBody = Data("offline body".utf8)
        defer { RedirectURLProtocol.reset() }

        let fileURL = try await fetcher.download(
            URL(string: "https://tiles.making-tracks.app/uk/current.json")!,
            connectivityWaiting: nil,
            connectivityAvailable: {
                availability.increment()
            }
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let data = try Data(contentsOf: fileURL)

        XCTAssertEqual(String(data: data, encoding: .utf8), "offline body")
        XCTAssertEqual(availability.count, 1)
    }

    func testOfflineFetcherDownloadTaskPathRejectsRedirectCallbacks() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectURLProtocol.self]
        let fetcher = HTTPTileFetcher(configuration: configuration)
        RedirectURLProtocol.reset()
        RedirectURLProtocol.mode = .redirect(to: "https://evil.example/uk/current.json")
        defer { RedirectURLProtocol.reset() }

        do {
            _ = try await fetcher.download(URL(string: "https://tiles.making-tracks.app/uk/current.json")!)
            XCTFail("302 redirect download unexpectedly succeeded")
        } catch {
            XCTAssertFalse(RedirectURLProtocol.requestedURLs.contains(URL(string: "https://evil.example/uk/current.json")!))
        }
    }

    func testOfflineFetcherDownloadRejectsPostHocOriginMismatch() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectURLProtocol.self]
        let fetcher = HTTPTileFetcher(configuration: configuration)
        RedirectURLProtocol.reset()
        RedirectURLProtocol.mode = .statusFromResponseURL(
            200,
            responseURL: "https://evil.example/uk/current.json"
        )
        RedirectURLProtocol.responseBody = Data("evil body".utf8)
        defer { RedirectURLProtocol.reset() }

        do {
            _ = try await fetcher.download(URL(string: "https://tiles.making-tracks.app/uk/current.json")!)
            XCTFail("download unexpectedly succeeded after final response URL changed origin")
        } catch TileError.untrustedHost {
        } catch {
            XCTFail("expected untrustedHost, got \(error)")
        }
    }

    func testDownloadedFileValidationRemovesTempFileWhenFinalURLIsMissingOrUntrusted() throws {
        let root = temporaryOfflineRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tempURL = root.appendingPathComponent("download.tmp")
        try Data("body".utf8).write(to: tempURL)
        let missingURLResponse = MissingURLHTTPResponse(
            url: URL(string: "https://tiles.making-tracks.app/uk/current.json")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        XCTAssertThrowsError(try HTTPTileFetcher.validateDownloadedFile(tempURL, response: missingURLResponse))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))

        try Data("body".utf8).write(to: tempURL)
        let offOriginResponse = HTTPURLResponse(
            url: URL(string: "https://evil.example/uk/current.json")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        XCTAssertThrowsError(try HTTPTileFetcher.validateDownloadedFile(tempURL, response: offOriginResponse))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testTileClientPrefersInstalledPackForTilesAndBasemap() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace(["source_refs": ["osm:node/5"]])]))
        let basemap = Data("basemap".utf8)
        let publish = cachedPublish(
            "20260716T155409Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: ["osm"]
        )
        try store.install(publish: publish, tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile], basemap: basemap)
        let remoteTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001", "source_refs": ["osm:node/6"]])]))
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(
                tileSHA: sha256(tile),
                tileBytes: tile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: ["osm"]
            ),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz": remoteTile,
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache(), offlineStore: store)

        try await client.refreshPin()
        let places = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)
        let url = await client.basemapURL
        let state = await client.loadState

        XCTAssertEqual(places.map(\.id), ["mt1_00000000000000000000000000"])
        XCTAssertEqual(state, .ok)
        XCTAssertEqual(url?.isFileURL, true)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(url)), basemap)
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz"))
    }

    func testTileClientResolvesViewportAcrossOverlappingInstalledPacks() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let ukTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000000",
            "name": "Country Pack Place",
            "source_refs": ["osm:node/5"],
        ])], x: 511, y: 340))
        let londonTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000001",
            "name": "London Pack Place",
            "lon": 0.05,
            "source_refs": ["osm:node/6"],
        ])], x: 512, y: 340))
        let basemap = Data("basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(ukTile),
                tileBytes: ukTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: ["osm"]
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): ukTile],
            basemap: basemap
        )
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(londonTile),
                tileBytes: londonTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: ["osm"]
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): londonTile],
            basemap: nil
        )
        let client = TileClient(region: "uk", fetcher: StubFetcher(routes: [:]), cache: try temporaryCache(), offlineStore: store)

        let places = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: 0.05, maxLat: 51.51), zoom: 16)
        let state = await client.loadState

        XCTAssertEqual(places.map(\.id), [
            "mt1_00000000000000000000000000",
            "mt1_00000000000000000000000001",
        ])
        XCTAssertEqual(state, .ok)
    }

    func testTileClientUsesInstalledZonePackWhenCountryPackIsAbsent() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let londonTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000001",
            "name": "London Pack Place",
            "lon": 0.05,
            "source_refs": ["osm:node/6"],
        ])], x: 512, y: 340))
        let basemap = Data("london-basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(londonTile),
                tileBytes: londonTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: ["osm"]
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): londonTile],
            basemap: basemap
        )
        let client = TileClient(region: "uk", fetcher: StubFetcher(routes: [:]), cache: try temporaryCache(), offlineStore: store)

        let places = await client.places(inViewport: BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51), zoom: 16)
        let state = await client.loadState
        let url = await client.basemapURL
        let integrity = await client.basemapIntegrity
        let attribution = await client.attribution

        XCTAssertEqual(places.map(\.id), ["mt1_00000000000000000000000001"])
        XCTAssertEqual(state, .ok)
        XCTAssertEqual(url?.isFileURL, true)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(url)), basemap)
        XCTAssertEqual(integrity?.sha256, sha256(basemap))
        XCTAssertEqual(integrity?.bytes, basemap.count)
        XCTAssertEqual(attribution.map(\.source), ["osm"])
    }

    func testTileClientDoesNotFetchParentTileCoveredByInstalledZonePack() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let londonTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000001",
            "name": "Installed Zone Place",
            "lon": 0.05,
            "source_refs": ["osm:node/6"],
        ])], x: 512, y: 340))
        let parentTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000002",
            "name": "Parent Network Place",
            "lon": 0.05,
            "source_refs": ["osm:node/7"],
        ])], x: 512, y: 340))
        let basemap = Data("london-basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(londonTile),
                tileBytes: londonTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: ["osm"]
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): londonTile],
            basemap: basemap
        )
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(parentTile),
                tileBytes: parentTile.count,
                attributionSources: ["osm"]
            ),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/512/340.json.gz": parentTile,
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache(), offlineStore: store)

        let places = await client.places(inViewport: BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51), zoom: 16)

        XCTAssertEqual(places.map(\.id), ["mt1_00000000000000000000000001"])
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/512/340.json.gz"))
    }

    func testTileClientDoesNotFetchParentTileWhenCurrentPackPointerIsCorruptButPackCoversCoordinate() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let londonTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000001",
            "name": "Installed Zone Place",
            "lon": 0.05,
            "source_refs": ["osm:node/6"],
        ])], x: 512, y: 340))
        let parentTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000002",
            "name": "Parent Network Place",
            "lon": 0.05,
            "source_refs": ["osm:node/7"],
        ])], x: 512, y: 340))
        let basemap = Data("london-basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(londonTile),
                tileBytes: londonTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: ["osm"]
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): londonTile],
            basemap: basemap
        )
        try Data("{".utf8).write(to: offlineCurrentPackURL(root: root, region: "uk_london"))
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(parentTile),
                tileBytes: parentTile.count,
                attributionSources: ["osm"]
            ),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/512/340.json.gz": parentTile,
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache(), offlineStore: store)

        let places = await client.places(inViewport: BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51), zoom: 16)
        let state = await client.loadState

        XCTAssertEqual(places, [])
        XCTAssertEqual(state, .manifestInvalid)
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/512/340.json.gz"))
        XCTAssertEqual(store.lastPackQuarantines().map(\.region), ["uk_london"])
        XCTAssertEqual(store.lastPackQuarantines().first?.coordinates, [TileCoordinate(z: 10, x: 512, y: 340)])
    }

    func testTileClientStreamsFallbackForUncoveredCoordinateBesideInstalledZone() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let zoneTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000001",
            "name": "Installed Zone Place",
            "source_refs": ["osm:node/6"],
        ])], x: 511, y: 340))
        let parentCoveredTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000002",
            "name": "Parent Covered Place",
            "source_refs": ["osm:node/7"],
        ])], x: 511, y: 340))
        let parentUncoveredTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000003",
            "name": "Parent Uncovered Place",
            "lon": 0.05,
            "source_refs": ["osm:node/8"],
        ])], x: 512, y: 340))
        let basemap = Data("london-basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(zoneTile),
                tileBytes: zoneTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: ["osm"]
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): zoneTile],
            basemap: basemap
        )
        var manifest = manifestObject(tileSHA: sha256(parentCoveredTile), tileBytes: parentCoveredTile.count, attributionSources: ["osm"])
        manifest["tiles"] = [
            ["x": 511, "y": 340, "sha256": sha256(parentCoveredTile), "bytes": parentCoveredTile.count],
            ["x": 512, "y": 340, "sha256": sha256(parentUncoveredTile), "bytes": parentUncoveredTile.count],
        ]
        manifest["counts"] = ["total": 2, "by_tier": [2, 0, 0, 0]]
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": jsonData(manifest),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz": parentCoveredTile,
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/512/340.json.gz": parentUncoveredTile,
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache(), offlineStore: store)

        let places = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: 0.07, maxLat: 51.51), zoom: 16)

        XCTAssertEqual(places.map(\.id), [
            "mt1_00000000000000000000000001",
            "mt1_00000000000000000000000003",
        ])
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz"))
        XCTAssertTrue(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/512/340.json.gz"))
    }

    func testTileClientPrefersNewerPublishVersionWhenInstalledPacksOverlap() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let olderTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000000",
            "lon": -0.12,
            "category": "older",
        ])], x: 511, y: 340))
        let newerTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000000",
            "lon": 0.05,
            "category": "newer",
        ])], x: 511, y: 340))
        let basemap = Data("basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260715T000000Z",
                region: "uk",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(olderTile),
                tileBytes: olderTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): olderTile],
            basemap: basemap
        )
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(newerTile),
                tileBytes: newerTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): newerTile],
            basemap: nil
        )
        let client = TileClient(region: "uk", fetcher: StubFetcher(routes: [:]), cache: try temporaryCache(), offlineStore: store)

        let places = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)

        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.id, "mt1_00000000000000000000000000")
        XCTAssertEqual(places.first?.lon, 0.05)
        XCTAssertEqual(places.first?.category, "newer")
    }

    func testTileClientPrefersSmallerInstalledPackForEqualVersionOverlap() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let countryTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000000",
            "category": "country",
        ])], x: 511, y: 340))
        let countryOtherTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000001",
            "category": "country",
            "lon": 0.05,
        ])], x: 512, y: 340))
        let zoneTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000000",
            "category": "zone",
        ])], x: 511, y: 340))
        let basemap = Data("basemap".utf8)
        var countryManifest = manifestObject(
            region: "osm_r_zz_country",
            tileSHA: sha256(countryTile),
            tileBytes: countryTile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        countryManifest["tiles"] = [
            ["x": 511, "y": 340, "sha256": sha256(countryTile), "bytes": countryTile.count],
            ["x": 512, "y": 340, "sha256": sha256(countryOtherTile), "bytes": countryOtherTile.count],
        ]
        countryManifest["counts"] = ["total": 2, "by_tier": [2, 0, 0, 0]]
        let countryPublish = PinnedPublish(
            region: "osm_r_zz_country",
            publishVersion: "20260716T155409Z",
            manifest: try Manifest.decode(jsonData(countryManifest))
        )
        try store.install(
            publish: countryPublish,
            tiles: [
                TileCoordinate(z: 10, x: 511, y: 340): countryTile,
                TileCoordinate(z: 10, x: 512, y: 340): countryOtherTile,
            ],
            basemap: basemap
        )
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "osm_r_aa_zone",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(zoneTile),
                tileBytes: zoneTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): zoneTile],
            basemap: nil
        )
        let client = TileClient(region: "uk", fetcher: StubFetcher(routes: [:]), cache: try temporaryCache(), offlineStore: store)

        let places = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)

        XCTAssertEqual(places.first(where: { $0.id == "mt1_00000000000000000000000000" })?.category, "zone")
    }

    func testTileClientUsesDeterministicRegionTieBreakForEqualVersionAndPackSize() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let countryTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000000",
            "category": "country",
        ])], x: 511, y: 340))
        let zoneTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000000",
            "category": "zone",
        ])], x: 511, y: 340))
        let basemap = Data("basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "osm_r_zz_country",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(countryTile),
                tileBytes: countryTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): countryTile],
            basemap: basemap
        )
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "osm_r_aa_zone",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(zoneTile),
                tileBytes: zoneTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): zoneTile],
            basemap: nil
        )
        let client = TileClient(region: "uk", fetcher: StubFetcher(routes: [:]), cache: try temporaryCache(), offlineStore: store)

        let places = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)

        XCTAssertEqual(places.map(\.id), ["mt1_00000000000000000000000000"])
        XCTAssertEqual(places.first?.category, "country")
    }

    func testOfflineStoreBoundsInstalledPackResolution() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        for index in 0...OfflineRegionStore.maxInstalledPackCount {
            let id = "r\(index)"
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("regions/\(id)", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        XCTAssertThrowsError(try store.installedPublishes(intersecting: BBox(minLon: -1, minLat: -1, maxLon: 1, maxLat: 1))) { error in
            XCTAssertEqual(error as? TileError, .invalidOfflinePack)
        }
    }

    func testOfflineStoreBoundsInstalledPackResolutionByDirectoryCountOnly() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()], x: 512, y: 340))
        let basemap = Data("basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(tile),
                tileBytes: tile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): tile],
            basemap: basemap
        )
        let regionsRoot = root.appendingPathComponent("regions", isDirectory: true)
        for index in 0...OfflineRegionStore.maxInstalledPackCount {
            try Data("junk".utf8).write(to: regionsRoot.appendingPathComponent("junk-\(index).tmp"))
        }

        let viewport = BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51)

        XCTAssertEqual(try store.installedPublishes(intersecting: viewport).map(\.region), ["uk_london"])
    }

    func testOfflineStoreResolvesInstalledPacksByManifestCellsNotBasemapBBox() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()], x: 512, y: 340))
        let basemap = Data("shared-parent-basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(tile),
                tileBytes: tile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                basemapBBox: [-8.65, 49.84, 1.77, 60.86],
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): tile],
            basemap: basemap
        )

        let countryWestViewport = BBox(minLon: -1.0, minLat: 51.49, maxLon: -0.9, maxLat: 51.51)
        let londonEastViewport = BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51)

        XCTAssertEqual(try store.installedPublishes(intersecting: countryWestViewport).map(\.region), [])
        XCTAssertEqual(try store.installedPublishes(intersecting: londonEastViewport).map(\.region), ["uk_london"])
    }

    func testOfflineStoreSummarizesInstalledPackSizesWithDeduplicatedTotal() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let ukTile = try gzipJSON(tileObject(places: [validPlace()], x: 511, y: 340))
        let londonTile = try gzipJSON(tileObject(places: [validPlace()], x: 512, y: 340))
        let sharedBasemap = Data("shared-basemap".utf8)

        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(ukTile),
                tileBytes: ukTile.count,
                basemapSHA: sha256(sharedBasemap),
                basemapBytes: sharedBasemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): ukTile],
            basemap: sharedBasemap
        )
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(londonTile),
                tileBytes: londonTile.count,
                basemapSHA: sha256(sharedBasemap),
                basemapBytes: sharedBasemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): londonTile],
            basemap: nil
        )

        let summary = try store.installedPackStorageSummary()

        XCTAssertEqual(summary.packs.map(\.region), ["uk", "uk_london"])
        XCTAssertEqual(summary.packs.map(\.publishVersion), ["20260716T155409Z", "20260716T155409Z"])
        XCTAssertEqual(summary.packs.map(\.tileCount), [1, 1])
        XCTAssertEqual(summary.packs.map(\.tileBytes), [ukTile.count, londonTile.count])
        XCTAssertEqual(summary.packs.map(\.basemapBytes), [sharedBasemap.count, sharedBasemap.count])
        XCTAssertEqual(summary.packs.map(\.referencedBytes), [
            ukTile.count + sharedBasemap.count,
            londonTile.count + sharedBasemap.count,
        ])
        XCTAssertEqual(summary.failedRegions, [])
        XCTAssertEqual(summary.totalBytes, ukTile.count + londonTile.count + sharedBasemap.count)
    }

    func testOfflineStoreFlagsCorruptStorageRegionAndReportsOtherPacks() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let ukTile = try gzipJSON(tileObject(places: [validPlace()], x: 511, y: 340))
        let londonTile = try gzipJSON(tileObject(places: [validPlace()], x: 512, y: 340))
        let sharedBasemap = Data("shared-basemap".utf8)

        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(ukTile),
                tileBytes: ukTile.count,
                basemapSHA: sha256(sharedBasemap),
                basemapBytes: sharedBasemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): ukTile],
            basemap: sharedBasemap
        )
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(londonTile),
                tileBytes: londonTile.count,
                basemapSHA: sha256(sharedBasemap),
                basemapBytes: sharedBasemap.count,
                basemapBBox: [-0.2, 51.45, 0.1, 51.6],
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): londonTile],
            basemap: nil
        )
        try Data("truncated".utf8).write(to: offlineTileObjectURL(root: root, sha: sha256(londonTile)))

        let summary = try store.installedPackStorageSummary()

        XCTAssertEqual(summary.packs.map(\.region), ["uk"])
        XCTAssertEqual(summary.failedRegions, ["uk_london"])
        XCTAssertEqual(summary.totalBytes, ukTile.count + sharedBasemap.count)
    }

    func testOfflineStoreBoundsInstalledPackStorageSummaryByDirectoryCount() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        for index in 0...OfflineRegionStore.maxInstalledPackCount {
            let id = "r\(index)"
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("regions/\(id)", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        XCTAssertThrowsError(try store.installedPackStorageSummary()) { error in
            XCTAssertEqual(error as? TileError, .invalidOfflinePack)
        }
    }

    func testOfflineStoreQuarantinesCorruptSiblingPackDuringInstalledTileResolution() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()], x: 512, y: 340))
        let corruptTile = try gzipJSON(tileObject(places: [validPlace()], x: 511, y: 340))
        let basemap = Data("basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(tile),
                tileBytes: tile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): tile],
            basemap: basemap
        )
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_corrupt",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(corruptTile),
                tileBytes: corruptTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): corruptTile],
            basemap: nil
        )
        try Data("{".utf8).write(to: offlineCurrentPackURL(root: root, region: "uk_corrupt"))

        let viewport = BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51)

        XCTAssertEqual(try store.installedPublishes(intersecting: viewport).map(\.region), ["uk_london"])
        XCTAssertEqual(store.lastPackQuarantines().map(\.region), ["uk_corrupt"])
        XCTAssertEqual(store.lastPackQuarantines().first?.coordinates, [TileCoordinate(z: 10, x: 511, y: 340)])
    }

    func testOfflineStoreQuarantinesOversizeCurrentPackBeforeTrustingIgnoredJSONFields() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()], x: 512, y: 340))
        let basemap = Data("basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: sha256(tile),
                tileBytes: tile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): tile],
            basemap: basemap
        )
        try jsonData([
            "publishVersion": "20260716T155409Z",
            "padding": String(repeating: "x", count: OfflineRegionStore.maxCurrentPackBytes + 1),
        ]).write(to: offlineCurrentPackURL(root: root, region: "uk_london"))

        let resolution = try store.installedTileResolution(intersecting: BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51))

        XCTAssertEqual(resolution.tiles, [])
        XCTAssertEqual(resolution.quarantinedPacks.map(\.region), ["uk_london"])
        XCTAssertEqual(resolution.blockedCoordinates, [TileCoordinate(z: 10, x: 512, y: 340)])
    }

    func testOfflineStoreQuarantinesOversizePackIndexBeforeTrustingIgnoredJSONFields() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()], x: 512, y: 340))
        let basemap = Data("basemap".utf8)
        let tileSHA = sha256(tile)
        let basemapSHA = sha256(basemap)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 512,
                tileY: 340,
                tileSHA: tileSHA,
                tileBytes: tile.count,
                basemapSHA: basemapSHA,
                basemapBytes: basemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 512, y: 340): tile],
            basemap: basemap
        )
        try jsonData([
            "region": "uk_london",
            "publishVersion": "20260716T155409Z",
            "tileSHAs": ["512/340": tileSHA],
            "tiles": ["512/340": ["sha256": tileSHA, "bytes": tile.count]],
            "basemapSHA": basemapSHA,
            "basemapBytes": basemap.count,
            "attribution": [],
            "attributionSources": [],
            "padding": String(repeating: "x", count: OfflineRegionStore.maxOfflinePackIndexBytes + 1),
        ]).write(to: offlinePackIndexURL(root: root, region: "uk_london", publishVersion: "20260716T155409Z"))

        let resolution = try store.installedTileResolution(intersecting: BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51))

        XCTAssertEqual(resolution.tiles, [])
        XCTAssertEqual(resolution.quarantinedPacks.map(\.region), ["uk_london"])
        XCTAssertEqual(resolution.blockedCoordinates, [TileCoordinate(z: 10, x: 512, y: 340)])
    }

    func testOfflineStoreFailsClosedWhenCorruptCurrentPackHasTooManyPublishDirectories() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let regionRoot = root.appendingPathComponent("regions/uk_london", isDirectory: true)
        try FileManager.default.createDirectory(at: regionRoot, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: regionRoot.appendingPathComponent("current-pack.json"))
        let packsRoot = root.appendingPathComponent("packs/uk_london", isDirectory: true)
        for index in 0...OfflineRegionStore.maxInstalledPackCount {
            let publishVersion = String(format: "20260716T%06dZ", index)
            try FileManager.default.createDirectory(
                at: packsRoot.appendingPathComponent(publishVersion, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        XCTAssertThrowsError(
            try store.installedTileResolution(intersecting: BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51))
        ) { error in
            XCTAssertEqual(error as? TileError, .invalidOfflinePack)
        }
    }

    func testTileClientQuarantinesMalformedPackIndexWithoutKillingUncoveredFallback() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let zoneTile = try gzipJSON(tileObject(places: [validPlace()], x: 511, y: 340))
        let parentCoveredTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000001",
            "lon": -0.12,
        ])], x: 511, y: 340))
        let parentTile = try gzipJSON(tileObject(places: [validPlace([
            "place_id": "mt1_00000000000000000000000002",
            "lon": 0.05,
        ])], x: 512, y: 340))
        let basemap = Data("basemap".utf8)
        try store.install(
            publish: cachedPublish(
                "20260716T155409Z",
                region: "uk_london",
                tileX: 511,
                tileY: 340,
                tileSHA: sha256(zoneTile),
                tileBytes: zoneTile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: []
            ),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): zoneTile],
            basemap: basemap
        )
        try jsonData([
            "region": "uk_london",
            "publishVersion": "20260716T155409Z",
            "tileSHAs": [
                "511/340": sha256(zoneTile),
                "512/340": sha256(parentTile),
            ],
            "tiles": [
                "511/340": ["sha256": sha256(zoneTile), "bytes": zoneTile.count],
                "512/340": ["sha256": sha256(parentTile), "bytes": parentTile.count],
            ],
            "basemapSHA": sha256(basemap),
            "basemapBytes": basemap.count,
            "attribution": [],
            "attributionSources": [],
        ]).write(to: offlinePackIndexURL(root: root, region: "uk_london", publishVersion: "20260716T155409Z"))
        var manifest = manifestObject(tileSHA: sha256(parentCoveredTile), tileBytes: parentCoveredTile.count, attributionSources: [])
        manifest["tiles"] = [
            ["x": 511, "y": 340, "sha256": sha256(parentCoveredTile), "bytes": parentCoveredTile.count],
            ["x": 512, "y": 340, "sha256": sha256(parentTile), "bytes": parentTile.count],
        ]
        manifest["counts"] = ["total": 2, "by_tier": [2, 0, 0, 0]]
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": jsonData(manifest),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz": parentCoveredTile,
            "https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/512/340.json.gz": parentTile,
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache(), offlineStore: store)

        let places = await client.places(inViewport: BBox(minLon: 0.03, minLat: 51.49, maxLon: 0.07, maxLat: 51.51), zoom: 16)
        let state = await client.loadState

        XCTAssertEqual(places.map(\.id), ["mt1_00000000000000000000000002"])
        XCTAssertEqual(state, .ok)
        XCTAssertEqual(store.lastPackQuarantines().map(\.region), ["uk_london"])
        XCTAssertEqual(store.lastPackQuarantines().first?.coordinates, [TileCoordinate(z: 10, x: 511, y: 340)])
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz"))
        XCTAssertTrue(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/512/340.json.gz"))
    }

    func testTileClientPreservesUpdateAvailableForInstalledPackAfterCurrentFlipAndOfflineRefresh() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let tileSHA = sha256(tile)
        let basemapSHA = sha256(basemap)
        try store.install(
            publish: cachedPublish("20260716T155409Z", tileSHA: tileSHA, tileBytes: tile.count, basemapSHA: basemapSHA, basemapBytes: basemap.count, attributionSources: []),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): tile],
            basemap: basemap
        )
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": manifestData(
                publishVersion: "20260717T000000Z",
                tileSHA: tileSHA,
                tileBytes: tile.count,
                basemapSHA: basemapSHA,
                basemapBytes: basemap.count,
                attributionSources: []
            ),
        ])
        let client = TileClient(region: "uk", fetcher: fetcher, cache: try temporaryCache(), offlineStore: store)

        try await client.refreshPin()
        let updateState = await client.loadState
        XCTAssertEqual(updateState, .updateAvailable)
        fetcher.routes.removeAll()
        try await client.refreshPin()

        let offlineUpdateState = await client.loadState
        XCTAssertEqual(offlineUpdateState, .updateAvailable)
        let places = await client.places(inViewport: BBox(minLon: -0.13, minLat: 51.49, maxLon: -0.11, maxLat: 51.51), zoom: 16)
        XCTAssertEqual(places.map(\.id), ["mt1_00000000000000000000000000"])
    }

    func testOfflineDownloaderFetchesOnlyChangedObjectsAndInstallsTargetPublish() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let oldTile = try gzipJSON(tileObject(places: [validPlace()]))
        let oldSHA = sha256(oldTile)
        let newTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let newSHA = sha256(newTile)
        let basemap = Data("basemap".utf8)
        let basemapSHA = sha256(basemap)
        try store.install(
            publish: cachedPublish("20260716T155409Z", tileSHA: oldSHA, tileBytes: oldTile.count, basemapSHA: basemapSHA, basemapBytes: basemap.count, attributionSources: []),
            tiles: [TileCoordinate(z: 10, x: 511, y: 340): oldTile],
            basemap: basemap
        )
        var targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: oldSHA,
            tileBytes: oldTile.count,
            basemapSHA: basemapSHA,
            basemapBytes: basemap.count,
            attributionSources: []
        )
        targetObject["tiles"] = [
            ["x": 511, "y": 340, "sha256": oldSHA, "bytes": oldTile.count],
            ["x": 512, "y": 340, "sha256": newSHA, "bytes": newTile.count],
        ]
        targetObject["counts"] = ["total": 2, "by_tier": [2, 0, 0, 0]]
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz": newTile,
        ])
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        let result = try await downloader.downloadCurrentRegion()

        XCTAssertEqual(result.publish.publishVersion, "20260717T000000Z")
        XCTAssertEqual(result.fetchedTileCount, 1)
        XCTAssertEqual(result.reusedTileCount, 1)
        XCTAssertEqual(try store.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"))
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles"))
    }

    func testOfflineDownloaderUsesObjectFetcherForPackObjects() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let currentURL = "https://tiles.making-tracks.app/uk/current.json"
        let manifestURL = "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json"
        let tileURL = "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"
        let basemapURL = "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles"
        let metadataFetcher = StubFetcher(routes: [
            currentURL: jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            manifestURL: manifestData(
                publishVersion: "20260717T000000Z",
                tileSHA: sha256(tile),
                tileBytes: tile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: []
            ),
        ])
        let objectFetcher = StubFetcher(routes: [
            tileURL: tile,
            basemapURL: basemap,
        ])
        let downloader = OfflineRegionDownloader(
            region: "uk",
            metadataFetcher: metadataFetcher,
            objectFetcher: objectFetcher,
            store: store,
            availableBytes: { 10_000_000_000 }
        )

        _ = try await downloader.downloadCurrentRegion()

        XCTAssertEqual(metadataFetcher.requestedURLs, [currentURL, manifestURL])
        XCTAssertEqual(objectFetcher.requestedURLs, [tileURL, basemapURL])
        XCTAssertFalse(objectFetcher.requestedURLs.contains(currentURL))
        XCTAssertFalse(objectFetcher.requestedURLs.contains(manifestURL))
        XCTAssertFalse(metadataFetcher.requestedURLs.contains(tileURL))
        XCTAssertFalse(metadataFetcher.requestedURLs.contains(basemapURL))
        XCTAssertEqual(try store.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
    }

    func testOfflineDownloaderPersistsVerifiedObjectsBeforeInstallAndResumeSkipsThem() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let firstTile = try gzipJSON(tileObject(places: [validPlace()]))
        let firstSHA = sha256(firstTile)
        let secondTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let secondSHA = sha256(secondTile)
        let basemap = Data("basemap".utf8)
        let targetObject = twoTileManifestObject(
            firstSHA: firstSHA,
            firstBytes: firstTile.count,
            secondSHA: secondSHA,
            secondBytes: secondTile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count
        )
        let firstAttempt = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": firstTile,
        ])
        let firstDownloader = OfflineRegionDownloader(region: "uk", fetcher: firstAttempt, store: store, availableBytes: { 10_000_000_000 })

        do {
            _ = try await firstDownloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded with the second tile missing")
        } catch let error as URLError where error.code == .notConnectedToInternet {
        } catch {
            XCTFail("expected interrupted fetch, got \(error)")
        }

        XCTAssertNil(try store.installedPublish(region: "uk"))
        XCTAssertEqual(try Data(contentsOf: offlineTileObjectURL(root: root, sha: firstSHA)), firstTile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        try store.delete(region: "malaysia")
        XCTAssertEqual(try Data(contentsOf: offlineTileObjectURL(root: root, sha: firstSHA)), firstTile)

        let relaunchedStore = try OfflineRegionStore(root: root)
        let resumed = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz": secondTile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let resumedProgress = ProgressRecorder()
        let resumedDownloader = OfflineRegionDownloader(region: "uk", fetcher: resumed, store: relaunchedStore, availableBytes: { 10_000_000_000 })

        let result = try await resumedDownloader.downloadCurrentRegion { event in
            resumedProgress.append(event)
        }

        XCTAssertEqual(result.fetchedTileCount, 1)
        XCTAssertEqual(result.reusedTileCount, 1)
        XCTAssertEqual(try relaunchedStore.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
        XCTAssertFalse(resumed.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"))
        XCTAssertEqual(resumedProgress.events.first?.completedBytes, firstTile.count + secondTile.count)
        XCTAssertEqual(resumedProgress.events.first?.totalBytes, firstTile.count + secondTile.count + basemap.count)
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
    }

    func testOfflineDownloaderConsumesCompletedBackgroundObjectAfterRelaunch() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let tileSHA = sha256(tile)
        let basemap = Data("basemap".utf8)
        let basemapSHA = sha256(basemap)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: basemapSHA,
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let sessionIdentifier = OfflineDownloadSession.backgroundIdentifier(region: "uk")
        let tileURLString = "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"
        let tileURL = URL(string: tileURLString)!
        let response = HTTPURLResponse(
            url: tileURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: sessionIdentifier,
            url: tileURL,
            fileURL: stagedObjectFile(tile),
            response: response
        )
        defer { OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: sessionIdentifier) }
        let metadataFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
        ])
        let objectFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let progress = ProgressRecorder()
        let downloader = OfflineRegionDownloader(
            region: "uk",
            metadataFetcher: metadataFetcher,
            objectFetcher: objectFetcher,
            store: store,
            availableBytes: { 10_000_000_000 }
        )

        let result = try await downloader.downloadCurrentRegion { event in
            progress.append(event)
        }

        XCTAssertEqual(result.fetchedTileCount, 1)
        XCTAssertEqual(result.reusedTileCount, 0)
        XCTAssertEqual(try store.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
        XCTAssertEqual(try Data(contentsOf: offlineTileObjectURL(root: root, sha: tileSHA)), tile)
        XCTAssertFalse(objectFetcher.requestedURLs.contains(tileURLString))
        XCTAssertEqual(progress.events.first?.completedBytes, tile.count)
        XCTAssertEqual(progress.events.last?.completedBytes, tile.count + basemap.count)
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
    }

    func testOfflineDownloaderResumesPendingPublishWhenCurrentMovedAfterRelaunch() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let publish = cachedPublish(
            "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        try store.beginDownload(publish: publish)
        let metadataFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260718T000000Z"]),
        ])
        let objectFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let downloader = OfflineRegionDownloader(
            region: "uk",
            metadataFetcher: metadataFetcher,
            objectFetcher: objectFetcher,
            store: store,
            availableBytes: { 10_000_000_000 }
        )

        let result = try await downloader.downloadCurrentRegion()

        XCTAssertEqual(result.publish.publishVersion, "20260717T000000Z")
        XCTAssertEqual(try store.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
        XCTAssertEqual(metadataFetcher.requestedURLs, [])
    }

    func testOfflineDownloaderDoesNotConsumeCompletedBackgroundObjectWhenAlreadyPaused() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let publish = cachedPublish(
            "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        try store.beginDownload(publish: publish)
        let identifier = OfflineDownloadSession.backgroundIdentifier(region: "uk")
        let url = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: identifier,
            url: url,
            fileURL: stagedObjectFile(tile),
            response: response
        )
        let control = OfflineRegionDownloadControl()
        control.pause()
        let downloader = OfflineRegionDownloader(
            region: "uk",
            metadataFetcher: StubFetcher(routes: [:]),
            objectFetcher: StubFetcher(routes: [
                "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
            ]),
            store: store,
            availableBytes: { 10_000_000_000 }
        )

        do {
            _ = try await downloader.downloadCurrentRegion(control: control)
            XCTFail("download unexpectedly succeeded while paused")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }

        XCTAssertNotNil(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: url))
        OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier)
    }

    func testOfflineDownloaderCanPauseAfterAdoptingCompletedBackgroundObject() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let identifier = OfflineDownloadSession.backgroundIdentifier(region: "uk")
        let tileURLString = "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"
        let tileURL = URL(string: tileURLString)!
        try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: identifier,
            url: tileURL,
            fileURL: stagedObjectFile(tile),
            response: HTTPURLResponse(url: tileURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
        defer { OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier) }
        let objectFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let control = OfflineRegionDownloadControl()
        let downloader = OfflineRegionDownloader(
            region: "uk",
            metadataFetcher: StubFetcher(routes: [
                "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
                "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            ]),
            objectFetcher: objectFetcher,
            store: store,
            availableBytes: { 10_000_000_000 }
        )

        do {
            _ = try await downloader.downloadCurrentRegion(control: control) { progress in
                if progress.completedObjectCount == 1 {
                    control.pause()
                }
            }
            XCTFail("download unexpectedly continued after adopted-object progress pause")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }

        XCTAssertFalse(objectFetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles"))
        XCTAssertNil(try store.installedPublish(region: "uk"))
    }

    func testOfflineDownloaderEmitsPerRegionByteProgressAndCanPause() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let firstTile = try gzipJSON(tileObject(places: [validPlace()]))
        let firstSHA = sha256(firstTile)
        let secondTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let secondSHA = sha256(secondTile)
        let basemap = Data("basemap".utf8)
        let targetObject = twoTileManifestObject(
            firstSHA: firstSHA,
            firstBytes: firstTile.count,
            secondSHA: secondSHA,
            secondBytes: secondTile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count
        )
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": firstTile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz": secondTile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let control = OfflineRegionDownloadControl()
        let progress = ProgressRecorder()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        do {
            _ = try await downloader.downloadCurrentRegion(control: control) { event in
                progress.append(event)
                if event.completedObjectCount == 1 {
                    control.pause()
                }
            }
            XCTFail("download unexpectedly succeeded after pause")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }

        let events = progress.events
        XCTAssertEqual(events.first?.region, "uk")
        XCTAssertEqual(events.first?.publishVersion, "20260717T000000Z")
        XCTAssertEqual(events.first?.completedBytes, firstTile.count)
        XCTAssertEqual(events.first?.totalBytes, firstTile.count + secondTile.count + basemap.count)
        XCTAssertEqual(events.first?.completedObjectCount, 1)
        XCTAssertEqual(events.first?.totalObjectCount, 3)
        XCTAssertEqual(try Data(contentsOf: offlineTileObjectURL(root: root, sha: firstSHA)), firstTile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertNil(try store.installedPublish(region: "uk"))
    }

    func testOfflineDownloaderRechecksHeadroomPerObjectAndPausesResumably() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let tileSHA = sha256(tile)
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let headroom = HeadroomSequence([10_000_000_000, 1])
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { headroom.next() })

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded after per-object headroom loss")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: tileSHA).path))
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"))
    }

    func testOfflineDownloaderRechecksHeadroomBeforeBasemapFetch() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let tileSHA = sha256(tile)
        let basemap = Data("basemap".utf8)
        try store.stageDownloadedTileObject(stagedObjectFile(tile), sha256: tileSHA, bytes: tile.count)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let headroom = HeadroomSequence([10_000_000_000, 1])
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { headroom.next() })

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded after basemap headroom loss")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: tileSHA).path))
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles"))
    }

    func testOfflineDownloaderMapsOutOfSpaceDownloadErrorToResumablePause() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let fetcher = OutOfSpaceDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
        ])
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded after out-of-space write error")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertNil(try store.installedPublish(region: "uk"))
    }

    func testOfflineDownloaderMapsURLSessionUnderlyingENOSPCToResumablePause() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let posixOutOfSpace = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let underlying = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError,
            userInfo: [NSUnderlyingErrorKey: posixOutOfSpace]
        )
        let urlSessionError = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cannotWriteToFile.rawValue,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        let fetcher = OutOfSpaceDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
        ], error: urlSessionError)
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded after URLSession ENOSPC")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertNil(try store.installedPublish(region: "uk"))
    }

    func testOfflineDownloaderResumesAfterENOSPCByReusingPreviouslyStoredObjects() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let firstTile = try gzipJSON(tileObject(places: [validPlace()]))
        let firstSHA = sha256(firstTile)
        let secondTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let secondSHA = sha256(secondTile)
        let basemap = Data("basemap".utf8)
        let secondTileURL = "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz"
        let targetObject = twoTileManifestObject(
            firstSHA: firstSHA,
            firstBytes: firstTile.count,
            secondSHA: secondSHA,
            secondBytes: secondTile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count
        )
        let fetcher = FailingDownloadFetcher(
            routes: [
                "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
                "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
                "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": firstTile,
                secondTileURL: secondTile,
            ],
            failURL: secondTileURL,
            error: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        )
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded after ENOSPC on the second object")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }

        XCTAssertEqual(try Data(contentsOf: offlineTileObjectURL(root: root, sha: firstSHA)), firstTile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertNil(try store.installedPublish(region: "uk"))

        let relaunched = try OfflineRegionStore(root: root)
        let resumed = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz": secondTile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let resumedDownloader = OfflineRegionDownloader(region: "uk", fetcher: resumed, store: relaunched, availableBytes: { 10_000_000_000 })

        _ = try await resumedDownloader.downloadCurrentRegion(resumingPausedDownload: true)

        XCTAssertFalse(resumed.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"))
        XCTAssertEqual(try relaunched.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
    }

    func testOfflineDownloaderRejectsSameRegionDoubleStartInEngine() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let started = expectation(description: "download started")
        let firstFetcher = SlowDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
        ], onDownloadStarted: {
            started.fulfill()
        })
        let secondFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let control = OfflineRegionDownloadControl()
        let first = OfflineRegionDownloader(region: "uk", fetcher: firstFetcher, store: store, availableBytes: { 10_000_000_000 })
        let second = OfflineRegionDownloader(region: "uk", fetcher: secondFetcher, store: store, availableBytes: { 10_000_000_000 })
        let firstTask = Task {
            try await first.downloadCurrentRegion(control: control)
        }
        await fulfillment(of: [started], timeout: 1)

        do {
            _ = try await second.downloadCurrentRegion()
            XCTFail("second same-region download unexpectedly started")
        } catch TileError.downloadAlreadyInProgress {
        } catch {
            XCTFail("expected downloadAlreadyInProgress, got \(error)")
        }
        XCTAssertEqual(secondFetcher.requestedURLs, [])
        control.cancel()
        _ = try? await firstTask.value

        let result = try await second.downloadCurrentRegion()
        XCTAssertEqual(result.publish.publishVersion, "20260717T000000Z")
        XCTAssertEqual(try store.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
    }

    func testOfflineStoreDeleteRefusesRegionWithActiveDownloadLease() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let started = expectation(description: "download started")
        let fetcher = SlowDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
        ], onDownloadStarted: {
            started.fulfill()
        })
        let control = OfflineRegionDownloadControl()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })
        let task = Task {
            try await downloader.downloadCurrentRegion(control: control)
        }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertThrowsError(try store.delete(region: "uk")) {
            XCTAssertEqual($0 as? TileError, .downloadAlreadyInProgress)
        }
        control.cancel()
        _ = try? await task.value
    }

    func testOfflineStoreDownloadLeaseSpansStoreInstancesForSameRoot() async throws {
        let root = temporaryOfflineRoot()
        let firstStore = try OfflineRegionStore(root: root)
        let secondStore = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let started = expectation(description: "download started")
        let firstFetcher = SlowDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
        ], onDownloadStarted: {
            started.fulfill()
        })
        let secondFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
        ])
        let control = OfflineRegionDownloadControl()
        let first = OfflineRegionDownloader(region: "uk", fetcher: firstFetcher, store: firstStore, availableBytes: { 10_000_000_000 })
        let second = OfflineRegionDownloader(region: "uk", fetcher: secondFetcher, store: secondStore, availableBytes: { 10_000_000_000 })
        let firstTask = Task {
            try await first.downloadCurrentRegion(control: control)
        }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertThrowsError(try secondStore.delete(region: "uk")) {
            XCTAssertEqual($0 as? TileError, .downloadAlreadyInProgress)
        }
        do {
            _ = try await second.downloadCurrentRegion()
            XCTFail("second same-root download unexpectedly started")
        } catch TileError.downloadAlreadyInProgress {
        } catch {
            XCTFail("expected downloadAlreadyInProgress, got \(error)")
        }
        XCTAssertEqual(secondFetcher.requestedURLs, [])
        control.cancel()
        _ = try? await firstTask.value
    }

    func testOfflineStoreDiscardRefusesRegionWithActiveDownloadLease() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let started = expectation(description: "download started")
        let fetcher = SlowDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
        ], onDownloadStarted: {
            started.fulfill()
        })
        let control = OfflineRegionDownloadControl()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })
        let task = Task {
            try await downloader.downloadCurrentRegion(control: control)
        }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertThrowsError(try store.discardInProgressDownloads(region: "uk")) {
            XCTAssertEqual($0 as? TileError, .downloadAlreadyInProgress)
        }
        control.cancel()
        _ = try? await task.value
    }

    func testOfflineDownloaderCancelStopsInflightDownloadAndDoesNotStageObject() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let tileSHA = sha256(tile)
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let started = expectation(description: "download started")
        let fetcher = SlowDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
        ], onDownloadStarted: {
            started.fulfill()
        })
        let control = OfflineRegionDownloadControl()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        let task = Task {
            try await downloader.downloadCurrentRegion(control: control)
        }
        await fulfillment(of: [started], timeout: 1)
        control.cancel()

        do {
            _ = try await task.value
            XCTFail("download unexpectedly succeeded after inflight cancel")
        } catch TileError.downloadCancelled {
        } catch {
            XCTFail("expected downloadCancelled, got \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: tileSHA).path))
        XCTAssertNil(try store.installedPublish(region: "uk"))
    }

    func testOfflineDownloaderPauseStopsInflightDownloadAndRetainsInProgressRoot() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let tileSHA = sha256(tile)
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let started = expectation(description: "download started")
        let fetcher = SlowDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
        ], onDownloadStarted: {
            started.fulfill()
        })
        let control = OfflineRegionDownloadControl()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        let task = Task {
            try await downloader.downloadCurrentRegion(control: control)
        }
        await fulfillment(of: [started], timeout: 1)
        control.pause()

        do {
            _ = try await task.value
            XCTFail("download unexpectedly succeeded after inflight pause")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: tileSHA).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertNil(try store.installedPublish(region: "uk"))
    }

    func testOfflineDownloaderPauseSurvivesRelaunchUntilUserResume() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let firstTile = try gzipJSON(tileObject(places: [validPlace()]))
        let firstSHA = sha256(firstTile)
        let secondTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let secondSHA = sha256(secondTile)
        let basemap = Data("basemap".utf8)
        let targetObject = twoTileManifestObject(
            firstSHA: firstSHA,
            firstBytes: firstTile.count,
            secondSHA: secondSHA,
            secondBytes: secondTile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count
        )
        let control = OfflineRegionDownloadControl()
        let first = OfflineRegionDownloader(
            region: "uk",
            fetcher: StubFetcher(routes: [
                "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
                "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
                "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": firstTile,
                "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz": secondTile,
                "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
            ]),
            store: store,
            availableBytes: { 10_000_000_000 }
        )
        do {
            _ = try await first.downloadCurrentRegion(control: control) { event in
                if event.completedObjectCount == 1 {
                    control.pause()
                }
            }
            XCTFail("download unexpectedly succeeded after pause")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }
        XCTAssertEqual(try Data(contentsOf: offlineTileObjectURL(root: root, sha: firstSHA)), firstTile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))

        let relaunchedStore = try OfflineRegionStore(root: root)
        XCTAssertEqual(try relaunchedStore.pendingDownloadRegions(), [])
        let replayFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260718T000000Z"]),
        ])
        let replay = OfflineRegionDownloader(region: "uk", fetcher: replayFetcher, store: relaunchedStore, availableBytes: { 10_000_000_000 })

        do {
            _ = try await replay.downloadCurrentRegion()
            XCTFail("relaunch replay unexpectedly resumed paused download")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected persisted downloadPaused, got \(error)")
        }
        XCTAssertEqual(replayFetcher.requestedURLs, [])

        let resumedFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz": secondTile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let resumed = OfflineRegionDownloader(region: "uk", fetcher: resumedFetcher, store: relaunchedStore, availableBytes: { 10_000_000_000 })

        _ = try await resumed.downloadCurrentRegion(resumingPausedDownload: true)

        XCTAssertFalse(resumedFetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"))
        XCTAssertEqual(try relaunchedStore.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
    }

    func testOfflineDownloaderPauseCancelsHTTPDownloadTaskAndRetainsInProgressRoot() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let started = expectation(description: "HTTP download started")
        let stopped = expectation(description: "HTTP download task cancelled")
        let tileURL = "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"
        RedirectURLProtocol.reset()
        RedirectURLProtocol.mode = .blockingDownload(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
        ])
        RedirectURLProtocol.onBlockedRequest = { request in
            if request.url?.absoluteString == tileURL {
                started.fulfill()
            }
        }
        RedirectURLProtocol.onStopLoading = { request in
            if request.url?.absoluteString == tileURL {
                stopped.fulfill()
            }
        }
        defer { RedirectURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectURLProtocol.self]
        let fetcher = HTTPTileFetcher(configuration: configuration)
        let control = OfflineRegionDownloadControl()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        let task = Task {
            try await downloader.downloadCurrentRegion(control: control)
        }
        await fulfillment(of: [started], timeout: 2)
        control.pause()

        do {
            _ = try await task.value
            XCTFail("download unexpectedly succeeded after HTTP download pause")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected downloadPaused, got \(error)")
        }
        await fulfillment(of: [stopped], timeout: 2)

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertNil(try store.installedPublish(region: "uk"))
    }

    func testOfflineDownloaderPauseResumeRaceDoesNotDiscardRetainedWork() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let tileSHA = sha256(tile)
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: tileSHA,
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let started = expectation(description: "download started")
        let fetcher = SlowDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
        ], onDownloadStarted: {
            started.fulfill()
        })
        let control = OfflineRegionDownloadControl()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        let task = Task {
            try await downloader.downloadCurrentRegion(control: control)
        }
        await fulfillment(of: [started], timeout: 1)
        control.pause()
        control.resume()

        do {
            _ = try await task.value
            XCTFail("download unexpectedly succeeded after pause/resume race")
        } catch TileError.downloadPaused {
        } catch {
            XCTFail("expected latched downloadPaused, got \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
    }

    func testOfflineDownloaderPauseThenCancelDiscardsRetainedWork() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let targetObject = manifestObject(
            publishVersion: "20260717T000000Z",
            tileSHA: sha256(tile),
            tileBytes: tile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count,
            attributionSources: []
        )
        let started = expectation(description: "download started")
        let fetcher = SlowDownloadFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": tile,
        ], onDownloadStarted: {
            started.fulfill()
        })
        let control = OfflineRegionDownloadControl()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        let task = Task {
            try await downloader.downloadCurrentRegion(control: control)
        }
        await fulfillment(of: [started], timeout: 1)
        control.pause()
        control.cancel()

        do {
            _ = try await task.value
            XCTFail("download unexpectedly succeeded after pause then cancel")
        } catch TileError.downloadCancelled {
        } catch {
            XCTFail("expected downloadCancelled, got \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertNil(try store.installedPublish(region: "uk"))
    }

    func testOfflineDownloaderResumesPendingPublishBeforeAdoptingNewCurrent() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let oldTile = try gzipJSON(tileObject(places: [validPlace()]))
        let oldSHA = sha256(oldTile)
        let missingOldTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let oldBasemap = Data("old-basemap".utf8)
        let oldManifest = twoTileManifestObject(
            publishVersion: "20260717T000000Z",
            firstSHA: oldSHA,
            firstBytes: oldTile.count,
            secondSHA: sha256(missingOldTile),
            secondBytes: missingOldTile.count,
            basemapSHA: sha256(oldBasemap),
            basemapBytes: oldBasemap.count
        )
        let interrupted = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(oldManifest),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": oldTile,
        ])
        let interruptedDownloader = OfflineRegionDownloader(region: "uk", fetcher: interrupted, store: store, availableBytes: { 10_000_000_000 })
        do {
            _ = try await interruptedDownloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded with the second tile missing")
        } catch let error as URLError where error.code == .notConnectedToInternet {
        } catch {
            XCTFail("expected interrupted fetch, got \(error)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: oldSHA).path))

        let complete = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260718T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz": missingOldTile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": oldBasemap,
        ])
        let completeDownloader = OfflineRegionDownloader(region: "uk", fetcher: complete, store: store, availableBytes: { 10_000_000_000 })

        _ = try await completeDownloader.downloadCurrentRegion()

        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: oldSHA).path))
        XCTAssertFalse(complete.requestedURLs.contains("https://tiles.making-tracks.app/uk/current.json"))
        XCTAssertEqual(try store.installedPublish(region: "uk")?.publishVersion, "20260717T000000Z")
    }

    func testOfflineDownloaderSurfacesPendingPublishObject404WithoutRepinningCurrent() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let oldTile = try gzipJSON(tileObject(places: [validPlace()]))
        let oldBasemap = Data("old-basemap".utf8)
        let oldPublish = cachedPublish(
            "20260717T000000Z",
            tileSHA: sha256(oldTile),
            tileBytes: oldTile.count,
            basemapSHA: sha256(oldBasemap),
            basemapBytes: oldBasemap.count,
            attributionSources: []
        )
        try store.beginDownload(publish: oldPublish)
        let newTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let newBasemap = Data("new-basemap".utf8)
        let newManifest = manifestObject(
            publishVersion: "20260718T000000Z",
            tileX: 512,
            tileY: 340,
            tileSHA: sha256(newTile),
            tileBytes: newTile.count,
            basemapSHA: sha256(newBasemap),
            basemapBytes: newBasemap.count,
            attributionSources: []
        )
        let oldTileURL = "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz"
        let completedURL = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz")!
        let identifier = OfflineDownloadSession.backgroundIdentifier(region: "uk")
        try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: identifier,
            url: completedURL,
            fileURL: stagedObjectFile(Data("stale completed".utf8)),
            response: HTTPURLResponse(url: completedURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
        defer { OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier) }
        let metadataFetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260718T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260718T000000Z/manifest.json": jsonData(newManifest),
        ])
        let objectFetcher = FailingDownloadFetcher(
            routes: [
                "https://tiles.making-tracks.app/uk/20260718T000000Z/tiles/10/512/340.json.gz": newTile,
                "https://tiles.making-tracks.app/uk/20260718T000000Z/uk.pmtiles": newBasemap,
            ],
            failURL: oldTileURL,
            error: TileError.httpStatus(404)
        )
        let downloader = OfflineRegionDownloader(
            region: "uk",
            metadataFetcher: metadataFetcher,
            objectFetcher: objectFetcher,
            store: store,
            availableBytes: { 10_000_000_000 }
        )

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("download unexpectedly repinned current after pending object 404")
        } catch TileError.httpStatus(404) {
        } catch {
            XCTFail("expected pending object 404, got \(error)")
        }

        XCTAssertNil(try store.installedPublish(region: "uk"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertEqual(metadataFetcher.requestedURLs, [])
        XCTAssertEqual(objectFetcher.requestedURLs, [
            oldTileURL,
        ])
        XCTAssertNotNil(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: completedURL))
    }

    func testOfflineStoreDeletePurgesCompletedBackgroundDownloadsForRegion() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let identifier = OfflineDownloadSession.backgroundIdentifier(region: "uk")
        let url = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: identifier,
            url: url,
            fileURL: stagedObjectFile(Data("downloaded".utf8)),
            response: response
        )
        defer { OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier) }

        try store.delete(region: "uk")

        XCTAssertNil(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: url))
    }

    func testCompletedBackgroundDownloadMaintenanceSweepsOrphansAndEvictsOldestFiles() throws {
        let identifier = OfflineDownloadSession.backgroundIdentifier(region: "uk")
        let firstURL = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz")!
        let secondURL = URL(string: "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz")!
        let response = HTTPURLResponse(url: firstURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: identifier,
            url: firstURL,
            fileURL: stagedObjectFile(Data("first".utf8)),
            response: response
        )
        try OfflineDownloadSession.stageCompletedDownloadForTesting(
            identifier: identifier,
            url: secondURL,
            fileURL: stagedObjectFile(Data("second".utf8)),
            response: HTTPURLResponse(url: secondURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
        let orphanName = "123E4567-E89B-12D3-A456-426614174000.download"
        try OfflineDownloadSession.createCompletedDownloadFileForTesting(named: orphanName, data: Data("orphan".utf8))
        defer { OfflineDownloadSession.removeCompletedDownloadsForTesting(identifier: identifier) }

        try OfflineDownloadSession.performCompletedDownloadMaintenanceForTesting(maxBytes: 6)

        XCTAssertNil(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: firstURL))
        XCTAssertNotNil(OfflineDownloadSession.consumeCompletedDownload(identifier: identifier, url: secondURL))
        XCTAssertFalse(OfflineDownloadSession.hasCompletedDownloadFileForTesting(named: orphanName))
    }

    func testOfflineStoreBasemapStagingMovesDownloadedFileIntoObjectStore() throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let basemap = Data("basemap".utf8)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("MakingTracksBasemapMoveTest-\(UUID().uuidString).pmtiles")
        try basemap.write(to: source, options: .atomic)

        try store.stageDownloadedBasemapObject(source, sha256: sha256(basemap), bytes: basemap.count)

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: offlineBasemapObjectURL(root: root, sha: sha256(basemap))), basemap)
    }

    func testOfflineStoreDeleteRegionDiscardsMatchingInProgressObjects() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let firstTile = try gzipJSON(tileObject(places: [validPlace()]))
        let firstSHA = sha256(firstTile)
        let secondTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let basemap = Data("basemap".utf8)
        let targetObject = twoTileManifestObject(
            firstSHA: firstSHA,
            firstBytes: firstTile.count,
            secondSHA: sha256(secondTile),
            secondBytes: secondTile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count
        )
        let firstAttempt = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": firstTile,
        ])
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: firstAttempt, store: store, availableBytes: { 10_000_000_000 })

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded with the second tile missing")
        } catch let error as URLError where error.code == .notConnectedToInternet {
        } catch {
            XCTFail("expected interrupted fetch, got \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: firstSHA).path))
        try store.delete(region: "uk")

        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: firstSHA).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
    }

    func testOfflineDownloaderCanCancelAfterPersistingCurrentObject() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let firstTile = try gzipJSON(tileObject(places: [validPlace()]))
        let firstSHA = sha256(firstTile)
        let secondTile = try gzipJSON(tileObject(places: [validPlace(["place_id": "mt1_00000000000000000000000001"])], x: 512))
        let secondSHA = sha256(secondTile)
        let basemap = Data("basemap".utf8)
        let targetObject = twoTileManifestObject(
            firstSHA: firstSHA,
            firstBytes: firstTile.count,
            secondSHA: secondSHA,
            secondBytes: secondTile.count,
            basemapSHA: sha256(basemap),
            basemapBytes: basemap.count
        )
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260717T000000Z"]),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/manifest.json": jsonData(targetObject),
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/511/340.json.gz": firstTile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/tiles/10/512/340.json.gz": secondTile,
            "https://tiles.making-tracks.app/uk/20260717T000000Z/uk.pmtiles": basemap,
        ])
        let control = OfflineRegionDownloadControl()
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 10_000_000_000 })

        do {
            _ = try await downloader.downloadCurrentRegion(control: control) { event in
                if event.completedObjectCount == 1 {
                    control.cancel()
                }
            }
            XCTFail("download unexpectedly succeeded after cancel")
        } catch TileError.downloadCancelled {
        } catch {
            XCTFail("expected downloadCancelled, got \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineTileObjectURL(root: root, sha: firstSHA).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineInProgressIndexURL(root: root, region: "uk", publishVersion: "20260717T000000Z").path))
        XCTAssertNil(try store.installedPublish(region: "uk"))
    }

    func testOfflineDownloaderRejectsInsufficientStorageBeforeBlobFetch() async throws {
        let root = temporaryOfflineRoot()
        let store = try OfflineRegionStore(root: root)
        let tile = try gzipJSON(tileObject(places: [validPlace()]))
        let basemap = Data("basemap".utf8)
        let fetcher = StubFetcher(routes: [
            "https://tiles.making-tracks.app/uk/current.json": jsonData(["schema_version": 1, "publish_version": "20260716T155409Z"]),
            "https://tiles.making-tracks.app/uk/20260716T155409Z/manifest.json": manifestData(
                tileSHA: sha256(tile),
                tileBytes: tile.count,
                basemapSHA: sha256(basemap),
                basemapBytes: basemap.count,
                attributionSources: []
            ),
        ])
        let downloader = OfflineRegionDownloader(region: "uk", fetcher: fetcher, store: store, availableBytes: { 1 })

        do {
            _ = try await downloader.downloadCurrentRegion()
            XCTFail("download unexpectedly succeeded without storage headroom")
        } catch TileError.insufficientStorage {
        } catch {
            XCTFail("expected insufficientStorage, got \(error)")
        }
        XCTAssertNil(try store.installedPublish(region: "uk"))
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260716T155409Z/tiles/10/511/340.json.gz"))
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/uk/20260716T155409Z/uk.pmtiles"))
    }
}

private final class StubFetcher: OfflineRegionFetching, @unchecked Sendable {
    var routes: [String: Data]
    private(set) var requestedURLs: [String] = []

    init(routes: [String: Data]) {
        self.routes = routes
    }

    func fetch(_ url: URL) async throws -> Data {
        requestedURLs.append(url.absoluteString)
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return data
    }

    func download(_ url: URL) async throws -> URL {
        let data = try await fetch(url)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MakingTracksStubDownload-\(UUID().uuidString)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private final class SlowDownloadFetcher: OfflineRegionFetching, @unchecked Sendable {
    private let routes: [String: Data]
    private let onDownloadStarted: () -> Void

    init(routes: [String: Data], onDownloadStarted: @escaping () -> Void) {
        self.routes = routes
        self.onDownloadStarted = onDownloadStarted
    }

    func fetch(_ url: URL) async throws -> Data {
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return data
    }

    func download(_ url: URL) async throws -> URL {
        onDownloadStarted()
        do {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        } catch is CancellationError {
            throw URLError(.cancelled)
        }
        let data = try await fetch(url)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MakingTracksSlowDownload-\(UUID().uuidString)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private final class OutOfSpaceDownloadFetcher: OfflineRegionFetching, @unchecked Sendable {
    private let routes: [String: Data]
    private let error: Error

    init(routes: [String: Data], error: Error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)) {
        self.routes = routes
        self.error = error
    }

    func fetch(_ url: URL) async throws -> Data {
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return data
    }

    func download(_ url: URL) async throws -> URL {
        throw error
    }
}

private final class ConnectivityWaitingFetcher: ConnectivityWaitingOfflineRegionFetching, @unchecked Sendable {
    private let routes: [String: Data]

    init(routes: [String: Data]) {
        self.routes = routes
    }

    func fetch(_ url: URL) async throws -> Data {
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return data
    }

    func fetch(_ url: URL, connectivityWaiting: (@Sendable () -> Void)?) async throws -> Data {
        try await fetch(url, connectivityWaiting: connectivityWaiting, connectivityAvailable: nil)
    }

    func fetch(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?
    ) async throws -> Data {
        connectivityWaiting?()
        connectivityAvailable?()
        return try await fetch(url)
    }

    func download(_ url: URL) async throws -> URL {
        let data = try await fetch(url)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MakingTracksConnectivityWaitingDownload-\(UUID().uuidString)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func download(_ url: URL, connectivityWaiting: (@Sendable () -> Void)?) async throws -> URL {
        try await download(url, connectivityWaiting: connectivityWaiting, connectivityAvailable: nil)
    }

    func download(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?
    ) async throws -> URL {
        connectivityWaiting?()
        connectivityAvailable?()
        return try await download(url)
    }
}

private final class ProgressReportingFetcher: ProgressReportingOfflineRegionFetching, @unchecked Sendable {
    private let routes: [String: Data]
    private let downloadProgress: [String: [Int64]]

    init(routes: [String: Data], downloadProgress: [String: [Int64]]) {
        self.routes = routes
        self.downloadProgress = downloadProgress
    }

    func fetch(_ url: URL) async throws -> Data {
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return data
    }

    func fetch(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?
    ) async throws -> Data {
        try await fetch(url)
    }

    func download(_ url: URL) async throws -> URL {
        try await download(
            url,
            connectivityWaiting: nil,
            connectivityAvailable: nil,
            progress: nil
        )
    }

    func download(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?
    ) async throws -> URL {
        try await download(
            url,
            connectivityWaiting: connectivityWaiting,
            connectivityAvailable: connectivityAvailable,
            progress: nil
        )
    }

    func download(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?,
        progress: (@Sendable (_ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)?
    ) async throws -> URL {
        connectivityAvailable?()
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        for bytes in downloadProgress[url.absoluteString] ?? [] {
            progress?(bytes, Int64(data.count))
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MakingTracksProgressReportingDownload-\(UUID().uuidString)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private final class FailingDownloadFetcher: OfflineRegionFetching, @unchecked Sendable {
    private let routes: [String: Data]
    private let failURL: String
    private let error: Error
    private(set) var requestedURLs: [String] = []

    init(routes: [String: Data], failURL: String, error: Error) {
        self.routes = routes
        self.failURL = failURL
        self.error = error
    }

    func fetch(_ url: URL) async throws -> Data {
        requestedURLs.append(url.absoluteString)
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return data
    }

    func download(_ url: URL) async throws -> URL {
        requestedURLs.append(url.absoluteString)
        if url.absoluteString == failURL {
            throw error
        }
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MakingTracksFailingDownload-\(UUID().uuidString)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [OfflineRegionDownloadProgress] = []

    var events: [OfflineRegionDownloadProgress] {
        lock.withLock { recorded }
    }

    func append(_ event: OfflineRegionDownloadProgress) {
        lock.withLock {
            recorded.append(event)
        }
    }
}

private final class CallbackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock {
            value += 1
        }
    }
}

private final class MissingURLHTTPResponse: HTTPURLResponse, @unchecked Sendable {
    override var url: URL? { nil }
}

private final class HeadroomSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64]

    init(_ values: [Int64]) {
        self.values = values
    }

    func next() -> Int64? {
        lock.withLock {
            if values.count > 1 {
                return values.removeFirst()
            }
            return values.first
        }
    }
}

private final class RedirectURLProtocol: URLProtocol, @unchecked Sendable {
    enum Mode: Sendable {
        case status(Int, location: String?)
        case statusFromResponseURL(Int, responseURL: String)
        case redirect(to: String)
        case blockingDownload(routes: [String: Data])
    }

    nonisolated(unsafe) static var mode: Mode = .status(200, location: nil)
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var requestedURLs: [URL] = []
    nonisolated(unsafe) static var onBlockedRequest: ((URLRequest) -> Void)?
    nonisolated(unsafe) static var onStopLoading: ((URLRequest) -> Void)?

    static func reset() {
        mode = .status(200, location: nil)
        responseBody = Data()
        requestedURLs = []
        onBlockedRequest = nil
        onStopLoading = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestedURLs.append(request.url!)
        switch Self.mode {
        case .status(let status, let location):
            startLoadingStatus(status, location: location, body: Self.responseBody)
        case .statusFromResponseURL(let status, let responseURL):
            let response = HTTPURLResponse(
                url: URL(string: responseURL)!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.responseBody)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let location):
            let response = response(status: 302, location: location)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: location)!), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
        case .blockingDownload(let routes):
            if let data = routes[request.url!.absoluteString] {
                startLoadingStatus(200, location: nil, body: data)
            } else {
                Self.onBlockedRequest?(request)
            }
        }
    }

    private func startLoadingStatus(_ status: Int, location: String?, body: Data) {
        let response = response(status: status, location: location)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func response(status: Int, location: String?) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let location {
            headers["Location"] = location
        }
        return HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    override func stopLoading() {
        Self.onStopLoading?(request)
    }
}

private func temporaryCache(maxBytes: Int = 1024 * 1024) throws -> TileCache {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MakingTracksTilesTests-\(UUID().uuidString)", isDirectory: true)
    return try TileCache(directory: url, maxBytes: maxBytes)
}

private func temporaryOfflineRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("MakingTracksOfflineRegionTests-\(UUID().uuidString)", isDirectory: true)
}

private func offlineTileObjectURL(root: URL, sha: String) -> URL {
    root.appendingPathComponent("objects/tiles/\(sha).json.gz")
}

private func offlineBasemapObjectURL(root: URL, sha: String) -> URL {
    root.appendingPathComponent("objects/basemaps/\(sha).pmtiles")
}

private func offlineCurrentPackURL(root: URL, region: String) -> URL {
    root.appendingPathComponent("regions/\(region)/current-pack.json")
}

private func offlinePackIndexURL(root: URL, region: String, publishVersion: String) -> URL {
    root.appendingPathComponent("packs/\(region)/\(publishVersion)/pack-index.json")
}

private func offlineInProgressIndexURL(root: URL, region: String, publishVersion: String) -> URL {
    root.appendingPathComponent("in-progress/\(region)/\(publishVersion)/pack-index.json")
}

private func offlineInstallBackupURL(root: URL) -> URL {
    root.appendingPathComponent("tmp/\(UUID().uuidString)-backup", isDirectory: true)
}

private func stagedObjectFile(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MakingTracksStagedObject-\(UUID().uuidString)")
    try data.write(to: url, options: .atomic)
    return url
}

private func cachedPublish(
    _ publishVersion: String,
    region: String = "uk",
    tileX: Int = 511,
    tileY: Int = 340,
    tileSHA: String = String(repeating: "0", count: 64),
    tileBytes: Int = 100,
    basemapSHA: String = String(repeating: "1", count: 64),
    basemapBytes: Int = 1234,
    basemapBBox: [Double] = [-8.65, 49.84, 1.77, 60.86],
    attributionSources: [String]
) -> PinnedPublish {
    let manifest = try! Manifest.decode(manifestData(
        publishVersion: publishVersion,
        region: region,
        tileX: tileX,
        tileY: tileY,
        tileSHA: tileSHA,
        tileBytes: tileBytes,
        basemapSHA: basemapSHA,
        basemapBytes: basemapBytes,
        basemapBBox: basemapBBox,
        attributionSources: attributionSources
    ))
    return PinnedPublish(region: region, publishVersion: publishVersion, manifest: manifest)
}

private func manifestData(
    publishVersion: String = "20260716T155409Z",
    region: String = "uk",
    minReaderVersion: Int = 2,
    tileX: Int = 511,
    tileY: Int = 340,
    tileSHA: String = String(repeating: "0", count: 64),
    tileBytes: Int = 100,
    basemapSHA: String = String(repeating: "1", count: 64),
    basemapBytes: Int = 1234,
    basemapBBox: [Double] = [-8.65, 49.84, 1.77, 60.86],
    attributionSources: [String]
) -> Data {
    jsonData(manifestObject(
        publishVersion: publishVersion,
        region: region,
        minReaderVersion: minReaderVersion,
        tileX: tileX,
        tileY: tileY,
        tileSHA: tileSHA,
        tileBytes: tileBytes,
        basemapSHA: basemapSHA,
        basemapBytes: basemapBytes,
        basemapBBox: basemapBBox,
        attributionSources: attributionSources
    ))
}

private func manifestObject(
    publishVersion: String = "20260716T155409Z",
    region: String = "uk",
    minReaderVersion: Int = 2,
    tileX: Int = 511,
    tileY: Int = 340,
    tileSHA: String = String(repeating: "0", count: 64),
    tileBytes: Int = 100,
    basemapSHA: String = String(repeating: "1", count: 64),
    basemapBytes: Int = 1234,
    basemapBBox: [Double] = [-8.65, 49.84, 1.77, 60.86],
    attributionSources: [String]
) -> [String: Any] {
    var object: [String: Any] = [
        "schema_version": 1,
        "min_reader_version": minReaderVersion,
        "region": region,
        "publish_version": publishVersion,
        "tile_z": 10,
        "tiles": [["x": tileX, "y": tileY, "sha256": tileSHA, "bytes": tileBytes]],
        "counts": ["total": 1, "by_tier": [1, 0, 0, 0]],
        "basemap": ["filename": "uk.pmtiles", "maxzoom": 14, "sha256": basemapSHA, "bytes": basemapBytes, "bbox": basemapBBox],
        "provenance": [["task_id": "score", "model": "heuristic", "prompt_version": "score-v1"]],
    ]
    if !attributionSources.isEmpty {
        object["attribution"] = attributionSources.map {
            ["source": $0, "license": $0 == "osm" ? "ODbL-1.0" : "PDDL-1.0", "text": $0 == "osm" ? "OSM credit" : "Credit"]
        }
    } else {
        object["attribution"] = []
    }
    return object
}

private func twoTileManifestObject(
    publishVersion: String = "20260717T000000Z",
    firstSHA: String,
    firstBytes: Int,
    secondSHA: String,
    secondBytes: Int,
    basemapSHA: String,
    basemapBytes: Int
) -> [String: Any] {
    var object = manifestObject(
        publishVersion: publishVersion,
        tileSHA: firstSHA,
        tileBytes: firstBytes,
        basemapSHA: basemapSHA,
        basemapBytes: basemapBytes,
        attributionSources: []
    )
    object["tiles"] = [
        ["x": 511, "y": 340, "sha256": firstSHA, "bytes": firstBytes],
        ["x": 512, "y": 340, "sha256": secondSHA, "bytes": secondBytes],
    ]
    object["counts"] = ["total": 2, "by_tier": [2, 0, 0, 0]]
    return object
}

private func regionIndexObject() -> [String: Any] {
    [
        "schema_version": 1,
        "min_reader_version": 2,
        "generated_at": "2026-07-17T10:00:00Z",
        "regions": [regionIndexEntry()],
    ]
}

private func regionIndexEntry(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var entry: [String: Any] = [
        "id": "uk",
        "display_name": "United Kingdom",
        "parent": NSNull(),
        "bbox": [-8.65, 49.84, 1.77, 60.86],
        "publish_version": "20260716T155409Z",
        "basemap_bytes": 1_500_000,
        "tile_count": 184,
        "bytes_without_thumbnails": 2_000_000,
        "bytes_with_thumbnails": 2_500_000,
    ]
    for (key, value) in overrides {
        entry[key] = value
    }
    return entry
}

private let liveTile489310Base64 = """
H4sIAAAAAAAC/x2PywrCMBBF/2XWtSSmD5NdXYhUCipiFyIlttEG2kaS+MZ/d+puuDPncuYD107WyoE4fKCWXl2MfYGAVjtvrK6r0013jR4uEEAnPYg4DeMoiSM+YwwjM4CYpCEnEaWcUB7AIHuFBZlrle6R+vdXusGs97RixXy5WxXZYr/Oy2KzXaR8XSY52ZV462pjESYhwdncLIJWnUc5eDRiQwnj05izFI4BeK0siOh7HLFW9bK6K+v0KEQDeOJqhjb4C6PY9saUfH9K/chJ7gAAAA==
"""

private func tileObject(places: [[String: Any]], z: Int = 10, x: Int = 511, y: Int = 340) -> [String: Any] {
    ["schema_version": 1, "z": z, "x": x, "y": y, "places": places]
}

private func validPlace(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var place: [String: Any] = [
        "place_id": "mt1_00000000000000000000000000",
        "name": "Big Ben",
        "lat": 51.5007,
        "lon": -0.1246,
        "category": "historic_building",
        "tier": 1,
        "score": 0.9,
        "source_refs": ["wd:Q42"],
        "alt_names": ["Elizabeth Tower"],
        "blurb": "Clock tower",
        "image_url": "https://upload.wikimedia.org/file.jpg",
        "wikipedia_title": "Big Ben",
    ]
    for (key, value) in overrides {
        place[key] = value
    }
    return place
}

private func jsonData(_ value: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

private func gzipJSON(_ value: Any) throws -> Data {
    try gzipData(jsonData(value))
}

private func gzipData(_ data: Data) throws -> Data {
    var stream = z_stream()
    let initStatus = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 16 + MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard initStatus == Z_OK else { throw NSError(domain: "gzip", code: Int(initStatus)) }
    defer { deflateEnd(&stream) }
    return try data.withUnsafeBytes { sourceBuffer in
        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: sourceBuffer.bindMemory(to: Bytef.self).baseAddress)
        stream.avail_in = uInt(data.count)
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        repeat {
            let status = try buffer.withUnsafeMutableBufferPointer { outBuffer in
                guard let outBase = outBuffer.baseAddress else { throw NSError(domain: "gzip", code: -1) }
                stream.next_out = outBase
                stream.avail_out = uInt(outBuffer.count)
                return deflate(&stream, Z_FINISH)
            }
            guard status == Z_OK || status == Z_STREAM_END else { throw NSError(domain: "gzip", code: Int(status)) }
            out.append(buffer, count: buffer.count - Int(stream.avail_out))
            if status == Z_STREAM_END { break }
        } while stream.avail_out == 0
        return out
    }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func syntheticCompletedDownloadTask(
    request: URLRequest,
    on session: URLSession,
    response: URLResponse? = nil
) -> URLSessionDownloadTask {
    let task = session.downloadTask(with: request)
    task.setValue(URLSessionTask.State.completed.rawValue, forKey: "state")
    if let response {
        task.setValue(response, forKey: "response")
    }
    return task
}

private final class LockedAsyncResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.withLock {
            self.result = result
        }
    }

    func load() -> Result<Value, Error>? {
        lock.withLock {
            result
        }
    }
}
