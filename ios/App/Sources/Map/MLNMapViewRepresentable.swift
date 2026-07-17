import CoreLocation
import SwiftUI
@preconcurrency import MapLibre
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles

@MainActor
struct MLNMapViewRepresentable: UIViewRepresentable {
    var worldPMTilesURL: String?
    var regionPMTilesURL: String?
    var startupViewport: ViewportSeed
    var features: [(MapPlace, PinState)]
    var locationManager: AppLocationManager
    var showsUserLocation: Bool
    var userTrackingMode: MLNUserTrackingMode
    var onCameraIdle: (BBox, Int) -> Void
    var onUserPanned: () -> Void
    var onTapPlace: (String) -> Void
    var onTapEmpty: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCameraIdle: onCameraIdle, onUserPanned: onUserPanned, onTapPlace: onTapPlace, onTapEmpty: onTapEmpty)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(
            frame: .zero,
            styleURL: context.coordinator.styleURL(worldPMTilesURL: worldPMTilesURL, regionPMTilesURL: regionPMTilesURL)
        )
        map.accessibilityIdentifier = "map.surface"
        map.delegate = context.coordinator
        map.locationManager = locationManager
        map.shouldRequestAuthorizationToUseLocationServices = false
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.showsUserLocation = showsUserLocation
        map.userTrackingMode = userTrackingMode
        map.setCenter(startupViewport.center, zoomLevel: Double(startupViewport.zoom), animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        context.coordinator.pendingFeatures = features
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.onCameraIdle = onCameraIdle
        context.coordinator.onUserPanned = onUserPanned
        context.coordinator.onTapPlace = onTapPlace
        context.coordinator.onTapEmpty = onTapEmpty
        context.coordinator.pendingFeatures = features
        map.locationManager = locationManager
        map.shouldRequestAuthorizationToUseLocationServices = false
        map.showsUserLocation = showsUserLocation
        map.userTrackingMode = userTrackingMode

        if context.coordinator.currentWorldPMTilesURL != worldPMTilesURL || context.coordinator.currentRegionPMTilesURL != regionPMTilesURL {
            context.coordinator.currentWorldPMTilesURL = worldPMTilesURL
            context.coordinator.currentRegionPMTilesURL = regionPMTilesURL
            map.styleURL = context.coordinator.styleURL(worldPMTilesURL: worldPMTilesURL, regionPMTilesURL: regionPMTilesURL)
        } else {
            context.coordinator.updateSource(on: map, features: features)
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var onCameraIdle: (BBox, Int) -> Void
        var onUserPanned: () -> Void
        var onTapPlace: (String) -> Void
        var onTapEmpty: () -> Void
        weak var map: MLNMapView?
        var currentWorldPMTilesURL: String?
        var currentRegionPMTilesURL: String?
        var pendingFeatures: [(MapPlace, PinState)] = []

        init(
            onCameraIdle: @escaping (BBox, Int) -> Void,
            onUserPanned: @escaping () -> Void,
            onTapPlace: @escaping (String) -> Void,
            onTapEmpty: @escaping () -> Void
        ) {
            self.onCameraIdle = onCameraIdle
            self.onUserPanned = onUserPanned
            self.onTapPlace = onTapPlace
            self.onTapEmpty = onTapEmpty
        }

        func styleURL(worldPMTilesURL: String?, regionPMTilesURL: String?) -> URL? {
            let style = paperBasemapStyle(worldPMTilesURL: worldPMTilesURL, regionPMTilesURL: regionPMTilesURL)
            guard let json = try? style.jsonString() else { return nil }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("making-tracks-style-\(UUID().uuidString).json")
            do {
                try Data(json.utf8).write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            map = mapView
            registerBadgeImages(in: style)

            if style.source(withIdentifier: PinLayers.sourceID) == nil {
                style.addSource(MLNShapeSource(identifier: PinLayers.sourceID, shape: nil, options: nil))
            }
            guard let source = style.source(withIdentifier: PinLayers.sourceID) as? MLNShapeSource else { return }

            let circle = MLNCircleStyleLayer(identifier: "pins-circle", source: source)
            circle.circleOpacity = NSExpression(mglJSONObject: PinLayers.fadeOpacityExpression().foundationObject)
            circle.circleColor = NSExpression(forConstantValue: UIColor(hex: PinLayers.pinColor))
            circle.circleRadius = NSExpression(forConstantValue: 6)
            style.addLayer(circle)

            addBadge(id: "pins-bookmark", icon: "badge-bookmark", filter: PinLayers.bookmarkFilter(), offset: PinLayers.bookmarkOffset, source: source, style: style)
            addBadge(id: "pins-heart", icon: "badge-heart", filter: PinLayers.heartFilter(), offset: PinLayers.heartOffset, source: source, style: style)
            updateSource(on: mapView, features: pendingFeatures)
            reportViewport(mapView)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            if reason.contains(.gesturePan) || reason.contains(.gestureRotate) {
                onUserPanned()
            }
            reportViewport(mapView)
        }

        func updateSource(on map: MLNMapView, features: [(MapPlace, PinState)]) {
            guard let source = map.style?.source(withIdentifier: PinLayers.sourceID) as? MLNShapeSource else { return }
            let collection = FeatureEncoding.featureCollection(features.map { FeatureEncoding.feature($0.0, $0.1) })
            guard let json = try? collection.jsonString(),
                  let shape = try? MLNShape(data: Data(json.utf8), encoding: String.Encoding.utf8.rawValue)
            else { return }
            source.shape = shape
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let map else { return }
            let point = recognizer.location(in: map)
            let hits = map.visibleFeatures(at: point, styleLayerIdentifiers: ["pins-circle", "pins-bookmark", "pins-heart"])
            if let id = hits.first?.attribute(forKey: "place_id") as? String {
                onTapPlace(id)
            } else {
                onTapEmpty()
            }
        }

        private func reportViewport(_ map: MLNMapView) {
            let bounds = map.visibleCoordinateBounds
            let bbox = BBox(
                minLon: min(bounds.sw.longitude, bounds.ne.longitude),
                minLat: min(bounds.sw.latitude, bounds.ne.latitude),
                maxLon: max(bounds.sw.longitude, bounds.ne.longitude),
                maxLat: max(bounds.sw.latitude, bounds.ne.latitude)
            )
            onCameraIdle(bbox, Int(map.zoomLevel.rounded()))
        }

        private func addBadge(id: String, icon: String, filter: JSONValue, offset: JSONValue, source: MLNShapeSource, style: MLNStyle) {
            let layer = MLNSymbolStyleLayer(identifier: id, source: source)
            layer.iconImageName = NSExpression(forConstantValue: icon)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            if case let .array(values) = offset,
               values.count == 2,
               case let .double(x) = values[0],
               case let .double(y) = values[1] {
                layer.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: x, dy: y)))
            }
            layer.predicate = NSPredicate(mglJSONObject: filter.foundationObject)
            style.addLayer(layer)
        }

        private func registerBadgeImages(in style: MLNStyle) {
            if let bookmark = UIImage(systemName: "bookmark.fill") {
                style.setImage(bookmark, forName: "badge-bookmark")
            }
            if let heart = UIImage(systemName: "heart.fill") {
                style.setImage(heart, forName: "badge-heart")
            }
        }
    }
}

private extension UIColor {
    convenience init(hex: String) {
        var string = hex
        if string.hasPrefix("#") {
            string.removeFirst()
        }
        let value = UInt64(string, radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
