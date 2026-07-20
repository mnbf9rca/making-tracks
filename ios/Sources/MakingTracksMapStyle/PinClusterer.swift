import Foundation
import MakingTracksData

public struct PinCluster: Sendable, Equatable {
    public let id: String
    public let lat: Double
    public let lon: Double
    public let minLat: Double
    public let minLon: Double
    public let maxLat: Double
    public let maxLon: Double
    public let count: Int
    public let memberIDs: [String]

    public init(
        id: String,
        lat: Double,
        lon: Double,
        minLat: Double? = nil,
        minLon: Double? = nil,
        maxLat: Double? = nil,
        maxLon: Double? = nil,
        count: Int,
        memberIDs: [String]
    ) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.minLat = minLat ?? lat
        self.minLon = minLon ?? lon
        self.maxLat = maxLat ?? lat
        self.maxLon = maxLon ?? lon
        self.count = count
        self.memberIDs = memberIDs
    }
}

public enum PinRenderFeature: Sendable, Equatable {
    case cluster(PinCluster)
    case singleton(MapPlace, PinState)
}

public struct PinRenderSnapshot: Sendable {
    public let renderFeatures: [PinRenderFeature]
    public let clusters: [PinCluster]
    public let singletons: [(MapPlace, PinState)]
}

public enum PinClusterer {
    public struct Options: Sendable, Equatable {
        public let zoom: Int
        public let radiusPoints: Double
        public let maximumClusterZoom: Int
        public let visibleCategories: Set<String>?

        public init(
            zoom: Int,
            radiusPoints: Double,
            maximumClusterZoom: Int = PinLayers.maximumClusterZoom,
            visibleCategories: Set<String>? = nil
        ) {
            self.zoom = zoom
            self.radiusPoints = max(1, radiusPoints)
            self.maximumClusterZoom = maximumClusterZoom
            self.visibleCategories = visibleCategories
        }
    }

    private struct ProjectedFeature {
        let place: MapPlace
        let state: PinState
        let x: Double
        let y: Double
    }

    private struct GridCell: Hashable {
        let x: Int
        let y: Int
    }

    public static func renderFeatures(
        _ features: [(MapPlace, PinState)],
        options: Options
    ) -> PinRenderSnapshot {
        let visibleFeatures = features
            .filter { place, _ in PinLayers.isCategoryVisible(place.category, visibleCategories: options.visibleCategories) }
            .sorted { lhs, rhs in lhs.0.id < rhs.0.id }

        guard options.zoom <= options.maximumClusterZoom else {
            return PinRenderSnapshot(
                renderFeatures: visibleFeatures.map { .singleton($0.0, $0.1) },
                clusters: [],
                singletons: visibleFeatures
            )
        }

        let projected = visibleFeatures.map { place, state in
            let point = project(lat: place.lat, lon: place.lon, zoom: options.zoom)
            return ProjectedFeature(place: place, state: state, x: point.x, y: point.y)
        }
        let cellSize = max(1, options.radiusPoints / 2.0.squareRoot())
        let neighborReach = Int(ceil(options.radiusPoints / cellSize))
        let grid = Dictionary(grouping: projected) { feature in
            gridCell(x: feature.x, y: feature.y, cellSize: cellSize)
        }
        var consumed = Set<String>()
        var renderFeatures: [PinRenderFeature] = []
        var clusters: [PinCluster] = []
        var singletons: [(MapPlace, PinState)] = []

        for seed in projected {
            guard !consumed.contains(seed.place.id) else { continue }
            let seedCell = gridCell(x: seed.x, y: seed.y, cellSize: cellSize)
            let members = nearbyFeatures(seedCell, reach: neighborReach, in: grid)
                .filter { candidate in
                    !consumed.contains(candidate.place.id)
                        && distance(seed, candidate) <= options.radiusPoints
                }
                .sorted { lhs, rhs in lhs.place.id < rhs.place.id }
            guard members.count >= PinLayers.minimumClusterPointCount else {
                consumed.insert(seed.place.id)
                let singleton = (seed.place, seed.state)
                singletons.append(singleton)
                renderFeatures.append(.singleton(seed.place, seed.state))
                continue
            }

            for member in members {
                consumed.insert(member.place.id)
            }
            let memberIDs = members.map(\.place.id).sorted()
            let count = members.count
            let lat = members.map(\.place.lat).reduce(0, +) / Double(count)
            let lon = members.map(\.place.lon).reduce(0, +) / Double(count)
            let lats = members.map(\.place.lat)
            let lons = members.map(\.place.lon)
            let cluster = PinCluster(
                id: "manual-cluster-z\(options.zoom)-\(stableClusterHash(memberIDs))",
                lat: lat,
                lon: lon,
                minLat: lats.min() ?? lat,
                minLon: lons.min() ?? lon,
                maxLat: lats.max() ?? lat,
                maxLon: lons.max() ?? lon,
                count: count,
                memberIDs: memberIDs
            )
            clusters.append(cluster)
            renderFeatures.append(.cluster(cluster))
        }

        return PinRenderSnapshot(
            renderFeatures: renderFeatures,
            clusters: clusters,
            singletons: singletons.sorted { lhs, rhs in lhs.0.id < rhs.0.id }
        )
    }

    private static func distance(_ lhs: ProjectedFeature, _ rhs: ProjectedFeature) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func project(lat: Double, lon: Double, zoom: Int) -> (x: Double, y: Double) {
        let scale = 256.0 * pow(2.0, Double(max(0, zoom)))
        let clampedLat = min(85.05112878, max(-85.05112878, lat))
        let x = (lon + 180.0) / 360.0 * scale
        let latRad = clampedLat * .pi / 180.0
        let y = (1.0 - log(tan(latRad) + (1.0 / cos(latRad))) / .pi) / 2.0 * scale
        return (x, y)
    }

    private static func gridCell(x: Double, y: Double, cellSize: Double) -> GridCell {
        GridCell(x: Int(floor(x / cellSize)), y: Int(floor(y / cellSize)))
    }

    private static func nearbyFeatures(
        _ cell: GridCell,
        reach: Int,
        in grid: [GridCell: [ProjectedFeature]]
    ) -> [ProjectedFeature] {
        var features: [ProjectedFeature] = []
        for x in (cell.x - reach)...(cell.x + reach) {
            for y in (cell.y - reach)...(cell.y + reach) {
                features.append(contentsOf: grid[GridCell(x: x, y: y)] ?? [])
            }
        }
        return features
    }

    private static func stableClusterHash(_ memberIDs: [String]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for memberID in memberIDs {
            for byte in memberID.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x100000001b3
            }
            hash ^= 0xff
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
