import XCTest
import MakingTracksData
@testable import MakingTracksMapStyle

final class PinClustererTests: XCTestCase {
    func testDenseVisiblePinsBecomeDeterministicClusterIndependentOfInputOrder() {
        let features = denseKualaLumpurFeatures()
        let options = PinClusterer.Options(zoom: 10, radiusPoints: 44, maximumClusterZoom: 13)

        let forward = PinClusterer.renderFeatures(features, options: options)
        let reversed = PinClusterer.renderFeatures(Array(features.reversed()), options: options)

        XCTAssertEqual(forward.renderFeatures, reversed.renderFeatures)
        XCTAssertEqual(forward.clusters.count, 1)
        XCTAssertEqual(forward.singletons.count, 0)

        let cluster = forward.clusters[0]
        XCTAssertEqual(cluster.count, features.count)
        XCTAssertEqual(cluster.memberIDs, features.map(\.0.id).sorted())
        XCTAssertEqual(cluster.lat, features.map(\.0.lat).reduce(0, +) / Double(features.count), accuracy: 0.000001)
        XCTAssertEqual(cluster.lon, features.map(\.0.lon).reduce(0, +) / Double(features.count), accuracy: 0.000001)
    }

    func testStreetZoomEmitsSingletonPinsInsteadOfClusters() {
        let features = denseKualaLumpurFeatures()
        let snapshot = PinClusterer.renderFeatures(
            features,
            options: PinClusterer.Options(zoom: 14, radiusPoints: 44, maximumClusterZoom: 13)
        )

        XCTAssertEqual(snapshot.clusters, [])
        XCTAssertEqual(snapshot.singletons.map(\.0.id), features.map(\.0.id).sorted())
        XCTAssertEqual(snapshot.renderFeatures.count, features.count)
    }

    func testDefaultRadiusLetsDenseMidZoomPinsRenderIndividually() {
        let features = denseKualaLumpurGridFeatures()
        let midZoom = PinClusterer.renderFeatures(
            features,
            options: PinClusterer.Options(
                zoom: 13,
                radiusPoints: PinLayers.clusterRadius(pinSize: PinSize()),
                maximumClusterZoom: PinLayers.maximumClusterZoom
            )
        )

        XCTAssertEqual(midZoom.clusters, [])
        XCTAssertEqual(midZoom.singletons.map(\.0.id), features.map(\.0.id).sorted())
        XCTAssertEqual(midZoom.renderFeatures.count, features.count)

        let cityZoom = PinClusterer.renderFeatures(
            features,
            options: PinClusterer.Options(
                zoom: 12,
                radiusPoints: PinLayers.clusterRadius(pinSize: PinSize()),
                maximumClusterZoom: PinLayers.maximumClusterZoom
            )
        )
        XCTAssertEqual(cityZoom.clusters.map(\.count).sorted(), [2, 4, 4, 4, 9])
        XCTAssertEqual(cityZoom.singletons.count, 1)
        XCTAssertEqual(cityZoom.clusters.map(\.count).reduce(0, +) + cityZoom.singletons.count, features.count)
    }

    func testCategoryVisibilityIsAppliedBeforeClusterCountsAreComputed() {
        let museumA = pin("museum-a", lat: 3.1400, lon: 101.6900, category: "museum")
        let museumB = pin("museum-b", lat: 3.1402, lon: 101.6902, category: "museum")
        let artwork = pin("artwork-a", lat: 3.1401, lon: 101.6901, category: "artwork")

        let snapshot = PinClusterer.renderFeatures(
            [museumA, museumB, artwork],
            options: PinClusterer.Options(
                zoom: 10,
                radiusPoints: 44,
                maximumClusterZoom: 13,
                visibleCategories: ["museum"]
            )
        )

        XCTAssertEqual(snapshot.clusters.count, 1)
        XCTAssertEqual(snapshot.clusters[0].count, 2)
        XCTAssertEqual(snapshot.clusters[0].memberIDs, ["museum-a", "museum-b"])
        XCTAssertFalse(snapshot.renderFeatures.contains(.singleton(artwork.0, artwork.1)))
    }

    func testClusterIDIsDeterministicAndBoundedForLargeClusters() {
        let features = (0..<120).map { index in
            pin(
                "very-long-production-place-identifier-\(index)",
                lat: 3.1400 + (Double(index) * 0.000001),
                lon: 101.6900 + (Double(index) * 0.000001),
                category: "museum"
            )
        }
        let options = PinClusterer.Options(zoom: 10, radiusPoints: 44, maximumClusterZoom: 13)

        let first = PinClusterer.renderFeatures(features, options: options)
        let second = PinClusterer.renderFeatures(Array(features.reversed()), options: options)

        XCTAssertEqual(first.clusters.count, 1)
        XCTAssertEqual(first.clusters[0].id, second.clusters[0].id)
        XCTAssertLessThanOrEqual(first.clusters[0].id.count, 36)
        XCTAssertEqual(first.clusters[0].memberIDs.count, 120)
    }

    func testRadiusKeepsSeparatedGroupsAndSingletonsDistinct() {
        let firstGroupA = pin("a-1", lat: 3.1400, lon: 101.6900, category: "museum")
        let firstGroupB = pin("a-2", lat: 3.1401, lon: 101.6901, category: "museum")
        let secondGroupA = pin("b-1", lat: 3.1400, lon: 102.2500, category: "museum")
        let secondGroupB = pin("b-2", lat: 3.1401, lon: 102.2501, category: "museum")
        let singleton = pin("c-1", lat: 3.1400, lon: 103.0000, category: "museum")

        let snapshot = PinClusterer.renderFeatures(
            [singleton, secondGroupB, firstGroupB, secondGroupA, firstGroupA],
            options: PinClusterer.Options(zoom: 10, radiusPoints: 44, maximumClusterZoom: 13)
        )

        XCTAssertEqual(snapshot.clusters.map(\.memberIDs), [["a-1", "a-2"], ["b-1", "b-2"]])
        XCTAssertEqual(snapshot.singletons.map(\.0.id), ["c-1"])
        XCTAssertEqual(snapshot.renderFeatures.count, 3)
    }

    func testClusterFeatureUsesOrdinaryPointGeoJSONWithCountProperties() throws {
        let cluster = PinCluster(
            id: "manual-cluster-z10-1",
            lat: 3.14,
            lon: 101.69,
            count: 12,
            memberIDs: ["a", "b"]
        )
        let feature = FeatureEncoding.clusterFeature(cluster)

        guard case let .object(root) = feature,
              case let .object(geometry) = root["geometry"],
              case let .array(coordinates) = geometry["coordinates"],
              case let .object(properties) = root["properties"]
        else {
            return XCTFail("cluster GeoJSON shape")
        }

        XCTAssertEqual(root["type"], .string("Feature"))
        XCTAssertEqual(geometry["type"], .string("Point"))
        XCTAssertEqual(coordinates, [.double(101.69), .double(3.14)])
        XCTAssertEqual(properties["cluster"], .bool(true))
        XCTAssertEqual(properties["cluster_id"], .string("manual-cluster-z10-1"))
        XCTAssertEqual(properties["point_count"], .double(12))
        XCTAssertEqual(properties["point_count_abbreviated"], .string("12"))
        XCTAssertNil(properties["place_id"], "clusters must not open a place card")
    }

    func testClusterLayerFiltersSeparateClustersFromSingletonPins() {
        let singletonProps = FeatureEncoding.featureProperties(PinState(saved: true, visit: .loved))
        let clusterProps: [String: JSONValue] = [
            "cluster": .bool(true),
            "point_count": .double(3),
            "point_count_abbreviated": .string("3"),
        ]

        XCTAssertEqual(Expression.evaluate(PinLayers.clusterFilter(), clusterProps), .bool(true))
        XCTAssertEqual(Expression.evaluate(PinLayers.clusterFilter(), singletonProps), .bool(false))
        XCTAssertEqual(Expression.evaluate(PinLayers.singlePinFilter(), singletonProps), .bool(true))
        XCTAssertEqual(Expression.evaluate(PinLayers.singlePinFilter(), clusterProps), .bool(false))
        XCTAssertEqual(Expression.evaluate(PinLayers.bookmarkFilter(), clusterProps), .bool(false))
        XCTAssertEqual(Expression.evaluate(PinLayers.heartFilter(), clusterProps), .bool(false))
    }

    private func denseKualaLumpurFeatures() -> [(MapPlace, PinState)] {
        (0..<6).map { index in
            pin(
                "kl-\(index)",
                lat: 3.1400 + (Double(index) * 0.00008),
                lon: 101.6900 + (Double(index) * 0.00008),
                category: "museum"
            )
        }
    }

    private func denseKualaLumpurGridFeatures() -> [(MapPlace, PinState)] {
        (0..<24).map { index in
            pin(
                "dense-kl-\(index)",
                lat: 3.132 + (Double(index / 6) * 0.004),
                lon: 101.682 + (Double(index % 6) * 0.004),
                category: "museum"
            )
        }
    }

    private func pin(
        _ id: String,
        lat: Double,
        lon: Double,
        category: String,
        state: PinState = PinState(saved: false, visit: .none)
    ) -> (MapPlace, PinState) {
        (MapPlace(id: id, lat: lat, lon: lon, tier: 2, category: category), state)
    }
}
