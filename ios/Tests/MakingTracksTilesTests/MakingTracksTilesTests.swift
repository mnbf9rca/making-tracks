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
        XCTAssertNoThrow(try HTTPTileFetcher.validateOrigin(URL(string: "https://tiles.making-tracks.app/uk/current.json")!))
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
}

private final class StubFetcher: TileFetching, @unchecked Sendable {
    var routes: [String: Data]

    init(routes: [String: Data]) {
        self.routes = routes
    }

    func fetch(_ url: URL) async throws -> Data {
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return data
    }
}

private final class RedirectURLProtocol: URLProtocol, @unchecked Sendable {
    enum Mode: Sendable {
        case status(Int, location: String?)
    }

    nonisolated(unsafe) static var mode: Mode = .status(200, location: nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.mode {
        case .status(let status, let location):
            var headers: [String: String] = [:]
            if let location {
                headers["Location"] = location
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private func temporaryCache(maxBytes: Int = 1024 * 1024) throws -> TileCache {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MakingTracksTilesTests-\(UUID().uuidString)", isDirectory: true)
    return try TileCache(directory: url, maxBytes: maxBytes)
}

private func cachedPublish(_ publishVersion: String, tileSHA: String = String(repeating: "0", count: 64), tileBytes: Int = 100, attributionSources: [String]) -> PinnedPublish {
    let manifest = try! Manifest.decode(manifestData(publishVersion: publishVersion, tileSHA: tileSHA, tileBytes: tileBytes, attributionSources: attributionSources))
    return PinnedPublish(region: "uk", publishVersion: publishVersion, manifest: manifest)
}

private func manifestData(
    publishVersion: String = "20260716T155409Z",
    region: String = "uk",
    minReaderVersion: Int = 2,
    tileSHA: String = String(repeating: "0", count: 64),
    tileBytes: Int = 100,
    attributionSources: [String]
) -> Data {
    jsonData(manifestObject(
        publishVersion: publishVersion,
        region: region,
        minReaderVersion: minReaderVersion,
        tileSHA: tileSHA,
        tileBytes: tileBytes,
        attributionSources: attributionSources
    ))
}

private func manifestObject(
    publishVersion: String = "20260716T155409Z",
    region: String = "uk",
    minReaderVersion: Int = 2,
    tileSHA: String = String(repeating: "0", count: 64),
    tileBytes: Int = 100,
    attributionSources: [String]
) -> [String: Any] {
    var object: [String: Any] = [
        "schema_version": 1,
        "min_reader_version": minReaderVersion,
        "region": region,
        "publish_version": publishVersion,
        "tile_z": 10,
        "tiles": [["x": 511, "y": 340, "sha256": tileSHA, "bytes": tileBytes]],
        "counts": ["total": 1, "by_tier": [1, 0, 0, 0]],
        "basemap": ["filename": "uk.pmtiles", "maxzoom": 14, "sha256": String(repeating: "1", count: 64), "bytes": 1234, "bbox": [-8.65, 49.84, 1.77, 60.86]],
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
        "category": "architecture",
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
