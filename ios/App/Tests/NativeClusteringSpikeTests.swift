import MapLibre
import MakingTracksMapStyle
import UIKit
import XCTest
@testable import MakingTracks

@MainActor
final class NativeClusteringSpikeTests: XCTestCase {
    private var retainedWindow: UIWindow?
    private var retainedDelegate: ClusterSpikeDelegate?

    func testClusteredShapeSourceProducesQueryableFeatures() async throws {
        try await assertClusteredShapeSourceProducesQueryableFeatures(shape: Self.fivePointShape())
    }

    func testClusteredShapeSourceProducesQueryableFeaturesWithAppPinProperties() async throws {
        try await assertClusteredShapeSourceProducesQueryableFeatures(shape: Self.appPinPropertyShape())
    }

    func testClusteredShapeSourceProducesQueryableFeaturesWithAppPaperStyle() async throws {
        let style = paperBasemapStyle(
            worldPMTilesURL: WorldBasemap.pmtilesURL(),
            regionPMTilesURL: nil,
            theme: .definedPaper
        )
        try await assertClusteredShapeSourceProducesQueryableFeatures(
            shape: Self.appPinPropertyShape(),
            styleJSON: try style.jsonString()
        )
    }

    private func assertClusteredShapeSourceProducesQueryableFeatures(
        shape: MLNShape?,
        styleJSON: String = #"{"version":8,"sources":{},"layers":[]}"#
    ) async throws {
        let styleLoaded = expectation(description: "style loaded")
        let sourceProducedFeatures = expectation(description: "clustered source produced features")
        var didFulfillSourceFeatures = false

        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        mapView.setCenter(CLLocationCoordinate2D(latitude: 3.14, longitude: 101.69), zoomLevel: 10, animated: false)

        let delegate = ClusterSpikeDelegate(
            didLoadStyle: { mapView, style in
                let source = MLNShapeSource(
                    identifier: "cluster-spike-points",
                    shape: shape,
                    options: [
                        .clustered: NSNumber(value: true),
                        .clusterRadius: NSNumber(value: 50),
                        .clusterMinPoints: NSNumber(value: 2),
                        .maximumZoomLevelForClustering: NSNumber(value: 13),
                    ]
                )
                style.addSource(source)

                let layer = MLNCircleStyleLayer(identifier: "cluster-spike-circles", source: source)
                layer.circleColor = NSExpression(forConstantValue: UIColor.systemRed)
                layer.circleRadius = NSExpression(forConstantValue: NSNumber(value: 8))
                style.addLayer(layer)

                mapView.setNeedsDisplay()
                styleLoaded.fulfill()
            },
            didRenderFrame: { mapView in
                guard !didFulfillSourceFeatures,
                      let source = mapView.style?.source(withIdentifier: "cluster-spike-points") as? MLNShapeSource,
                      !source.features(matching: nil).isEmpty
                else { return }
                didFulfillSourceFeatures = true
                sourceProducedFeatures.fulfill()
            }
        )
        retainedDelegate = delegate
        mapView.delegate = delegate

        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let viewController = UIViewController()
        viewController.view = mapView
        let window = UIWindow(windowScene: windowScene)
        window.frame = mapView.frame
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        retainedWindow = window

        mapView.styleURL = try Self.styleURL(json: styleJSON)

        await fulfillment(of: [styleLoaded], timeout: 5)
        await fulfillment(of: [sourceProducedFeatures], timeout: 10)

        let source = try XCTUnwrap(mapView.style?.source(withIdentifier: "cluster-spike-points") as? MLNShapeSource)
        XCTAssertFalse(source.features(matching: nil).isEmpty)
    }

    private static func styleURL(json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("making-tracks-cluster-spike-style-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url, options: .atomic)
        return url
    }

    private static func fivePointShape() -> MLNShape? {
        let json = """
        {"type":"FeatureCollection","features":[
        {"type":"Feature","geometry":{"type":"Point","coordinates":[101.6900,3.1400]},"properties":{"name":"one"}},
        {"type":"Feature","geometry":{"type":"Point","coordinates":[101.6902,3.1401]},"properties":{"name":"two"}},
        {"type":"Feature","geometry":{"type":"Point","coordinates":[101.6904,3.1402]},"properties":{"name":"three"}},
        {"type":"Feature","geometry":{"type":"Point","coordinates":[101.6906,3.1403]},"properties":{"name":"four"}},
        {"type":"Feature","geometry":{"type":"Point","coordinates":[101.6908,3.1404]},"properties":{"name":"five"}}
        ]}
        """
        return try? MLNShape(data: Data(json.utf8), encoding: String.Encoding.utf8.rawValue)
    }

    private static func appPinPropertyShape() -> MLNShape? {
        let features = (0..<5).map { index in
            """
            {"type":"Feature","geometry":{"type":"Point","coordinates":[\(101.6900 + Double(index) * 0.0002),\(3.1400 + Double(index) * 0.0001)]},"properties":{"place_id":"mt1_D000000000000000000000000\(index)","tier":\(index + 1),"category":"attraction","visit":"none","saved":false,"hidden":false,"pin_presentation":"discovery"}}
            """
        }.joined(separator: ",")
        let json = #"{"type":"FeatureCollection","features":["# + features + #"]}"#
        return try? MLNShape(data: Data(json.utf8), encoding: String.Encoding.utf8.rawValue)
    }
}

@MainActor
private final class ClusterSpikeDelegate: NSObject, @MainActor MLNMapViewDelegate {
    private let didLoadStyleHandler: (MLNMapView, MLNStyle) -> Void
    private let didRenderFrameHandler: (MLNMapView) -> Void

    init(
        didLoadStyle: @escaping (MLNMapView, MLNStyle) -> Void,
        didRenderFrame: @escaping (MLNMapView) -> Void
    ) {
        didLoadStyleHandler = didLoadStyle
        didRenderFrameHandler = didRenderFrame
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        didLoadStyleHandler(mapView, style)
    }

    func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
        guard fullyRendered else { return }
        didRenderFrameHandler(mapView)
    }
}
