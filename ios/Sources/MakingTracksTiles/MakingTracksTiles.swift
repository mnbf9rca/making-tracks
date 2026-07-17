import CryptoKit
import Foundation
import MakingTracksData
import zlib

public enum TileLoadState: String, Codable, Sendable, Equatable {
    case ok
    case stale
    case updateAvailable
    case updateRequired
    case offline
    case manifestInvalid
    case unavailable
}

public enum SchemaCompatibility: Sendable, Equatable {
    case ok
    case tooNew
    case tooOld
}

public enum VersionGate {
    public static let readerVersion = 2
    public static let readerSchemaVersion = 1
    public static let minSupportedSchemaVersion = 1

    public static func schema(readerMax: Int, dataVersion: Int, minSupported: Int) -> SchemaCompatibility {
        if dataVersion > readerMax { return .tooNew }
        if dataVersion < minSupported { return .tooOld }
        return .ok
    }

    public static func reader(
        readerVersion: Int = Self.readerVersion,
        minReaderVersion: Int,
        hasReadableCache: Bool
    ) -> TileLoadState {
        minReaderVersion > readerVersion
            ? (hasReadableCache ? .updateAvailable : .updateRequired)
            : .ok
    }
}

public struct BBox: Sendable, Equatable {
    public let minLon: Double
    public let minLat: Double
    public let maxLon: Double
    public let maxLat: Double

    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }
}

public struct TileCoordinate: Codable, Sendable, Hashable {
    public let z: Int
    public let x: Int
    public let y: Int

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }
}

public struct Attribution: Codable, Sendable, Equatable {
    public let source: String
    public let license: String
    public let text: String

    public init(source: String, license: String, text: String) {
        self.source = source
        self.license = license
        self.text = text
    }
}

public protocol TileFetching: Sendable {
    func fetch(_ url: URL) async throws -> Data
}

public enum TileError: Error, Equatable {
    case invalidURL
    case untrustedHost
    case invalidRedirect
    case invalidCurrent
    case invalidManifest
    case invalidRegionIndex
    case invalidTile
    case invalidOfflinePack
    case insufficientStorage
    case checksumMismatch
    case byteCountMismatch
    case compressedTooLarge
    case inflatedTooLarge
    case invalidGzip
    case httpStatus(Int)
}

public final class HTTPTileFetcher: TileFetching, @unchecked Sendable {
    public static let trustedHost = "tiles.making-tracks.app"
    private let delegate: RedirectDelegate
    private let session: URLSession

    public convenience init() {
        self.init(configuration: .ephemeral)
    }

    init(configuration: URLSessionConfiguration) {
        delegate = RedirectDelegate()
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    public func fetch(_ url: URL) async throws -> Data {
        try Self.validateOrigin(url)
        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            throw TileError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    public static func validateOrigin(_ url: URL) throws {
        guard url.scheme == "https", url.host == trustedHost else {
            throw TileError.untrustedHost
        }
    }

    public static func validateRedirect(from: URL, to: URL) throws {
        try validateOrigin(from)
        try validateOrigin(to)
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let from = response.url, let to = request.url else {
            completionHandler(nil)
            return
        }
        do {
            try HTTPTileFetcher.validateRedirect(from: from, to: to)
            completionHandler(request)
        } catch {
            completionHandler(nil)
        }
    }
}

public struct Manifest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let minReaderVersion: Int
    public let region: String
    public let publishVersion: String
    public let generatedAt: String?
    public let tileZ: Int
    public let tiles: [ManifestTile]
    public let counts: Counts
    public let basemap: Basemap
    public let provenance: [Provenance]
    public let attribution: [Attribution]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case minReaderVersion = "min_reader_version"
        case region
        case publishVersion = "publish_version"
        case generatedAt = "generated_at"
        case tileZ = "tile_z"
        case tiles
        case counts
        case basemap
        case provenance
        case attribution
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        minReaderVersion = try container.decode(Int.self, forKey: .minReaderVersion)
        region = try container.decode(String.self, forKey: .region)
        publishVersion = try container.decode(String.self, forKey: .publishVersion)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        tileZ = try container.decode(Int.self, forKey: .tileZ)
        tiles = try container.decode([ManifestTile].self, forKey: .tiles)
        counts = try container.decode(Counts.self, forKey: .counts)
        basemap = try container.decode(Basemap.self, forKey: .basemap)
        provenance = try container.decode([Provenance].self, forKey: .provenance)
        attribution = try container.decodeIfPresent([Attribution].self, forKey: .attribution) ?? []
    }

    public static func decode(_ data: Data) throws -> Manifest {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TileError.invalidManifest
        }
        let allowed: Set<String> = [
            "schema_version", "min_reader_version", "region", "publish_version", "generated_at",
            "tile_z", "tiles", "counts", "basemap", "provenance", "attribution",
        ]
        guard Set(object.keys).isSubset(of: allowed) else { throw TileError.invalidManifest }
        try validateManifestObject(object)
        var manifest = try JSONDecoder().decode(Manifest.self, from: data)
        if manifest.attribution.isEmpty, object["attribution"] == nil {
            manifest = Manifest(
                schemaVersion: manifest.schemaVersion,
                minReaderVersion: manifest.minReaderVersion,
                region: manifest.region,
                publishVersion: manifest.publishVersion,
                generatedAt: manifest.generatedAt,
                tileZ: manifest.tileZ,
                tiles: manifest.tiles,
                counts: manifest.counts,
                basemap: manifest.basemap,
                provenance: manifest.provenance,
                attribution: []
            )
        }
        try manifest.validate()
        return manifest
    }

    private static func validateManifestObject(_ object: [String: Any]) throws {
        if let generatedAt = object["generated_at"] as? String {
            guard generatedAt.count <= 32,
                  generatedAt.matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")
            else { throw TileError.invalidManifest }
        }
        guard let tiles = object["tiles"] as? [[String: Any]],
              let counts = object["counts"] as? [String: Any],
              Set(counts.keys) == ["total", "by_tier"],
              let total = counts["total"] as? Int,
              total >= 0,
              let byTier = counts["by_tier"] as? [Int],
              byTier.count == 4,
              byTier.allSatisfy({ $0 >= 0 }),
              let basemap = object["basemap"] as? [String: Any],
              Set(basemap.keys) == ["filename", "maxzoom", "sha256", "bytes", "bbox"],
              let bbox = basemap["bbox"] as? [Double],
              bbox.count == 4,
              bbox.allSatisfy({ (-180.0...180.0).contains($0) }),
              let provenance = object["provenance"] as? [[String: Any]]
        else { throw TileError.invalidManifest }
        let attribution = (object["attribution"] as? [[String: Any]]) ?? []
        let tileKeys: Set<String> = ["x", "y", "sha256", "bytes"]
        let provenanceKeys: Set<String> = ["task_id", "model", "prompt_version"]
        let attributionKeys: Set<String> = ["source", "license", "text"]
        guard tiles.allSatisfy({ Set($0.keys) == tileKeys }),
              provenance.allSatisfy({ Set($0.keys) == provenanceKeys }),
              attribution.count <= 32,
              attribution.allSatisfy({ Set($0.keys) == attributionKeys })
        else { throw TileError.invalidManifest }
    }

    private init(
        schemaVersion: Int,
        minReaderVersion: Int,
        region: String,
        publishVersion: String,
        generatedAt: String?,
        tileZ: Int,
        tiles: [ManifestTile],
        counts: Counts,
        basemap: Basemap,
        provenance: [Provenance],
        attribution: [Attribution]
    ) {
        self.schemaVersion = schemaVersion
        self.minReaderVersion = minReaderVersion
        self.region = region
        self.publishVersion = publishVersion
        self.generatedAt = generatedAt
        self.tileZ = tileZ
        self.tiles = tiles
        self.counts = counts
        self.basemap = basemap
        self.provenance = provenance
        self.attribution = attribution
    }

    private func validate() throws {
        guard VersionGate.schema(
            readerMax: VersionGate.readerSchemaVersion,
            dataVersion: schemaVersion,
            minSupported: VersionGate.minSupportedSchemaVersion
        ) == .ok else { throw TileError.invalidManifest }
        guard minReaderVersion >= 1,
              region.matches("^[a-z][a-z0-9_]*$"),
              publishVersion.matches("^[0-9]{8}T[0-9]{6}Z$"),
              tileZ == 10,
              !tiles.isEmpty || counts.total == 0,
              tiles.count <= 1_048_576,
              counts.byTier.count == 4,
              !provenance.isEmpty,
              provenance.count <= 32
        else { throw TileError.invalidManifest }
        if !attribution.isEmpty && minReaderVersion < 2 {
            throw TileError.invalidManifest
        }
        for tile in tiles {
            try tile.validate()
        }
        try basemap.validate()
        for item in provenance {
            try item.validate()
        }
        for item in attribution {
            try item.validate()
        }
    }
}

public struct ManifestTile: Codable, Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let sha256: String
    public let bytes: Int

    func validate() throws {
        guard (0...1023).contains(x),
              (0...1023).contains(y),
              sha256.matches("^[0-9a-f]{64}$"),
              (1...TileCodec.maxCompressedBytes).contains(bytes)
        else { throw TileError.invalidManifest }
    }
}

public struct Counts: Codable, Sendable, Equatable {
    public let total: Int
    public let byTier: [Int]

    enum CodingKeys: String, CodingKey {
        case total
        case byTier = "by_tier"
    }
}

public struct Basemap: Codable, Sendable, Equatable {
    public let filename: String
    public let maxzoom: Int
    public let sha256: String
    public let bytes: Int
    public let bbox: [Double]

    func validate() throws {
        guard filename.matches("^[a-z0-9][a-z0-9._-]{0,123}\\.pmtiles$"),
              maxzoom == 14,
              sha256.matches("^[0-9a-f]{64}$"),
              (1...3_221_225_472).contains(bytes),
              bbox.count == 4
        else { throw TileError.invalidManifest }
    }
}

public struct Provenance: Codable, Sendable, Equatable {
    public let taskID: String
    public let model: String
    public let promptVersion: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case model
        case promptVersion = "prompt_version"
    }

    func validate() throws {
        guard ["score", "curiosity", "blurb", "category", "reconcile"].contains(taskID),
              (1...128).contains(model.scalarCount),
              (1...64).contains(promptVersion.scalarCount)
        else { throw TileError.invalidManifest }
    }
}

extension Attribution {
    func validate() throws {
        guard (1...32).contains(source.scalarCount),
              (1...32).contains(license.scalarCount),
              (1...512).contains(text.scalarCount),
              source.isSafeText,
              license.isSafeText,
              text.isSafeText
        else { throw TileError.invalidManifest }
    }
}

public struct PinnedPublish: Codable, Sendable, Equatable {
    public let region: String
    public let publishVersion: String
    public let manifest: Manifest

    public init(region: String, publishVersion: String, manifest: Manifest) {
        self.region = region
        self.publishVersion = publishVersion
        self.manifest = manifest
    }

    public var attribution: [Attribution] { manifest.attribution }

    public var basemapURL: URL? {
        URL(string: "https://\(HTTPTileFetcher.trustedHost)/\(region)/\(publishVersion)/\(manifest.basemap.filename)")
    }

    public var basemapIntegrity: (sha256: String, bytes: Int)? {
        (manifest.basemap.sha256, manifest.basemap.bytes)
    }
}

public struct ManifestPinResult: Sendable, Equatable {
    public let publish: PinnedPublish?
    public let state: TileLoadState
}

public final class ManifestClient: @unchecked Sendable {
    private let region: String
    private let fetcher: TileFetching
    private let cache: TileCache

    public init(region: String, fetcher: TileFetching, cache: TileCache) {
        self.region = region
        self.fetcher = fetcher
        self.cache = cache
    }

    public func refresh() async -> ManifestPinResult {
        do {
            guard region.matches("^[a-z][a-z0-9_]*$") else {
                return ManifestPinResult(publish: nil, state: .unavailable)
            }
            let currentURL = try trustedURL("\(region)/current.json")
            let currentData: Data
            do {
                currentData = try await fetcher.fetch(currentURL)
            } catch {
                return fallback(for: error)
            }
            let publishVersion = try Self.decodeCurrent(currentData)
            let manifestURL = try trustedURL("\(region)/\(publishVersion)/manifest.json")
            let manifestData: Data
            do {
                manifestData = try await fetcher.fetch(manifestURL)
            } catch {
                return fallback(for: error)
            }
            let manifest = try Manifest.decode(manifestData)
            guard manifest.region == region, manifest.publishVersion == publishVersion else {
                throw TileError.invalidManifest
            }
            let cached = try? cache.lastVerifiedPublish(region: region)
            let readerState = VersionGate.reader(
                minReaderVersion: manifest.minReaderVersion,
                hasReadableCache: cached != nil
            )
            if readerState == .updateAvailable {
                return ManifestPinResult(publish: cached, state: .updateAvailable)
            }
            if readerState == .updateRequired {
                return ManifestPinResult(publish: nil, state: .updateRequired)
            }
            let pin = PinnedPublish(region: region, publishVersion: publishVersion, manifest: manifest)
            try cache.recordVerifiedPublish(region: region, publish: pin)
            return ManifestPinResult(publish: pin, state: .ok)
        } catch {
            if let cached = try? cache.lastVerifiedPublish(region: region) {
                return ManifestPinResult(publish: cached, state: .manifestInvalid)
            }
            return ManifestPinResult(publish: nil, state: .unavailable)
        }
    }

    private func fallback(for error: Error) -> ManifestPinResult {
        if let cached = try? cache.lastVerifiedPublish(region: region) {
            return ManifestPinResult(publish: cached, state: .stale)
        }
        return ManifestPinResult(publish: nil, state: .unavailable)
    }

    static func decodeCurrent(_ data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schema_version", "publish_version"],
              let schemaVersion = object["schema_version"] as? Int,
              schemaVersion == 1,
              let publishVersion = object["publish_version"] as? String,
              publishVersion.matches("^[0-9]{8}T[0-9]{6}Z$")
        else { throw TileError.invalidCurrent }
        return publishVersion
    }
}

public enum TileCodec {
    public static let maxCompressedBytes = 1 * 1024 * 1024
    public static let maxUncompressedBytes = 8 * 1024 * 1024

    public static func decode(gzipped data: Data, expectedSHA256: String, expectedBytes: Int) throws -> Data {
        guard data.count == expectedBytes else { throw TileError.byteCountMismatch }
        guard data.count <= maxCompressedBytes else { throw TileError.compressedTooLarge }
        guard sha256(data) == expectedSHA256 else { throw TileError.checksumMismatch }
        return try gunzip(data)
    }

    private static func gunzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw TileError.invalidGzip }
        defer { inflateEnd(&stream) }

        var output = Data()
        var reachedEnd = false
        try data.withUnsafeBytes { inputBuffer in
            guard let inputBase = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw TileError.invalidGzip
            }
            var offset = 0
            while offset < data.count {
                if reachedEnd { throw TileError.invalidGzip }
                let chunkSize = min(65_536, data.count - offset)
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBase.advanced(by: offset))
                stream.avail_in = uInt(chunkSize)

                repeat {
                    var buffer = [UInt8](repeating: 0, count: 65_536)
                    let produced: Int = try buffer.withUnsafeMutableBufferPointer { outBuffer in
                        guard let outBase = outBuffer.baseAddress else { throw TileError.invalidGzip }
                        stream.next_out = outBase
                        stream.avail_out = uInt(outBuffer.count)
                        let status = inflate(&stream, Z_NO_FLUSH)
                        guard status == Z_OK || status == Z_STREAM_END else {
                            throw TileError.invalidGzip
                        }
                        if status == Z_STREAM_END {
                            reachedEnd = true
                            if stream.avail_in != 0 || offset + chunkSize != data.count {
                                throw TileError.invalidGzip
                            }
                        }
                        return outBuffer.count - Int(stream.avail_out)
                    }
                    if produced > 0 {
                        output.append(buffer, count: produced)
                        if output.count > maxUncompressedBytes {
                            throw TileError.inflatedTooLarge
                        }
                    }
                } while stream.avail_out == 0

                offset += chunkSize
            }
        }
        guard reachedEnd else { throw TileError.invalidGzip }
        return output
    }
}

public struct DecodedPlace: Sendable, Equatable {
    public let mapPlace: MapPlace
    public let placeRef: PlaceRef
    public let imageURL: URL?
    public let sourceRefs: [String]
}

public struct DecodedTile: Sendable, Equatable {
    public let places: [DecodedPlace]
    public let missingAttributionSources: Set<String>
}

public enum PlaceContentGuards {
    public static let allowedPlaceKeys: Set<String> = [
        "place_id", "name", "lat", "lon", "category", "tier", "score", "source_refs",
        "alt_names", "blurb", "image_url", "wikipedia_title",
    ]
    public static let allowedImageHosts: Set<String> = ["upload.wikimedia.org", "commons.wikimedia.org"]
    public static let sourceRefPattern = "^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._/-]*$"

    public static func isSafeText(_ text: String) -> Bool {
        text.isSafeText
    }

    public static func isSafeURLString(_ text: String) -> Bool {
        text.isSafeURLString
    }

    public static func isAllowedImageURL(_ url: URL) -> Bool {
        url.scheme == "https" && allowedImageHosts.contains(url.host ?? "")
    }

    public static func isValidSourceRef(_ ref: String) -> Bool {
        ref.scalarCount <= 128 && ref.matches(sourceRefPattern)
    }
}

public enum PlaceDecoder {
    private static let attributionRequiredSources: Set<String> = ["osm", "historic_england", "open_plaques"]

    public static func decode(
        tileData: Data,
        expected: TileCoordinate,
        attributionSources: Set<String>
    ) throws -> DecodedTile {
        guard let object = try JSONSerialization.jsonObject(with: tileData) as? [String: Any],
              Set(object.keys) == ["schema_version", "z", "x", "y", "places"],
              object["schema_version"] as? Int == 1,
              object["z"] as? Int == expected.z,
              object["x"] as? Int == expected.x,
              object["y"] as? Int == expected.y,
              let places = object["places"] as? [[String: Any]],
              places.count <= 4_000
        else { throw TileError.invalidTile }

        var decoded: [DecodedPlace] = []
        var missing: Set<String> = []
        for place in places {
            guard let item = decodePlace(place) else { continue }
            decoded.append(item)
            for source in item.sourceRefs.compactMap(refPrefix) where attributionRequiredSources.contains(source) {
                if !attributionSources.contains(source) {
                    missing.insert(source)
                }
            }
        }
        return DecodedTile(places: decoded, missingAttributionSources: missing)
    }

    private static func decodePlace(_ place: [String: Any]) -> DecodedPlace? {
        guard Set(place.keys).isSubset(of: PlaceContentGuards.allowedPlaceKeys),
              let placeID = place["place_id"] as? String,
              placeID.matches("^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$"),
              let name = place["name"] as? String,
              PlaceContentGuards.isSafeText(name),
              (1...200).contains(name.scalarCount),
              let lat = place["lat"] as? Double,
              lat.isFinite,
              (-90.0...90.0).contains(lat),
              let lon = place["lon"] as? Double,
              lon.isFinite,
              (-180.0...180.0).contains(lon),
              let category = place["category"] as? String,
              PlaceContentGuards.isSafeText(category),
              (1...64).contains(category.scalarCount),
              let tier = place["tier"] as? Int,
              (1...4).contains(tier),
              let score = place["score"] as? Double,
              score.isFinite,
              (0.0...1.0).contains(score),
              let sourceRefs = place["source_refs"] as? [String],
              (1...64).contains(sourceRefs.count),
              Set(sourceRefs).count == sourceRefs.count,
              sourceRefs.allSatisfy(PlaceContentGuards.isValidSourceRef)
        else { return nil }

        if let altNames = place["alt_names"] as? [String] {
            guard altNames.count <= 8,
                  altNames.allSatisfy({ (1...200).contains($0.scalarCount) && PlaceContentGuards.isSafeText($0) })
            else { return nil }
        }
        guard optionalText(place["blurb"], max: 600),
              optionalText(place["wikipedia_title"], max: 300)
        else { return nil }

        var sanitizedPlace = place
        let imageURL: URL?
        if let rawImage = place["image_url"] as? String {
            guard rawImage.scalarCount <= 2_048,
                  PlaceContentGuards.isSafeURLString(rawImage),
                  let url = URL(string: rawImage),
                  url.scheme == "https"
            else { return nil }
            if PlaceContentGuards.isAllowedImageURL(url) {
                imageURL = url
            } else {
                imageURL = nil
                sanitizedPlace["image_url"] = NSNull()
            }
        } else if place.keys.contains("image_url"), !(place["image_url"] is NSNull) {
            return nil
        } else {
            imageURL = nil
        }

        let rawJSON = (try? stableJSONString(sanitizedPlace)) ?? "{}"
        guard let placeRef = try? PlaceRef(
            placeID: placeID,
            name: name,
            lat: lat,
            lon: lon,
            category: category,
            tier: tier,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: rawJSON
        ) else { return nil }

        return DecodedPlace(
            mapPlace: MapPlace(id: placeID, lat: lat, lon: lon, tier: tier),
            placeRef: placeRef,
            imageURL: imageURL,
            sourceRefs: sourceRefs
        )
    }

    private static func optionalText(_ value: Any?, max: Int) -> Bool {
        if value == nil || value is NSNull { return true }
        guard let text = value as? String else { return false }
        return text.scalarCount <= max && PlaceContentGuards.isSafeText(text)
    }

    private static func refPrefix(_ ref: String) -> String? {
        ref.split(separator: ":", maxSplits: 1).first.map(String.init)
    }
}

public enum TileCoverage {
    public static func lonLatToZ10(lat: Double, lon: Double) -> TileCoordinate {
        let n = Double(1 << 10)
        let latRad = lat * .pi / 180.0
        let x = Int((lon + 180.0) / 360.0 * n)
        let y = Int((1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n)
        return TileCoordinate(z: 10, x: clampTile(x), y: clampTile(y))
    }

    public static func tiles(for bbox: BBox, prefetchRadius: Int = PrefetchRing.radius) -> [TileCoordinate] {
        let corners = [
            lonLatToZ10(lat: bbox.minLat, lon: bbox.minLon),
            lonLatToZ10(lat: bbox.minLat, lon: bbox.maxLon),
            lonLatToZ10(lat: bbox.maxLat, lon: bbox.minLon),
            lonLatToZ10(lat: bbox.maxLat, lon: bbox.maxLon),
        ]
        let minX = clampTile((corners.map(\.x).min() ?? 0) - prefetchRadius)
        let maxX = clampTile((corners.map(\.x).max() ?? 0) + prefetchRadius)
        let minY = clampTile((corners.map(\.y).min() ?? 0) - prefetchRadius)
        let maxY = clampTile((corners.map(\.y).max() ?? 0) + prefetchRadius)
        var out: [TileCoordinate] = []
        for x in minX...maxX {
            for y in minY...maxY {
                out.append(TileCoordinate(z: 10, x: x, y: y))
            }
        }
        return out
    }

    private static func clampTile(_ value: Int) -> Int {
        min(1023, max(0, value))
    }
}

public enum PrefetchRing {
    /// Tunable after fast-pan measurement; B3 ships the privacy/cache-friendly 1-tile ring.
    public static let radius = 1
}

public struct RegionIndex: Sendable, Equatable {
    public static let maxBytes = 512 * 1024
    public static let maxRegionCount = 10_000

    public let schemaVersion: Int
    public let minReaderVersion: Int
    public let generatedAt: String?
    public let regions: [Entry]

    public struct Entry: Sendable, Equatable {
        public let id: String
        public let displayName: String
        public let parent: String?
        public let bbox: BBox
        public let publishVersion: String?
        public let basemapBytes: Int
        public let tileCount: Int
        public let bytesWithoutThumbnails: Int
        public let bytesWithThumbnails: Int
    }

    public static func decode(_ data: Data) throws -> RegionIndex {
        guard data.count <= maxBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw TileError.invalidRegionIndex }
        let allowed: Set<String> = ["schema_version", "min_reader_version", "generated_at", "regions"]
        guard Set(object.keys).isSubset(of: allowed),
              let schemaVersion = object["schema_version"] as? Int,
              VersionGate.schema(readerMax: VersionGate.readerSchemaVersion, dataVersion: schemaVersion, minSupported: VersionGate.minSupportedSchemaVersion) == .ok,
              let minReaderVersion = object["min_reader_version"] as? Int,
              minReaderVersion >= 1,
              VersionGate.reader(minReaderVersion: minReaderVersion, hasReadableCache: false) == .ok,
              let entries = object["regions"] as? [[String: Any]],
              entries.count <= maxRegionCount
        else { throw TileError.invalidRegionIndex }
        if let generatedAt = object["generated_at"] as? String {
            guard generatedAt.count <= 32,
                  generatedAt.matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")
            else { throw TileError.invalidRegionIndex }
        } else if object.keys.contains("generated_at"), !(object["generated_at"] is NSNull) {
            throw TileError.invalidRegionIndex
        }
        let regions = try entries.map(decodeEntry)
        guard Set(regions.map(\.id)).count == regions.count else { throw TileError.invalidRegionIndex }
        let knownIDs = Set(regions.map(\.id))
        guard regions.allSatisfy({ $0.parent == nil || knownIDs.contains($0.parent!) }) else {
            throw TileError.invalidRegionIndex
        }
        return RegionIndex(
            schemaVersion: schemaVersion,
            minReaderVersion: minReaderVersion,
            generatedAt: object["generated_at"] as? String,
            regions: regions
        )
    }

    private static func decodeEntry(_ object: [String: Any]) throws -> Entry {
        let allowed: Set<String> = [
            "id", "display_name", "parent", "bbox", "publish_version",
            "basemap_bytes", "tile_count", "bytes_without_thumbnails", "bytes_with_thumbnails",
        ]
        guard Set(object.keys).isSubset(of: allowed),
              let id = object["id"] as? String,
              id.matches("^[a-z][a-z0-9_]{0,63}$"),
              let displayName = object["display_name"] as? String,
              (1...120).contains(displayName.scalarCount),
              displayName.isSafeText,
              let bboxValues = object["bbox"] as? [Double],
              bboxValues.count == 4,
              let basemapBytes = object["basemap_bytes"] as? Int,
              (0...3_221_225_472).contains(basemapBytes),
              let tileCount = object["tile_count"] as? Int,
              (0...1_048_576).contains(tileCount),
              let bytesWithoutThumbnails = object["bytes_without_thumbnails"] as? Int,
              (0...20_000_000_000).contains(bytesWithoutThumbnails),
              let bytesWithThumbnails = object["bytes_with_thumbnails"] as? Int,
              (bytesWithoutThumbnails...20_000_000_000).contains(bytesWithThumbnails)
        else { throw TileError.invalidRegionIndex }
        let parent: String?
        if let value = object["parent"] as? String {
            guard value.matches("^[a-z][a-z0-9_]{0,63}$") else { throw TileError.invalidRegionIndex }
            parent = value
        } else if object.keys.contains("parent"), !(object["parent"] is NSNull) {
            throw TileError.invalidRegionIndex
        } else {
            parent = nil
        }
        let publishVersion: String?
        if let value = object["publish_version"] as? String {
            guard value.matches("^[0-9]{8}T[0-9]{6}Z$") else { throw TileError.invalidRegionIndex }
            publishVersion = value
        } else if object.keys.contains("publish_version"), !(object["publish_version"] is NSNull) {
            throw TileError.invalidRegionIndex
        } else {
            publishVersion = nil
        }
        let bbox = BBox(minLon: bboxValues[0], minLat: bboxValues[1], maxLon: bboxValues[2], maxLat: bboxValues[3])
        guard bbox.minLon >= -180,
              bbox.maxLon <= 180,
              bbox.minLat >= -90,
              bbox.maxLat <= 90,
              bbox.minLon <= bbox.maxLon,
              bbox.minLat <= bbox.maxLat
        else { throw TileError.invalidRegionIndex }
        return Entry(
            id: id,
            displayName: displayName,
            parent: parent,
            bbox: bbox,
            publishVersion: publishVersion,
            basemapBytes: basemapBytes,
            tileCount: tileCount,
            bytesWithoutThumbnails: bytesWithoutThumbnails,
            bytesWithThumbnails: bytesWithThumbnails
        )
    }
}

public struct OfflineTileFetch: Sendable, Equatable {
    public let coordinate: TileCoordinate
    public let sha256: String
    public let bytes: Int

    public init(coordinate: TileCoordinate, sha256: String, bytes: Int) {
        self.coordinate = coordinate
        self.sha256 = sha256
        self.bytes = bytes
    }
}

public struct OfflineRegionUpdatePlan: Sendable, Equatable {
    public let tilesToFetch: [OfflineTileFetch]
    public let reusedTileCount: Int
    public let basemapNeedsFetch: Bool
    public let bytesToFetch: Int
}

public enum StorageHeadroom {
    public static let defaultReserveBytes: Int64 = 512 * 1024 * 1024

    public static func hasHeadroom(requiredBytes: Int, availableBytes: Int64?, reserveBytes: Int64 = defaultReserveBytes) -> Bool {
        guard requiredBytes >= 0, let availableBytes else { return false }
        return availableBytes >= Int64(requiredBytes) + reserveBytes
    }

    public static func availableBytes(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))
            .flatMap(\.volumeAvailableCapacityForImportantUsage)
    }
}

public enum OfflineDownloadSession {
    public static func configuration(identifier: String) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = true
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.httpAdditionalHeaders = nil
        return configuration
    }
}

public struct OfflineRegionDownloadResult: Sendable, Equatable {
    public let publish: PinnedPublish
    public let fetchedTileCount: Int
    public let reusedTileCount: Int
    public let fetchedBytes: Int
}

public final class OfflineRegionDownloader: @unchecked Sendable {
    private let region: String
    private let fetcher: TileFetching
    private let store: OfflineRegionStore
    private let availableBytes: @Sendable () -> Int64?

    public init(
        region: String,
        fetcher: TileFetching,
        store: OfflineRegionStore,
        availableBytes: @escaping @Sendable () -> Int64?
    ) {
        self.region = region
        self.fetcher = fetcher
        self.store = store
        self.availableBytes = availableBytes
    }

    public func downloadCurrentRegion() async throws -> OfflineRegionDownloadResult {
        guard region.matches("^[a-z][a-z0-9_]{0,63}$") else { throw TileError.invalidOfflinePack }
        let currentData = try await fetcher.fetch(try trustedURL("\(region)/current.json"))
        let publishVersion = try ManifestClient.decodeCurrent(currentData)
        let manifestData = try await fetcher.fetch(try trustedURL("\(region)/\(publishVersion)/manifest.json"))
        let manifest = try Manifest.decode(manifestData)
        guard manifest.region == region, manifest.publishVersion == publishVersion else {
            throw TileError.invalidManifest
        }
        let publish = PinnedPublish(region: region, publishVersion: publishVersion, manifest: manifest)
        let plan = try store.updatePlan(for: publish)
        guard StorageHeadroom.hasHeadroom(requiredBytes: plan.bytesToFetch, availableBytes: availableBytes()) else {
            throw TileError.insufficientStorage
        }

        var tiles: [TileCoordinate: Data] = [:]
        for item in plan.tilesToFetch {
            let data = try await fetcher.fetch(try trustedURL("\(region)/\(publishVersion)/tiles/10/\(item.coordinate.x)/\(item.coordinate.y).json.gz"))
            _ = try TileCodec.decode(gzipped: data, expectedSHA256: item.sha256, expectedBytes: item.bytes)
            tiles[item.coordinate] = data
        }
        let basemap: Data?
        if plan.basemapNeedsFetch {
            let data = try await fetcher.fetch(try trustedURL("\(region)/\(publishVersion)/\(manifest.basemap.filename)"))
            guard data.count == manifest.basemap.bytes, sha256(data) == manifest.basemap.sha256 else {
                throw TileError.checksumMismatch
            }
            basemap = data
        } else {
            basemap = nil
        }
        try store.install(publish: publish, tiles: tiles, basemap: basemap)
        return OfflineRegionDownloadResult(
            publish: publish,
            fetchedTileCount: plan.tilesToFetch.count,
            reusedTileCount: plan.reusedTileCount,
            fetchedBytes: plan.bytesToFetch
        )
    }
}

public final class OfflineRegionStore: @unchecked Sendable {
    private let root: URL
    private let fm = FileManager.default
    private let lock = NSLock()

    public init(root: URL) throws {
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try excludeFromBackup(root)
    }

    public static func documentsStore() throws -> OfflineRegionStore {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try OfflineRegionStore(root: documents.appendingPathComponent("MakingTracks/OfflineRegions", isDirectory: true))
    }

    public func install(publish: PinnedPublish, tiles: [TileCoordinate: Data], basemap: Data?) throws {
        try withLock {
            try installLocked(publish: publish, tiles: tiles, basemap: basemap)
        }
    }

    private func installLocked(publish: PinnedPublish, tiles: [TileCoordinate: Data], basemap: Data?) throws {
        guard publish.region.matches("^[a-z][a-z0-9_]*$"),
              publish.publishVersion.matches("^[0-9]{8}T[0-9]{6}Z$"),
              publish.region == publish.manifest.region,
              publish.publishVersion == publish.manifest.publishVersion
        else { throw TileError.invalidOfflinePack }
        let requiredCoordinates = Set(publish.manifest.tiles.map { TileCoordinate(z: publish.manifest.tileZ, x: $0.x, y: $0.y) })
        guard Set(tiles.keys).isSubset(of: requiredCoordinates) else { throw TileError.invalidOfflinePack }
        if let basemap {
            guard basemap.count == publish.manifest.basemap.bytes,
                  sha256(basemap) == publish.manifest.basemap.sha256
            else { throw TileError.checksumMismatch }
        } else {
            try verifyExistingBasemapObject(sha256: publish.manifest.basemap.sha256, bytes: publish.manifest.basemap.bytes)
        }
        for manifestTile in publish.manifest.tiles {
            let coordinate = TileCoordinate(z: publish.manifest.tileZ, x: manifestTile.x, y: manifestTile.y)
            if let data = tiles[coordinate] {
                _ = try TileCodec.decode(gzipped: data, expectedSHA256: manifestTile.sha256, expectedBytes: manifestTile.bytes)
            } else {
                try verifyExistingTileObject(sha256: manifestTile.sha256, bytes: manifestTile.bytes)
            }
        }

        let temp = root.appendingPathComponent("tmp/\(UUID().uuidString)", isDirectory: true)
        let backup = root.appendingPathComponent("tmp/\(UUID().uuidString)-backup", isDirectory: true)
        let final = packURL(region: publish.region, publishVersion: publish.publishVersion)
        do {
            try fm.createDirectory(at: tileObjectsURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: basemapObjectsURL, withIntermediateDirectories: true)
            for manifestTile in publish.manifest.tiles {
                let coordinate = TileCoordinate(z: publish.manifest.tileZ, x: manifestTile.x, y: manifestTile.y)
                if let data = tiles[coordinate] {
                    try writeVerifiedTileObject(data, sha256: manifestTile.sha256, bytes: manifestTile.bytes)
                }
            }
            if let basemap {
                try writeVerifiedBasemapObject(basemap, sha256: publish.manifest.basemap.sha256, bytes: publish.manifest.basemap.bytes)
            }

            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            try JSONEncoder().encode(publish).write(to: temp.appendingPathComponent("manifest-snapshot.json"), options: .atomic)
            try JSONEncoder().encode(OfflinePackIndex(
                region: publish.region,
                publishVersion: publish.publishVersion,
                tileSHAs: Dictionary(uniqueKeysWithValues: publish.manifest.tiles.map {
                    ("\($0.x)/\($0.y)", $0.sha256)
                }),
                basemapSHA: publish.manifest.basemap.sha256
            )).write(to: temp.appendingPathComponent("pack-index.json"), options: .atomic)
            try excludeFromBackup(temp)
            try fm.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: final.path) {
                try fm.moveItem(at: final, to: backup)
            }
            try fm.moveItem(at: temp, to: final)
            try excludeFromBackup(final)
            let regionDirectory = regionURL(region: publish.region)
            try fm.createDirectory(at: regionDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(OfflineCurrentPack(publishVersion: publish.publishVersion))
                .write(to: regionDirectory.appendingPathComponent("current-pack.json"), options: .atomic)
            if fm.fileExists(atPath: backup.path) {
                try fm.removeItem(at: backup)
            }
        } catch {
            if fm.fileExists(atPath: temp.path) {
                try? fm.removeItem(at: temp)
            }
            if fm.fileExists(atPath: final.path), fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: final)
            }
            if fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: final)
            }
            try? garbageCollectObjects()
            throw error
        }
    }

    public func installedPublish(region: String) throws -> PinnedPublish? {
        try withLock {
            try installedPublishLocked(region: region)
        }
    }

    private func installedPublishLocked(region: String) throws -> PinnedPublish? {
        guard isValidRegion(region) else { throw TileError.invalidOfflinePack }
        let currentURL = regionURL(region: region).appendingPathComponent("current-pack.json")
        guard fm.fileExists(atPath: currentURL.path) else { return nil }
        let current = try JSONDecoder().decode(OfflineCurrentPack.self, from: Data(contentsOf: currentURL))
        guard isValidPublishVersion(current.publishVersion) else { throw TileError.invalidOfflinePack }
        let manifestURL = packURL(region: region, publishVersion: current.publishVersion).appendingPathComponent("manifest-snapshot.json")
        let publish = try JSONDecoder().decode(PinnedPublish.self, from: Data(contentsOf: manifestURL))
        let strictManifest = try Manifest.decode(try JSONEncoder().encode(publish.manifest))
        guard publish.region == region,
              publish.publishVersion == current.publishVersion,
              strictManifest.region == region,
              strictManifest.publishVersion == current.publishVersion
        else { throw TileError.invalidOfflinePack }
        return PinnedPublish(region: publish.region, publishVersion: publish.publishVersion, manifest: strictManifest)
    }

    public func updatePlan(for target: PinnedPublish) throws -> OfflineRegionUpdatePlan {
        try withLock {
            try updatePlanLocked(for: target)
        }
    }

    private func updatePlanLocked(for target: PinnedPublish) throws -> OfflineRegionUpdatePlan {
        guard target.region == target.manifest.region,
              target.publishVersion == target.manifest.publishVersion,
              isValidRegion(target.region),
              isValidPublishVersion(target.publishVersion)
        else { throw TileError.invalidOfflinePack }
        var reused = 0
        var fetches: [OfflineTileFetch] = []
        for tile in target.manifest.tiles {
            if (try? verifyExistingTileObject(sha256: tile.sha256, bytes: tile.bytes)) != nil {
                reused += 1
            } else {
                fetches.append(OfflineTileFetch(coordinate: TileCoordinate(z: target.manifest.tileZ, x: tile.x, y: tile.y), sha256: tile.sha256, bytes: tile.bytes))
            }
        }
        let basemapNeedsFetch = (try? verifyExistingBasemapObject(sha256: target.manifest.basemap.sha256, bytes: target.manifest.basemap.bytes)) == nil
        let tileBytes = fetches.reduce(0) { $0 + $1.bytes }
        return OfflineRegionUpdatePlan(
            tilesToFetch: fetches,
            reusedTileCount: reused,
            basemapNeedsFetch: basemapNeedsFetch,
            bytesToFetch: tileBytes + (basemapNeedsFetch ? target.manifest.basemap.bytes : 0)
        )
    }

    public func tile(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String) -> Data? {
        withLock {
            tileLocked(region: region, publishVersion: publishVersion, coordinate: coordinate, sha256: sha256)
        }
    }

    private func tileLocked(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String) -> Data? {
        guard isValidRegion(region),
              isValidPublishVersion(publishVersion),
              coordinate.z == 10,
              (0...1023).contains(coordinate.x),
              (0...1023).contains(coordinate.y),
              sha256.matches("^[0-9a-f]{64}$")
        else { return nil }
        guard fm.fileExists(atPath: packURL(region: region, publishVersion: publishVersion).path) else { return nil }
        return try? Data(contentsOf: tileObjectURL(sha256: sha256))
    }

    public func basemapURL(region: String, publishVersion: String, sha256: String, bytes: Int) -> URL? {
        withLock {
            basemapURLLocked(region: region, publishVersion: publishVersion, sha256: sha256, bytes: bytes)
        }
    }

    private func basemapURLLocked(region: String, publishVersion: String, sha256: String, bytes: Int) -> URL? {
        guard isValidRegion(region),
              isValidPublishVersion(publishVersion),
              sha256.matches("^[0-9a-f]{64}$"),
              bytes > 0
        else { return nil }
        guard fm.fileExists(atPath: packURL(region: region, publishVersion: publishVersion).path),
              (try? verifyExistingBasemapObject(sha256: sha256, bytes: bytes)) != nil
        else { return nil }
        return basemapObjectURL(sha256: sha256)
    }

    public func delete(region: String) throws {
        try withLock {
            try deleteLocked(region: region)
        }
    }

    private func deleteLocked(region: String) throws {
        guard isValidRegion(region) else { throw TileError.invalidOfflinePack }
        let packs = root.appendingPathComponent("packs").appendingPathComponent(region)
        if fm.fileExists(atPath: packs.path) {
            try fm.removeItem(at: packs)
        }
        let regionDirectory = regionURL(region: region)
        if fm.fileExists(atPath: regionDirectory.path) {
            try fm.removeItem(at: regionDirectory)
        }
        try garbageCollectObjects()
    }

    func packURL(region: String, publishVersion: String) -> URL {
        root.appendingPathComponent("packs").appendingPathComponent(region).appendingPathComponent(publishVersion, isDirectory: true)
    }

    func regionURL(region: String) -> URL {
        root.appendingPathComponent("regions").appendingPathComponent(region, isDirectory: true)
    }

    private var tileObjectsURL: URL {
        root.appendingPathComponent("objects/tiles", isDirectory: true)
    }

    private var basemapObjectsURL: URL {
        root.appendingPathComponent("objects/basemaps", isDirectory: true)
    }

    private func tileObjectURL(sha256: String) -> URL {
        tileObjectsURL.appendingPathComponent("\(sha256).json.gz")
    }

    private func basemapObjectURL(sha256: String) -> URL {
        basemapObjectsURL.appendingPathComponent("\(sha256).pmtiles")
    }

    private func writeVerifiedTileObject(_ data: Data, sha256: String, bytes: Int) throws {
        let url = tileObjectURL(sha256: sha256)
        if (try? verifyExistingTileObject(sha256: sha256, bytes: bytes)) != nil { return }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try verifyExistingTileObject(sha256: sha256, bytes: bytes)
    }

    private func writeVerifiedBasemapObject(_ data: Data, sha256: String, bytes: Int) throws {
        let url = basemapObjectURL(sha256: sha256)
        if (try? verifyExistingBasemapObject(sha256: sha256, bytes: bytes)) != nil { return }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try verifyExistingBasemapObject(sha256: sha256, bytes: bytes)
    }

    private func verifyExistingTileObject(sha256: String, bytes: Int) throws {
        let data = try Data(contentsOf: tileObjectURL(sha256: sha256))
        _ = try TileCodec.decode(gzipped: data, expectedSHA256: sha256, expectedBytes: bytes)
    }

    private func verifyExistingBasemapObject(sha256 expectedSHA256: String, bytes: Int) throws {
        let url = basemapObjectURL(sha256: expectedSHA256)
        let data = try Data(contentsOf: url)
        guard data.count == bytes, sha256(data) == expectedSHA256 else {
            throw TileError.checksumMismatch
        }
    }

    private func garbageCollectObjects() throws {
        let references = try referencedObjects()
        try removeUnreferencedObjects(in: tileObjectsURL, keeping: references.tileSHAs, extension: "gz")
        try removeUnreferencedObjects(in: basemapObjectsURL, keeping: references.basemapSHAs, extension: "pmtiles")
    }

    private func referencedObjects() throws -> (tileSHAs: Set<String>, basemapSHAs: Set<String>) {
        let packsRoot = root.appendingPathComponent("packs")
        guard let enumerator = fm.enumerator(at: packsRoot, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return ([], [])
        }
        var tileSHAs = Set<String>()
        var basemapSHAs = Set<String>()
        for case let url as URL in enumerator where url.lastPathComponent == "pack-index.json" {
            let index = try JSONDecoder().decode(OfflinePackIndex.self, from: Data(contentsOf: url))
            tileSHAs.formUnion(index.tileSHAs.values)
            basemapSHAs.insert(index.basemapSHA)
        }
        return (tileSHAs, basemapSHAs)
    }

    private func removeUnreferencedObjects(in directory: URL, keeping references: Set<String>, extension pathExtension: String) throws {
        guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for child in children where child.pathExtension == pathExtension {
            let sha = child.deletingPathExtension().lastPathComponent
            if !references.contains(sha) {
                try? fm.removeItem(at: child)
            }
        }
    }

    private func isValidRegion(_ value: String) -> Bool {
        value.matches("^[a-z][a-z0-9_]{0,63}$")
    }

    private func isValidPublishVersion(_ value: String) -> Bool {
        value.matches("^[0-9]{8}T[0-9]{6}Z$")
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}

private struct OfflineCurrentPack: Codable {
    let publishVersion: String
}

private struct OfflinePackIndex: Codable {
    let region: String
    let publishVersion: String
    let tileSHAs: [String: String]
    let basemapSHA: String
}

public final class TileCache: @unchecked Sendable {
    /// Tunable budget; B7 offline packs are intentionally outside this B3 cache.
    public static let maxBytes = 64 * 1024 * 1024

    private let directory: URL
    private let maxBytes: Int
    private let fm = FileManager.default
    private let lock = NSLock()
    private var accessCounter: Int
    private var accessEntries: [String: Int]

    public init(directory: URL, maxBytes: Int = TileCache.maxBytes) throws {
        self.directory = directory
        self.maxBytes = maxBytes
        if let stored = try? JSONDecoder().decode(TileAccess.self, from: Data(contentsOf: directory.appendingPathComponent("tile-access.json"))) {
            accessCounter = stored.next
            accessEntries = stored.entries
        } else {
            accessCounter = 1
            accessEntries = [:]
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func recordVerifiedPublish(region: String, publish: PinnedPublish) throws {
        let data = try JSONEncoder().encode(publish)
        let url = manifestURL(region: region)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func lastVerifiedPublish(region: String) throws -> PinnedPublish? {
        let url = manifestURL(region: region)
        guard fm.fileExists(atPath: url.path) else { return nil }
        let cached = try JSONDecoder().decode(PinnedPublish.self, from: Data(contentsOf: url))
        let strictManifest = try Manifest.decode(try JSONEncoder().encode(cached.manifest))
        return PinnedPublish(region: cached.region, publishVersion: cached.publishVersion, manifest: strictManifest)
    }

    public func storeTile(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String, data: Data) throws {
        let url = tileURL(region: region, publishVersion: publishVersion, coordinate: coordinate, sha256: sha256)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try touch(url)
        try trimIfNeeded()
    }

    public func tile(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String) -> Data? {
        let url = tileURL(region: region, publishVersion: publishVersion, coordinate: coordinate, sha256: sha256)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? touch(url)
        return data
    }

    public func evictPublish(region: String, publishVersion: String) {
        try? fm.removeItem(at: directory.appendingPathComponent(region).appendingPathComponent(publishVersion))
    }

    public func purgeNonPinned(region: String, pinnedPublishVersion: String) {
        let root = directory.appendingPathComponent(region)
        guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for child in children where child.lastPathComponent != pinnedPublishVersion && child.lastPathComponent != "last-publish.json" {
            try? fm.removeItem(at: child)
        }
    }

    private func manifestURL(region: String) -> URL {
        directory.appendingPathComponent(region).appendingPathComponent("last-publish.json")
    }

    private func tileURL(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String) -> URL {
        directory
            .appendingPathComponent(region)
            .appendingPathComponent(publishVersion)
            .appendingPathComponent("tiles")
            .appendingPathComponent(String(coordinate.z))
            .appendingPathComponent(String(coordinate.x))
            .appendingPathComponent("\(coordinate.y)-\(sha256).json.gz")
    }

    private func trimIfNeeded() throws {
        let access = accessSnapshot()
        let files = try tileFiles()
        var total = files.reduce(0) { $0 + $1.bytes }
        for file in files.sorted(by: { access[cacheKey($0.url), default: 0] < access[cacheKey($1.url), default: 0] }) where total > maxBytes {
            try? fm.removeItem(at: file.url)
            total -= file.bytes
        }
    }

    private func tileFiles() throws -> [(url: URL, bytes: Int)] {
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return []
        }
        var files: [(URL, Int)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true, url.pathExtension == "gz" {
                files.append((url, values.fileSize ?? 0))
            }
        }
        return files
    }

    private func touch(_ url: URL) throws {
        lock.lock()
        accessEntries[cacheKey(url)] = accessCounter
        accessCounter += 1
        let snapshot = TileAccess(next: accessCounter, entries: accessEntries)
        lock.unlock()
        try JSONEncoder().encode(snapshot).write(to: accessURL, options: .atomic)
    }

    private var accessURL: URL {
        directory.appendingPathComponent("tile-access.json")
    }

    private func accessSnapshot() -> [String: Int] {
        lock.lock()
        let snapshot = accessEntries
        lock.unlock()
        return snapshot
    }

    private func cacheKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}

private struct TileAccess: Codable {
    var next: Int
    var entries: [String: Int]
}

public enum TileFetchConcurrency {
    /// Bounded concurrency for viewport tile fetch/decode work; tune after pan telemetry.
    public static let maxConcurrent = 4
}

public actor TileClient {
    // Tunable: enough refs for open/recent card actions after panning, still a hard memory bound.
    private static let recentPlaceRefLimit = 128

    private let region: String
    private let fetcher: TileFetching
    private let cache: TileCache
    private let offlineStore: OfflineRegionStore?
    private var pin: PinnedPublish?
    private var state: TileLoadState = .unavailable
    private var loadedPlaces: [String: DecodedPlace] = [:]
    private var recentPlaceRefs: [String: PlaceRef] = [:]
    private var recentPlaceRefOrder: [String] = []
    private var viewportGeneration = 0

    public init(region: String, fetcher: TileFetching, cache: TileCache, offlineStore: OfflineRegionStore? = nil) {
        self.region = region
        self.fetcher = fetcher
        self.cache = cache
        self.offlineStore = offlineStore
    }

    public func refreshPin() async throws {
        let oldPublishVersion = pin?.publishVersion
        let result = await ManifestClient(region: region, fetcher: fetcher, cache: cache).refresh()
        let installed = try? offlineStore?.installedPublish(region: region)
        let resolved = resolvePin(remote: result, installed: installed)
        pin = resolved.publish
        state = resolved.state
        if oldPublishVersion != resolved.publish?.publishVersion {
            clearLoadedPlaceRefs()
        }
        if let pin {
            cache.purgeNonPinned(region: region, pinnedPublishVersion: pin.publishVersion)
        }
    }

    public func places(inViewport bbox: BBox, zoom: Int) async -> [MapPlace] {
        if pin == nil {
            try? await refreshPin()
        }
        guard let pin else { return [] }
        viewportGeneration += 1
        let generation = viewportGeneration

        let needed = Set(TileCoverage.tiles(for: bbox).filter { coordinate in
            pin.manifest.tiles.contains { $0.x == coordinate.x && $0.y == coordinate.y }
        }).sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) })
        var output: [MapPlace] = []
        var viewportPlaces: [String: DecodedPlace] = [:]
        let attributionSources = Set(pin.manifest.attribution.map(\.source))
        var usedCache = false
        var trustedTile = false
        var missingTile = false

        await withTaskGroup(of: TileLoadResult.self) { group in
            var iterator = needed.makeIterator()
            for _ in 0..<TileFetchConcurrency.maxConcurrent {
                guard let coordinate = iterator.next(),
                      let tile = pin.manifest.tiles.first(where: { $0.x == coordinate.x && $0.y == coordinate.y })
                else { break }
                group.addTask {
                    await loadTile(
                        region: self.region,
                        publish: pin,
                        coordinate: coordinate,
                        tile: tile,
                        attributionSources: attributionSources,
                        fetcher: self.fetcher,
                        cache: self.cache,
                        offlineStore: self.offlineStore
                    )
                }
            }
            while let result = await group.next() {
                if generation != viewportGeneration {
                    group.cancelAll()
                    return
                }
                switch result {
                case .loaded(let decoded, let source):
                    switch source {
                    case .cache:
                        usedCache = true
                    case .network:
                        trustedTile = true
                    case .offlinePack:
                        trustedTile = true
                    }
                    if !decoded.missingAttributionSources.isEmpty {
                        cache.evictPublish(region: region, publishVersion: pin.publishVersion)
                        self.pin = nil
                        clearLoadedPlaceRefs()
                        state = .manifestInvalid
                        group.cancelAll()
                        return
                    }
                    for place in decoded.places {
                        viewportPlaces[place.mapPlace.id] = place
                        output.append(place.mapPlace)
                    }
                case .missing:
                    missingTile = true
                case .invalid:
                    missingTile = true
                }
                guard let coordinate = iterator.next(),
                      let tile = pin.manifest.tiles.first(where: { $0.x == coordinate.x && $0.y == coordinate.y })
                else { continue }
                group.addTask {
                    await loadTile(
                        region: self.region,
                        publish: pin,
                        coordinate: coordinate,
                        tile: tile,
                        attributionSources: attributionSources,
                        fetcher: self.fetcher,
                        cache: self.cache,
                        offlineStore: self.offlineStore
                    )
                }
            }
        }
        guard generation == viewportGeneration else { return [] }
        if state == .manifestInvalid { return [] }
        loadedPlaces = viewportPlaces
        if usedCache {
            state = .stale
        } else if trustedTile, state != .updateAvailable {
            state = .ok
        } else if missingTile, !needed.isEmpty, state != .updateAvailable {
            state = .unavailable
        }
        return output.sorted(by: { $0.id < $1.id })
    }

    public func isPresentInCurrentTiles(_ placeID: String) async -> Bool {
        loadedPlaces[placeID] != nil
    }

    public func placeRef(for placeID: String) async -> PlaceRef? {
        if let placeRef = loadedPlaces[placeID]?.placeRef {
            rememberRecentPlaceRef(placeRef)
            return placeRef
        }
        return recentPlaceRefs[placeID]
    }

    private func rememberRecentPlaceRef(_ placeRef: PlaceRef) {
        recentPlaceRefs[placeRef.placeID] = placeRef
        recentPlaceRefOrder.removeAll { $0 == placeRef.placeID }
        recentPlaceRefOrder.append(placeRef.placeID)
        while recentPlaceRefOrder.count > Self.recentPlaceRefLimit {
            let evicted = recentPlaceRefOrder.removeFirst()
            recentPlaceRefs[evicted] = nil
        }
    }

    private func clearLoadedPlaceRefs() {
        loadedPlaces.removeAll()
        recentPlaceRefs.removeAll()
        recentPlaceRefOrder.removeAll()
    }

    public var attribution: [Attribution] {
        get async { pin?.attribution ?? [] }
    }

    public var basemapURL: URL? {
        get async {
            guard let pin else { return nil }
            return offlineStore?.basemapURL(
                region: pin.region,
                publishVersion: pin.publishVersion,
                sha256: pin.manifest.basemap.sha256,
                bytes: pin.manifest.basemap.bytes
            ) ?? pin.basemapURL
        }
    }

    public var basemapIntegrity: (sha256: String, bytes: Int)? {
        get async { pin?.basemapIntegrity }
    }

    public var loadState: TileLoadState {
        get async { state }
    }

    private func resolvePin(remote: ManifestPinResult, installed: PinnedPublish?) -> ManifestPinResult {
        guard let installed else { return remote }
        guard let remotePublish = remote.publish else {
            let resolvedState: TileLoadState = switch remote.state {
            case .updateRequired:
                .updateAvailable
            case .unavailable:
                .offline
            default:
                remote.state
            }
            return ManifestPinResult(publish: installed, state: resolvedState)
        }
        if remote.state == .ok, remotePublish.publishVersion != installed.publishVersion {
            return ManifestPinResult(publish: installed, state: .updateAvailable)
        }
        if remotePublish.publishVersion == installed.publishVersion {
            return ManifestPinResult(publish: installed, state: remote.state == .stale ? .stale : .ok)
        }
        return ManifestPinResult(publish: installed, state: .updateAvailable)
    }
}

private enum TileLoadSource: Sendable {
    case network
    case cache
    case offlinePack
}

private enum TileLoadResult: Sendable {
    case loaded(DecodedTile, TileLoadSource)
    case missing
    case invalid
}

private func loadTile(
    region: String,
    publish: PinnedPublish,
    coordinate: TileCoordinate,
    tile: ManifestTile,
    attributionSources: Set<String>,
    fetcher: TileFetching,
    cache: TileCache,
    offlineStore: OfflineRegionStore?
) async -> TileLoadResult {
    var gzipped: Data
    var source: TileLoadSource
    if let offline = offlineStore?.tile(
        region: region,
        publishVersion: publish.publishVersion,
        coordinate: coordinate,
        sha256: tile.sha256
    ) {
        gzipped = offline
        source = .offlinePack
    } else {
        do {
        gzipped = try await fetcher.fetch(try trustedURL("\(region)/\(publish.publishVersion)/tiles/10/\(coordinate.x)/\(coordinate.y).json.gz"))
        _ = try TileCodec.decode(gzipped: gzipped, expectedSHA256: tile.sha256, expectedBytes: tile.bytes)
        try cache.storeTile(region: region, publishVersion: publish.publishVersion, coordinate: coordinate, sha256: tile.sha256, data: gzipped)
        source = .network
        } catch let error as TileError {
            switch error {
            case .checksumMismatch, .byteCountMismatch, .compressedTooLarge, .inflatedTooLarge, .invalidGzip, .invalidTile:
                guard let cached = cache.tile(region: region, publishVersion: publish.publishVersion, coordinate: coordinate, sha256: tile.sha256) else {
                    return .missing
                }
                gzipped = cached
                source = .cache
            default:
                guard let cached = cache.tile(region: region, publishVersion: publish.publishVersion, coordinate: coordinate, sha256: tile.sha256) else {
                    return .missing
                }
                gzipped = cached
                source = .cache
            }
        } catch {
            guard let cached = cache.tile(region: region, publishVersion: publish.publishVersion, coordinate: coordinate, sha256: tile.sha256) else {
                return .missing
            }
            gzipped = cached
            source = .cache
        }
    }

    do {
        let raw = try TileCodec.decode(gzipped: gzipped, expectedSHA256: tile.sha256, expectedBytes: tile.bytes)
        let decoded = try PlaceDecoder.decode(tileData: raw, expected: coordinate, attributionSources: attributionSources)
        return .loaded(decoded, source)
    } catch {
        return .missing
    }
}

func trustedURL(_ path: String) throws -> URL {
    guard let url = URL(string: "https://\(HTTPTileFetcher.trustedHost)/\(path)") else {
        throw TileError.invalidURL
    }
    try HTTPTileFetcher.validateOrigin(url)
    return url
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func stableJSONString(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

extension String {
    var scalarCount: Int {
        unicodeScalars.count
    }

    var isSafeText: Bool {
        unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x0000...0x001f, 0x007f...0x009f,
                 0x200b...0x200d, 0x2028...0x2029, 0x202a...0x202e,
                 0x2060, 0x2066...0x2069, 0xfeff:
                return false
            default:
                return true
            }
        }
    }

    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) == startIndex..<endIndex
    }

    var isSafeURLString: Bool {
        !isEmpty && unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x0000...0x001f, 0x007f...0x009f, 0x20:
                return false
            default:
                return true
            }
        }
    }
}
