import CoreLocation
import SwiftUI
@preconcurrency import MapLibre
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles

enum PinCategoryImageRegistry {
    static let categorySymbolNames = PinLayers.categorySymbolNames
    static let requiredIconNames = Set(PinLayers.categoryIconNames.values)
        .union([PinLayers.fallbackCategoryIconName, PinLayers.hiddenIconName])
}

struct ProjectedFeatureDiagnostic: Identifiable, Equatable, Sendable {
    let placeID: String
    let x: Double
    let y: Double
    let normalizedX: Double
    let normalizedY: Double
    let isHitTestable: Bool

    var id: String { placeID }
}

@MainActor
struct MLNMapViewRepresentable: UIViewRepresentable {
    var worldPMTilesURL: String?
    var regionPMTilesURL: String?
    var theme: MapTheme
    var startupViewport: ViewportSeed
    var features: [(MapPlace, PinState)]
    var visibleCategories: Set<String>?
    var locationManager: AppLocationManager
    var showsUserLocation: Bool
    var userTrackingMode: MLNUserTrackingMode
    var onCameraIdle: (BBox, Int) -> Void
    var onUserPanned: () -> Void
    var onTapPlace: (String) -> Void
    var onTapEmpty: () -> Void
    var onMapReady: () -> Void
    var onFeaturesApplied: () -> Void
    var onStyleWillReload: () -> Void
    var debugReportProjectedFeatureDiagnostics: ([ProjectedFeatureDiagnostic]) -> Void = { _ in }
    var debugReportMapUpdateStatus: (String) -> Void = { _ in }
    var debugReportTapStatus: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(
            onCameraIdle: onCameraIdle,
            onUserPanned: onUserPanned,
            onTapPlace: onTapPlace,
            onTapEmpty: onTapEmpty,
            onMapReady: onMapReady,
            onFeaturesApplied: onFeaturesApplied,
            onStyleWillReload: onStyleWillReload
        )
        coordinator.debugReportProjectedFeatureDiagnostics = debugReportProjectedFeatureDiagnostics
        coordinator.debugReportMapUpdateStatus = debugReportMapUpdateStatus
        coordinator.debugReportTapStatus = debugReportTapStatus
        return coordinator
    }

    func makeUIView(context: Context) -> MLNMapView {
        let initialStyleReload = context.coordinator.prepareStyleReload(
            worldPMTilesURL: worldPMTilesURL,
            regionPMTilesURL: regionPMTilesURL,
            theme: theme
        )
        let map = MLNMapView(
            frame: .zero,
            styleURL: initialStyleReload?.url
        )
        map.accessibilityIdentifier = "map.surface"
        map.accessibilityLabel = "Map"
        map.accessibilityHint = "Shows places and your location"
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
        if let initialStyleReload {
            context.coordinator.commitStyleReload(initialStyleReload)
        }
        context.coordinator.pendingFeatures = features
        context.coordinator.desiredVisibleCategories = visibleCategories
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.onCameraIdle = onCameraIdle
        context.coordinator.onUserPanned = onUserPanned
        context.coordinator.onTapPlace = onTapPlace
        context.coordinator.onTapEmpty = onTapEmpty
        context.coordinator.debugReportProjectedFeatureDiagnostics = debugReportProjectedFeatureDiagnostics
        context.coordinator.debugReportMapUpdateStatus = debugReportMapUpdateStatus
        context.coordinator.debugReportTapStatus = debugReportTapStatus
        context.coordinator.pendingFeatures = features
        context.coordinator.desiredVisibleCategories = visibleCategories
        map.shouldRequestAuthorizationToUseLocationServices = false
        map.showsUserLocation = showsUserLocation
        map.userTrackingMode = userTrackingMode

        let styleReload = context.coordinator.prepareStyleReload(
            worldPMTilesURL: worldPMTilesURL,
            regionPMTilesURL: regionPMTilesURL,
            theme: theme
        )
        context.coordinator.debugReportMapUpdateStatus(
            "update features:\(features.count) style:\(map.style != nil) source:\(map.style?.source(withIdentifier: PinLayers.sourceID) != nil) reload:\(styleReload != nil)"
        )
        if let styleReload {
            context.coordinator.onStyleWillReload()
            context.coordinator.commitStyleReload(styleReload)
            map.styleURL = styleReload.url
        } else {
            context.coordinator.updateLayerFilters(on: map, visibleCategories: visibleCategories)
            context.coordinator.updateSource(on: map, features: features)
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var onCameraIdle: (BBox, Int) -> Void
        var onUserPanned: () -> Void
        var onTapPlace: (String) -> Void
        var onTapEmpty: () -> Void
        var onMapReady: () -> Void
        var onFeaturesApplied: () -> Void
        var onStyleWillReload: () -> Void
        var debugReportProjectedFeatureDiagnostics: ([ProjectedFeatureDiagnostic]) -> Void = { _ in }
        var debugReportMapUpdateStatus: (String) -> Void = { _ in }
        var debugReportTapStatus: (String) -> Void = { _ in }
        weak var map: MLNMapView?
        var currentWorldPMTilesURL: String?
        var currentRegionPMTilesURL: String?
        var currentThemeID: String?
        var desiredVisibleCategories: Set<String>?
        var currentVisibleCategories: Set<String>?
        var pendingFeatures: [(MapPlace, PinState)] = []
#if DEBUG
        private var needsProjectedDiagnosticsResample = false
#endif

        struct StyleReload: Equatable {
            let url: URL
            let worldPMTilesURL: String?
            let regionPMTilesURL: String?
            let themeID: String
        }

        init(
            onCameraIdle: @escaping (BBox, Int) -> Void,
            onUserPanned: @escaping () -> Void,
            onTapPlace: @escaping (String) -> Void,
            onTapEmpty: @escaping () -> Void,
            onMapReady: @escaping () -> Void,
            onFeaturesApplied: @escaping () -> Void,
            onStyleWillReload: @escaping () -> Void
        ) {
            self.onCameraIdle = onCameraIdle
            self.onUserPanned = onUserPanned
            self.onTapPlace = onTapPlace
            self.onTapEmpty = onTapEmpty
            self.onMapReady = onMapReady
            self.onFeaturesApplied = onFeaturesApplied
            self.onStyleWillReload = onStyleWillReload
        }

        func prepareStyleReload(
            worldPMTilesURL: String?,
            regionPMTilesURL: String?,
            theme: MapTheme,
            makeStyleURL: ((String?, String?, MapTheme) -> URL?)? = nil
        ) -> StyleReload? {
            guard currentWorldPMTilesURL != worldPMTilesURL
                || currentRegionPMTilesURL != regionPMTilesURL
                || currentThemeID != theme.id
            else { return nil }
            let makeStyleURL = makeStyleURL ?? styleURL
            guard let url = makeStyleURL(worldPMTilesURL, regionPMTilesURL, theme) else { return nil }
            return StyleReload(
                url: url,
                worldPMTilesURL: worldPMTilesURL,
                regionPMTilesURL: regionPMTilesURL,
                themeID: theme.id
            )
        }

        func commitStyleReload(_ reload: StyleReload) {
            currentWorldPMTilesURL = reload.worldPMTilesURL
            currentRegionPMTilesURL = reload.regionPMTilesURL
            currentThemeID = reload.themeID
        }

        func styleURL(worldPMTilesURL: String?, regionPMTilesURL: String?, theme: MapTheme) -> URL? {
            let style = paperBasemapStyle(
                worldPMTilesURL: worldPMTilesURL,
                regionPMTilesURL: regionPMTilesURL,
                theme: theme
            )
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
            registerCategoryImages(in: style)
            onMapReady()

            if style.source(withIdentifier: PinLayers.sourceID) == nil {
                style.addSource(MLNShapeSource(identifier: PinLayers.sourceID, shape: nil, options: nil))
            }
            guard let source = style.source(withIdentifier: PinLayers.sourceID) as? MLNShapeSource else { return }

            let circle = MLNCircleStyleLayer(identifier: "pins-circle", source: source)
            circle.circleOpacity = NSExpression(mglJSONObject: PinLayers.fadeOpacityExpression().foundationObject)
            circle.circleColor = NSExpression(mglJSONObject: PinLayers.pinColorExpression().foundationObject)
            circle.circleRadius = NSExpression(forConstantValue: 6)
            style.addLayer(circle)

            addCategoryIcon(source: source, style: style)
            addBadge(id: "pins-bookmark", icon: "badge-bookmark", filter: PinLayers.bookmarkFilter(), offset: PinLayers.bookmarkOffset, source: source, style: style)
            addBadge(id: "pins-heart", icon: "badge-heart", filter: PinLayers.heartFilter(), offset: PinLayers.heartOffset, source: source, style: style)
            currentVisibleCategories = nil
            updateLayerFilters(on: mapView, visibleCategories: desiredVisibleCategories)
            updateSource(on: mapView, features: pendingFeatures)
            reportViewport(mapView)
        }

#if DEBUG
        func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
            guard needsProjectedDiagnosticsResample, !pendingFeatures.isEmpty else { return }
            reportProjectedFeatureDiagnostics(on: mapView, features: pendingFeatures)
        }
#endif

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            if reason.contains(.gesturePan) || reason.contains(.gestureRotate) {
                onUserPanned()
            }
            reportViewport(mapView)
        }

        func updateSource(on map: MLNMapView, features: [(MapPlace, PinState)]) {
            guard let style = map.style else {
                debugReportMapUpdateStatus("source no-style features:\(features.count)")
                return
            }
            guard let source = style.source(withIdentifier: PinLayers.sourceID) as? MLNShapeSource else {
                debugReportMapUpdateStatus("source no-pin-source features:\(features.count)")
                return
            }
            let collection = FeatureEncoding.featureCollection(features.map { FeatureEncoding.feature($0.0, $0.1) })
            guard let json = try? collection.jsonString(),
                  let shape = try? MLNShape(data: Data(json.utf8), encoding: String.Encoding.utf8.rawValue)
            else {
                debugReportMapUpdateStatus("source shape-failed features:\(features.count)")
                return
            }
            source.shape = shape
            debugReportMapUpdateStatus("source applied features:\(features.count)")
            if !features.isEmpty {
                onFeaturesApplied()
#if DEBUG
                needsProjectedDiagnosticsResample = true
                reportProjectedFeatureDiagnostics(on: map, features: features)
                Task { @MainActor [weak self, weak map] in
                    guard let self, let map else { return }
                    self.reportProjectedFeatureDiagnostics(on: map, features: features)
                }
#endif
            }
        }

        func updateLayerFilters(on map: MLNMapView, visibleCategories: Set<String>?) {
            guard currentVisibleCategories != visibleCategories,
                  let style = map.style
            else { return }
            currentVisibleCategories = visibleCategories

            let categoryFilter = PinLayers.categoryVisibilityFilter(visibleCategories: visibleCategories)
            setPredicate(PinLayers.combinedFilter([categoryFilter]), on: "pins-circle", in: style)
            setPredicate(PinLayers.combinedFilter([categoryFilter]), on: "pins-icon", in: style)
            setPredicate(PinLayers.combinedFilter([categoryFilter, PinLayers.bookmarkFilter()]), on: "pins-bookmark", in: style)
            setPredicate(PinLayers.combinedFilter([categoryFilter, PinLayers.heartFilter()]), on: "pins-heart", in: style)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let map else { return }
            let point = recognizer.location(in: map)
            let hits = map.visibleFeatures(at: point, styleLayerIdentifiers: ["pins-circle", "pins-icon", "pins-bookmark", "pins-heart"])
            if let id = hits.lazy.compactMap({ $0.attribute(forKey: "place_id") as? String }).first {
                debugReportTapStatus("tap hit \(id) at \(Int(point.x)),\(Int(point.y))")
                onTapPlace(id)
            } else {
                debugReportTapStatus("tap empty at \(Int(point.x)),\(Int(point.y))")
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

        private func addCategoryIcon(source: MLNShapeSource, style: MLNStyle) {
            let layer = MLNSymbolStyleLayer(identifier: "pins-icon", source: source)
            layer.iconImageName = NSExpression(mglJSONObject: PinLayers.categoryIconExpression().foundationObject)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            layer.iconScale = NSExpression(forConstantValue: PinLayers.categoryIconScale)
            layer.iconOpacity = NSExpression(mglJSONObject: PinLayers.fadeOpacityExpression().foundationObject)
            style.addLayer(layer)
        }

        private func setPredicate(_ filter: JSONValue?, on layerID: String, in style: MLNStyle) {
            let predicate = filter.map { NSPredicate(mglJSONObject: $0.foundationObject) }
            if let circle = style.layer(withIdentifier: layerID) as? MLNCircleStyleLayer {
                circle.predicate = predicate
            } else if let symbol = style.layer(withIdentifier: layerID) as? MLNSymbolStyleLayer {
                symbol.predicate = predicate
            }
        }

#if DEBUG
        private func reportProjectedFeatureDiagnostics(on map: MLNMapView, features: [(MapPlace, PinState)]) {
            let diagnostics = features.map { place, _ in
                let coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
                let point = map.convert(coordinate, toPointTo: map)
                let hits = map.visibleFeatures(at: point, styleLayerIdentifiers: ["pins-circle", "pins-icon", "pins-bookmark", "pins-heart"])
                let isHitTestable = hits.contains { feature in
                    (feature.attribute(forKey: "place_id") as? String) == place.id
                }
                return ProjectedFeatureDiagnostic(
                    placeID: place.id,
                    x: Double(point.x),
                    y: Double(point.y),
                    normalizedX: Double(point.x / max(map.bounds.width, 1)),
                    normalizedY: Double(point.y / max(map.bounds.height, 1)),
                    isHitTestable: isHitTestable
                )
            }
            needsProjectedDiagnosticsResample = diagnostics.contains { !$0.isHitTestable }
            debugReportProjectedFeatureDiagnostics(diagnostics)
        }
#endif

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

        private func registerCategoryImages(in style: MLNStyle) {
            let configuration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            for (iconName, symbolName) in PinCategoryImageRegistry.categorySymbolNames {
                guard let image = UIImage(systemName: symbolName, withConfiguration: configuration)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                else {
                    assertionFailure("Missing SF Symbol '\(symbolName)' for category icon '\(iconName)'")
                    continue
                }
                style.setImage(image, forName: iconName)
            }
        }
    }
}
