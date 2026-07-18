import Foundation

public enum MapRegion: String, CaseIterable, Sendable, Equatable {
    case malaysia
    case uk

    public var displayName: String {
        switch self {
        case .malaysia:
            return "Malaysia"
        case .uk:
            return "United Kingdom"
        }
    }

    public var viewportBBox: BBox {
        switch self {
        case .malaysia:
            return BBox(minLon: 99.64, minLat: 0.85, maxLon: 119.27, maxLat: 7.36)
        case .uk:
            return BBox(minLon: -8.65, minLat: 49.84, maxLon: 1.77, maxLat: 60.86)
        }
    }

    public static func select(for viewport: BBox, current: MapRegion? = nil) -> MapRegion {
        let intersecting = allCases.filter { $0.viewportBBox.intersects(viewport) }
        if let current, intersecting.contains(current) {
            return current
        }
        if intersecting.count == 1 {
            return intersecting[0]
        }
        if let current {
            return current
        }
        return allCases.min(by: {
            distanceSquared($0.viewportBBox.center, viewport.center)
                < distanceSquared($1.viewportBBox.center, viewport.center)
        }) ?? .malaysia
    }

    public static func supportedRegion(for viewport: BBox) -> MapRegion? {
        allCases.first { $0.viewportBBox.intersects(viewport) }
    }
}

public extension BBox {
    var center: (lon: Double, lat: Double) {
        ((minLon + maxLon) / 2.0, (minLat + maxLat) / 2.0)
    }

    func intersects(_ other: BBox) -> Bool {
        !(maxLon < other.minLon || other.maxLon < minLon || maxLat < other.minLat || other.maxLat < minLat)
    }
}

private func distanceSquared(
    _ lhs: (lon: Double, lat: Double),
    _ rhs: (lon: Double, lat: Double)
) -> Double {
    let dLon = lhs.lon - rhs.lon
    let dLat = lhs.lat - rhs.lat
    return dLon * dLon + dLat * dLat
}
