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

struct TrackSourceSnapshot: Sendable {
    static let emptyFeatureCollectionJSON = "{\"features\":[],\"type\":\"FeatureCollection\"}"
    static let empty = TrackSourceSnapshot(
        featureCollectionJSON: emptyFeatureCollectionJSON,
        segmentCount: 0,
        filteredBridgeCount: 0,
        connectableVisitCount: 0
    )

    let signature: String
    let segmentCount: Int
    let filteredBridgeCount: Int
    let connectableVisitCount: Int
    let data: Data

    init(
        featureCollectionJSON: String,
        segmentCount: Int,
        filteredBridgeCount: Int = 0,
        connectableVisitCount: Int = 0
    ) {
        signature = featureCollectionJSON
        self.segmentCount = segmentCount
        self.filteredBridgeCount = filteredBridgeCount
        self.connectableVisitCount = connectableVisitCount
        data = Data(featureCollectionJSON.utf8)
    }

    static func make(context: TrackGeometryContext) -> TrackSourceSnapshot {
        let summary = FeatureEncoding.trackSegmentSummary(context.visits)
        return TrackSourceSnapshot(
            featureCollectionJSON: (try? FeatureEncoding.featureCollection(summary.features).jsonString())
                ?? TrackSourceSnapshot.emptyFeatureCollectionJSON,
            segmentCount: summary.features.count,
            filteredBridgeCount: context.filteredBridgeCount,
            connectableVisitCount: summary.connectableVisitCount
        )
    }
}

struct MapPinAccessibilityContent: Equatable, Sendable {
    let identifier: String
    let label: String
    let hint: String

    init(place: MapPlace, state: PinState, name: String?) {
        identifier = "map.pin.\(place.id)"
        hint = "Opens the place card"

        var parts = [
            Self.placeName(name),
            Self.categoryLabel(place.category),
            Self.visitLabel(state.visit),
        ]
        if state.saved {
            parts.append("saved")
        }
        if state.hidden {
            parts.append("hidden")
        }
        label = parts.joined(separator: ", ")
    }

    private static func placeName(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unnamed place" : trimmed
    }

    private static func categoryLabel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func visitLabel(_ visit: VisitState) -> String {
        switch visit {
        case .none:
            return "not visited"
        case .visited:
            return "visited"
        case .loved:
            return "loved"
        }
    }
}

@MainActor
final class MapAccessibilityContainerView: UIView {
    let mapView: MLNMapView
    let surfaceAccessibilityView = UIView(frame: .zero)
    var onLayout: (() -> Void)?

    init(mapView: MLNMapView) {
        self.mapView = mapView
        super.init(frame: .zero)
        isAccessibilityElement = false
        addSubview(mapView)
        surfaceAccessibilityView.isAccessibilityElement = true
        surfaceAccessibilityView.accessibilityIdentifier = "map.surface"
        surfaceAccessibilityView.accessibilityLabel = "Map"
        surfaceAccessibilityView.accessibilityHint = "Shows places and your location"
        surfaceAccessibilityView.isUserInteractionEnabled = false
        surfaceAccessibilityView.backgroundColor = .clear
        addSubview(surfaceAccessibilityView)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        surfaceAccessibilityView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor),
            surfaceAccessibilityView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceAccessibilityView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceAccessibilityView.topAnchor.constraint(equalTo: topAnchor),
            surfaceAccessibilityView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

@MainActor
struct MLNMapViewRepresentable: UIViewRepresentable {
    var worldPMTilesURL: String?
    var regionPMTilesURL: String?
    var coverageBBoxes: [CoverageBBox]
    var showsCoverageShading: Bool
    var theme: MapTheme
    var startupViewport: ViewportSeed
    var features: [(MapPlace, PinState)]
    var pinPresentation: PinPresentation
    var trackReplayPulsePlaceIDs: Set<String>
    var trackSourceSnapshot: TrackSourceSnapshot
    var pinAccessibilityNames: [String: String]
    var visibleCategories: Set<String>?
    var pinSizeMultiplier: Double
    var locationManager: AppLocationManager
    var showsUserLocation: Bool
    var userTrackingMode: MLNUserTrackingMode
    var debugExposeFixturePinDiagnostics = false
    var cameraRequest: ViewportCameraRequest?
    var onCameraIdle: (BBox, Int) -> Void
    var onUserPanned: () -> Void
    var onTapPlace: (String) -> Void
    var onTapEmpty: () -> Void
    var onMapReady: (String?) -> Void
    var onFeaturesApplied: () -> Void
    var onStyleWillReload: () -> Void
    var onMapLoadFailed: () -> Void
    var debugReportProjectedFeatureDiagnostics: ([ProjectedFeatureDiagnostic]) -> Void = { _ in }
    var debugReportMapUpdateStatus: (String) -> Void = { _ in }
    var debugReportTrackSourceStatus: (String) -> Void = { _ in }
    var debugReportTapStatus: (String) -> Void = { _ in }
    var debugReportPinLayerSize: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(
            onCameraIdle: onCameraIdle,
            onUserPanned: onUserPanned,
            onTapPlace: onTapPlace,
            onTapEmpty: onTapEmpty,
            onMapReady: onMapReady,
            onFeaturesApplied: onFeaturesApplied,
            onStyleWillReload: onStyleWillReload,
            onMapLoadFailed: onMapLoadFailed
        )
        coordinator.debugExposeFixturePinDiagnostics = debugExposeFixturePinDiagnostics
        coordinator.debugReportProjectedFeatureDiagnostics = debugReportProjectedFeatureDiagnostics
        coordinator.debugReportMapUpdateStatus = debugReportMapUpdateStatus
        coordinator.debugReportTrackSourceStatus = debugReportTrackSourceStatus
        coordinator.debugReportTapStatus = debugReportTapStatus
        coordinator.debugReportPinLayerSize = debugReportPinLayerSize
        return coordinator
    }

    func makeUIView(context: Context) -> MapAccessibilityContainerView {
        let initialStyleReload = context.coordinator.prepareStyleReload(
            worldPMTilesURL: worldPMTilesURL,
            regionPMTilesURL: regionPMTilesURL,
            coverageBBoxes: coverageBBoxes,
            showsCoverageShading: showsCoverageShading,
            theme: theme
        )
        let map = MLNMapView(
            frame: .zero,
            styleURL: initialStyleReload?.url
        )
        map.isAccessibilityElement = false
        map.delegate = context.coordinator
        map.locationManager = locationManager
        map.shouldRequestAuthorizationToUseLocationServices = false
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.showsUserLocation = showsUserLocation
        map.userTrackingMode = userTrackingMode
        map.setCenter(startupViewport.center, zoomLevel: Double(startupViewport.zoom), animated: false)
        let container = MapAccessibilityContainerView(mapView: map)
        container.onLayout = { [weak coordinator = context.coordinator, weak map] in
            guard let coordinator, let map else { return }
            coordinator.updatePinAccessibilityElements(on: map)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        context.coordinator.container = container
        context.coordinator.map = map
        if let initialStyleReload {
            context.coordinator.commitStyleReload(initialStyleReload)
        }
        context.coordinator.pendingFeatures = features
        context.coordinator.pendingPinPresentation = pinPresentation
        context.coordinator.pendingTrackReplayPulsePlaceIDs = trackReplayPulsePlaceIDs
        context.coordinator.pendingTrackSourceSnapshot = trackSourceSnapshot
        context.coordinator.pinAccessibilityNames = pinAccessibilityNames
        context.coordinator.desiredVisibleCategories = visibleCategories
        context.coordinator.desiredPinSizeMultiplier = pinSizeMultiplier
        return container
    }

    func updateUIView(_ container: MapAccessibilityContainerView, context: Context) {
        let map = container.mapView
        context.coordinator.container = container
        context.coordinator.onCameraIdle = onCameraIdle
        context.coordinator.onUserPanned = onUserPanned
        context.coordinator.onTapPlace = onTapPlace
        context.coordinator.onTapEmpty = onTapEmpty
        context.coordinator.onMapLoadFailed = onMapLoadFailed
        context.coordinator.debugExposeFixturePinDiagnostics = debugExposeFixturePinDiagnostics
        context.coordinator.debugReportProjectedFeatureDiagnostics = debugReportProjectedFeatureDiagnostics
        context.coordinator.debugReportMapUpdateStatus = debugReportMapUpdateStatus
        context.coordinator.debugReportTrackSourceStatus = debugReportTrackSourceStatus
        context.coordinator.debugReportTapStatus = debugReportTapStatus
        context.coordinator.debugReportPinLayerSize = debugReportPinLayerSize
        context.coordinator.pendingFeatures = features
        context.coordinator.pendingPinPresentation = pinPresentation
        context.coordinator.pendingTrackReplayPulsePlaceIDs = trackReplayPulsePlaceIDs
        context.coordinator.pendingTrackSourceSnapshot = trackSourceSnapshot
        context.coordinator.pinAccessibilityNames = pinAccessibilityNames
        context.coordinator.desiredVisibleCategories = visibleCategories
        context.coordinator.desiredPinSizeMultiplier = pinSizeMultiplier
        map.shouldRequestAuthorizationToUseLocationServices = false
        map.showsUserLocation = showsUserLocation
        map.userTrackingMode = userTrackingMode
        if let cameraRequest,
           context.coordinator.consumeCameraRequest(cameraRequest.id) {
            context.coordinator.applyCameraRequest(cameraRequest, on: map)
        }

        let styleReload = context.coordinator.prepareStyleReload(
            worldPMTilesURL: worldPMTilesURL,
            regionPMTilesURL: regionPMTilesURL,
            coverageBBoxes: coverageBBoxes,
            showsCoverageShading: showsCoverageShading,
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
            context.coordinator.updatePinSize(on: map, multiplier: pinSizeMultiplier)
            context.coordinator.updateLayerFilters(on: map, visibleCategories: visibleCategories)
            context.coordinator.updateSource(
                on: map,
                features: features,
                pinPresentation: pinPresentation,
                trackReplayPulsePlaceIDs: trackReplayPulsePlaceIDs
            )
            context.coordinator.updateTrackSource(on: map, snapshot: trackSourceSnapshot)
        }
        context.coordinator.updatePinAccessibilityElements(on: map)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        private final class PinAccessibilityElement: UIAccessibilityElement {
            let placeID: String
            weak var viewContainer: UIView?
            var activate: ((String) -> Void)?

            init(placeID: String, container: MapAccessibilityContainerView) {
                self.placeID = placeID
                viewContainer = container
                super.init(accessibilityContainer: container)
            }

            func configure(content: MapPinAccessibilityContent, frame: CGRect) {
                accessibilityIdentifier = content.identifier
                accessibilityLabel = content.label
                accessibilityHint = content.hint
                accessibilityTraits = [.button]
                accessibilityFrameInContainerSpace = frame
                if let viewContainer {
                    accessibilityFrame = UIAccessibility.convertToScreenCoordinates(frame, in: viewContainer)
                }
            }

            override func accessibilityActivate() -> Bool {
                activate?(placeID)
                return true
            }
        }

        var onCameraIdle: (BBox, Int) -> Void
        var onUserPanned: () -> Void
        var onTapPlace: (String) -> Void
        var onTapEmpty: () -> Void
        var onMapReady: (String?) -> Void
        var onFeaturesApplied: () -> Void
        var onStyleWillReload: () -> Void
        var onMapLoadFailed: () -> Void
        var debugExposeFixturePinDiagnostics = false
        var debugReportProjectedFeatureDiagnostics: ([ProjectedFeatureDiagnostic]) -> Void = { _ in }
        var debugReportMapUpdateStatus: (String) -> Void = { _ in }
        var debugReportTrackSourceStatus: (String) -> Void = { _ in }
        var debugReportTapStatus: (String) -> Void = { _ in }
        var debugReportPinLayerSize: (String) -> Void = { _ in }
        weak var container: MapAccessibilityContainerView?
        weak var map: MLNMapView?
        var currentWorldPMTilesURL: String?
        var currentRegionPMTilesURL: String?
        var currentCoverageBBoxes: [CoverageBBox] = []
        var currentShowsCoverageShading = true
        var currentThemeID: String?
        var desiredVisibleCategories: Set<String>?
        var currentVisibleCategories: Set<String>?
        var desiredPinSizeMultiplier = PinSize.defaultMultiplier
        var currentPinSize: PinSize?
        var pendingFeatures: [(MapPlace, PinState)] = []
        var pendingPinPresentation: PinPresentation = .discovery
        var pendingTrackReplayPulsePlaceIDs: Set<String> = []
        var pendingTrackSourceSnapshot = TrackSourceSnapshot.empty
        var renderedFeatures: [(MapPlace, PinState)] = []
        var renderedTrackSignature: String?
        var pinAccessibilityNames: [String: String] = [:]
        private var pinAccessibilityElements: [String: PinAccessibilityElement] = [:]
#if DEBUG
        private var needsProjectedDiagnosticsRenderSample = false
#endif
        private var lastAppliedCameraRequestID: Int?

        struct StyleReload: Equatable {
            let url: URL
            let worldPMTilesURL: String?
            let regionPMTilesURL: String?
            let coverageBBoxes: [CoverageBBox]
            let showsCoverageShading: Bool
            let themeID: String
        }

        init(
            onCameraIdle: @escaping (BBox, Int) -> Void,
            onUserPanned: @escaping () -> Void,
            onTapPlace: @escaping (String) -> Void,
            onTapEmpty: @escaping () -> Void,
            onMapReady: @escaping (String?) -> Void,
            onFeaturesApplied: @escaping () -> Void,
            onStyleWillReload: @escaping () -> Void,
            onMapLoadFailed: @escaping () -> Void
        ) {
            self.onCameraIdle = onCameraIdle
            self.onUserPanned = onUserPanned
            self.onTapPlace = onTapPlace
            self.onTapEmpty = onTapEmpty
            self.onMapReady = onMapReady
            self.onFeaturesApplied = onFeaturesApplied
            self.onStyleWillReload = onStyleWillReload
            self.onMapLoadFailed = onMapLoadFailed
        }

        func prepareStyleReload(
            worldPMTilesURL: String?,
            regionPMTilesURL: String?,
            coverageBBoxes: [CoverageBBox],
            showsCoverageShading: Bool = true,
            theme: MapTheme,
            makeStyleURL: ((String?, String?, [CoverageBBox], MapTheme) -> URL?)? = nil
        ) -> StyleReload? {
            let effectiveCoverageBBoxes = showsCoverageShading ? coverageBBoxes : []
            guard currentWorldPMTilesURL != worldPMTilesURL
                || currentRegionPMTilesURL != regionPMTilesURL
                || currentCoverageBBoxes != effectiveCoverageBBoxes
                || currentShowsCoverageShading != showsCoverageShading
                || currentThemeID != theme.id
            else { return nil }
            let makeStyleURL = makeStyleURL ?? styleURL
            guard let url = makeStyleURL(worldPMTilesURL, regionPMTilesURL, effectiveCoverageBBoxes, theme) else { return nil }
            return StyleReload(
                url: url,
                worldPMTilesURL: worldPMTilesURL,
                regionPMTilesURL: regionPMTilesURL,
                coverageBBoxes: effectiveCoverageBBoxes,
                showsCoverageShading: showsCoverageShading,
                themeID: theme.id
            )
        }

        func commitStyleReload(_ reload: StyleReload) {
            currentWorldPMTilesURL = reload.worldPMTilesURL
            currentRegionPMTilesURL = reload.regionPMTilesURL
            currentCoverageBBoxes = reload.coverageBBoxes
            currentShowsCoverageShading = reload.showsCoverageShading
            currentThemeID = reload.themeID
        }

        func consumeCameraRequest(_ id: Int) -> Bool {
            guard lastAppliedCameraRequestID != id else { return false }
            lastAppliedCameraRequestID = id
            return true
        }

        func applyCameraRequest(_ request: ViewportCameraRequest, on map: MLNMapView) {
            guard request.fitBounds else {
                map.setCenter(request.viewport.center, zoomLevel: Double(request.viewport.zoom), animated: true)
                return
            }
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(
                    latitude: request.viewport.bbox.minLat,
                    longitude: request.viewport.bbox.minLon
                ),
                ne: CLLocationCoordinate2D(
                    latitude: request.viewport.bbox.maxLat,
                    longitude: request.viewport.bbox.maxLon
                )
            )
            map.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: 92, left: 28, bottom: 132, right: 28),
                animated: true,
                completionHandler: nil
            )
        }

        func styleURL(
            worldPMTilesURL: String?,
            regionPMTilesURL: String?,
            coverageBBoxes: [CoverageBBox],
            theme: MapTheme
        ) -> URL? {
            let style = paperBasemapStyle(
                worldPMTilesURL: worldPMTilesURL,
                regionPMTilesURL: regionPMTilesURL,
                coverageBBoxes: coverageBBoxes,
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
            onMapReady(currentThemeID)

            if style.source(withIdentifier: PinLayers.sourceID) == nil {
                style.addSource(MLNShapeSource(identifier: PinLayers.sourceID, shape: nil, options: nil))
            }
            guard let source = style.source(withIdentifier: PinLayers.sourceID) as? MLNShapeSource else { return }
            if style.source(withIdentifier: TrackLayers.sourceID) == nil {
                style.addSource(MLNShapeSource(identifier: TrackLayers.sourceID, shape: nil, options: nil))
            }
            let pinSize = PinSize(multiplier: desiredPinSizeMultiplier)

            let circle = MLNCircleStyleLayer(identifier: "pins-circle", source: source)
            circle.circleOpacity = NSExpression(mglJSONObject: PinLayers.fadeOpacityExpression().foundationObject)
            circle.circleColor = NSExpression(mglJSONObject: PinLayers.pinColorExpression().foundationObject)
            circle.circleRadius = Self.mapExpression(PinLayers.trackReplayPulseExpression(base: pinSize.circleRadiusExpression))
            style.addLayer(circle)
            addTrackLine(style: style)

            addCategoryIcon(source: source, style: style, pinSize: pinSize)
            addBadge(id: "pins-bookmark", icon: "badge-bookmark", filter: PinLayers.bookmarkFilter(), pinSize: pinSize, offset: pinSize.bookmarkOffset, source: source, style: style)
            addBadge(id: "pins-heart", icon: "badge-heart", filter: PinLayers.heartFilter(), pinSize: pinSize, offset: pinSize.heartOffset, source: source, style: style)
            currentVisibleCategories = nil
            currentPinSize = pinSize
#if DEBUG
            reportPinLayerSize(in: style, pinSize: pinSize)
#endif
            updateLayerFilters(on: mapView, visibleCategories: desiredVisibleCategories)
            updateSource(
                on: mapView,
                features: pendingFeatures,
                pinPresentation: pendingPinPresentation,
                trackReplayPulsePlaceIDs: pendingTrackReplayPulsePlaceIDs
            )
            renderedTrackSignature = nil
            updateTrackSource(on: mapView, snapshot: pendingTrackSourceSnapshot)
            updatePinAccessibilityElements(on: mapView)
            reportViewport(mapView)
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            onMapLoadFailed()
        }

#if DEBUG
        func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
            guard debugExposeFixturePinDiagnostics,
                  needsProjectedDiagnosticsRenderSample,
                  !pendingFeatures.isEmpty
            else { return }
            needsProjectedDiagnosticsRenderSample = false
            reportProjectedFeatureDiagnostics(on: mapView, features: pendingFeatures)
        }
#endif

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            if reason.contains(.gesturePan) || reason.contains(.gestureRotate) {
                onUserPanned()
            }
            updatePinAccessibilityElements(on: mapView)
            reportViewport(mapView)
        }

        func updateSource(
            on map: MLNMapView,
            features: [(MapPlace, PinState)],
            pinPresentation: PinPresentation,
            trackReplayPulsePlaceIDs: Set<String>
        ) {
            guard let style = map.style else {
                renderedFeatures = []
                debugReportMapUpdateStatus("source no-style features:\(features.count)")
                updatePinAccessibilityElements(on: map)
                return
            }
            guard let source = style.source(withIdentifier: PinLayers.sourceID) as? MLNShapeSource else {
                renderedFeatures = []
                debugReportMapUpdateStatus("source no-pin-source features:\(features.count)")
                updatePinAccessibilityElements(on: map)
                return
            }
            let collection = FeatureEncoding.featureCollection(features.map {
                FeatureEncoding.feature(
                    $0.0,
                    $0.1,
                    pinPresentation: pinPresentation,
                    trackReplayPulse: trackReplayPulsePlaceIDs.contains($0.0.id)
                )
            })
            guard let json = try? collection.jsonString(),
                  let shape = try? MLNShape(data: Data(json.utf8), encoding: String.Encoding.utf8.rawValue)
            else {
                debugReportMapUpdateStatus("source shape-failed features:\(features.count)")
                return
            }
            source.shape = shape
            renderedFeatures = features
            debugReportMapUpdateStatus("source applied features:\(features.count)")
            updatePinAccessibilityElements(on: map)
            if !features.isEmpty {
                onFeaturesApplied()
#if DEBUG
                if debugExposeFixturePinDiagnostics {
                    needsProjectedDiagnosticsRenderSample = true
                    reportProjectedFeatureDiagnostics(on: map, features: features)
                    Task { @MainActor [weak self, weak map] in
                        guard let self, let map else { return }
                        self.reportProjectedFeatureDiagnostics(on: map, features: features)
                    }
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
            updatePinAccessibilityElements(on: map)
        }

        func updateTrackSource(on map: MLNMapView, snapshot: TrackSourceSnapshot) {
            guard renderedTrackSignature != snapshot.signature else { return }
            guard let style = map.style,
                  let source = style.source(withIdentifier: TrackLayers.sourceID) as? MLNShapeSource
            else {
                debugReportTrackSourceStatus("track source missing")
                return
            }
            guard let shape = Self.shape(from: snapshot.data) else {
                source.shape = Self.emptyTrackShape()
                renderedTrackSignature = snapshot.signature
                debugReportTrackSourceStatus("track source shape-failed")
                return
            }
            source.shape = shape
            renderedTrackSignature = snapshot.signature
            debugReportTrackSourceStatus(
                "track source applied segments:\(snapshot.segmentCount) layer:\(style.layer(withIdentifier: TrackLayers.lineLayerID) != nil)"
            )
        }

        func updatePinSize(on map: MLNMapView, multiplier: Double) {
            let pinSize = PinSize(multiplier: multiplier)
            guard currentPinSize != pinSize,
                  let style = map.style
            else { return }
            currentPinSize = pinSize
            if let circle = style.layer(withIdentifier: "pins-circle") as? MLNCircleStyleLayer {
                circle.circleRadius = Self.mapExpression(PinLayers.trackReplayPulseExpression(base: pinSize.circleRadiusExpression))
            }
            if let icon = style.layer(withIdentifier: "pins-icon") as? MLNSymbolStyleLayer {
                icon.iconScale = Self.mapExpression(PinLayers.trackReplayPulseExpression(base: pinSize.categoryIconScaleExpression))
            }
            if let bookmark = style.layer(withIdentifier: "pins-bookmark") as? MLNSymbolStyleLayer {
                bookmark.iconScale = Self.mapExpression(pinSize.badgeIconScaleExpression)
                setIconOffset(pinSize.bookmarkOffset, on: bookmark)
            }
            if let heart = style.layer(withIdentifier: "pins-heart") as? MLNSymbolStyleLayer {
                heart.iconScale = Self.mapExpression(pinSize.badgeIconScaleExpression)
                setIconOffset(pinSize.heartOffset, on: heart)
            }
            updatePinAccessibilityElements(on: map)
#if DEBUG
            reportPinLayerSize(in: style, pinSize: pinSize)
#endif
        }

        func updatePinAccessibilityElements(on map: MLNMapView) {
            guard let container,
                  container.bounds.width > 0,
                  container.bounds.height > 0
            else { return }

            let pinSize = currentPinSize ?? PinSize(multiplier: desiredPinSizeMultiplier)
            let targetSide = Self.pinAccessibilityTargetSide(pinSize)
            var visibleIDs = Set<String>()
            let candidates = renderedFeatures
                .filter { feature in Self.isCategoryVisuallyExposed(feature.0.category, visibleCategories: currentVisibleCategories) }
                .compactMap { place, state -> (String, MapPinAccessibilityContent, CGRect)? in
                    let coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
                    let point = map.convert(coordinate, toPointTo: container)
                    let frame = CGRect(
                        x: point.x - targetSide / 2,
                        y: point.y - targetSide / 2,
                        width: targetSide,
                        height: targetSide
                    )
                    guard frame.intersects(container.bounds) else { return nil }
                    let content = MapPinAccessibilityContent(
                        place: place,
                        state: state,
                        name: pinAccessibilityNames[place.id]
                    )
                    return (place.id, content, frame)
                }
            var accessibilityElements: [Any] = []
            for (placeID, content, frame) in candidates {
                visibleIDs.insert(placeID)
                let element = pinAccessibilityElements[placeID] ?? {
                    let next = PinAccessibilityElement(placeID: placeID, container: container)
                    next.activate = { [weak self] placeID in
                        self?.onTapPlace(placeID)
                    }
                    pinAccessibilityElements[placeID] = next
                    return next
                }()
                element.configure(content: content, frame: frame)
                accessibilityElements.append(element)
            }
            accessibilityElements.append(container.surfaceAccessibilityView)
            pinAccessibilityElements = pinAccessibilityElements.filter { visibleIDs.contains($0.key) }
            container.accessibilityElements = accessibilityElements
        }

        private static func pinAccessibilityTargetSide(_ pinSize: PinSize) -> CGFloat {
            // Minimum tracks Apple's 44 pt control target; visual radius keeps larger pins' frames honest.
            max(44, CGFloat((pinSize.circleRadius * 2) + 12))
        }

        private static func isCategoryVisuallyExposed(_ category: String, visibleCategories: Set<String>?) -> Bool {
            PinLayers.isCategoryVisible(category, visibleCategories: visibleCategories)
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

        private func addCategoryIcon(source: MLNShapeSource, style: MLNStyle, pinSize: PinSize) {
            let layer = MLNSymbolStyleLayer(identifier: "pins-icon", source: source)
            layer.iconImageName = NSExpression(mglJSONObject: PinLayers.categoryIconExpression().foundationObject)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            layer.iconScale = Self.mapExpression(PinLayers.trackReplayPulseExpression(base: pinSize.categoryIconScaleExpression))
            layer.iconOpacity = NSExpression(mglJSONObject: PinLayers.fadeOpacityExpression().foundationObject)
            style.addLayer(layer)
        }

        private func addTrackLine(style: MLNStyle) {
            guard let source = style.source(withIdentifier: TrackLayers.sourceID) as? MLNShapeSource,
                  style.layer(withIdentifier: TrackLayers.lineLayerID) == nil
            else { return }
            let line = MLNLineStyleLayer(identifier: TrackLayers.lineLayerID, source: source)
            line.lineCap = NSExpression(forConstantValue: "round")
            line.lineJoin = NSExpression(forConstantValue: "round")
            line.lineColor = NSExpression(forConstantValue: MapThemeColor.uiColor(hex: TrackLayers.lineColor))
            line.lineOpacity = NSExpression(forConstantValue: TrackLayers.lineOpacity)
            line.lineWidth = NSExpression(forConstantValue: TrackLayers.lineWidth)
            line.lineDashPattern = NSExpression(forConstantValue: TrackLayers.lineDashPatternValues)
            if let circle = style.layer(withIdentifier: "pins-circle") {
                style.insertLayer(line, below: circle)
            } else {
                style.addLayer(line)
            }
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
        private func reportPinLayerSize(in style: MLNStyle, pinSize: PinSize) {
            let circle = style.layer(withIdentifier: "pins-circle") as? MLNCircleStyleLayer
            let icon = style.layer(withIdentifier: "pins-icon") as? MLNSymbolStyleLayer
            let bookmark = style.layer(withIdentifier: "pins-bookmark") as? MLNSymbolStyleLayer
            let heart = style.layer(withIdentifier: "pins-heart") as? MLNSymbolStyleLayer
            let expectedCircleRadius = PinLayers.trackReplayPulseExpression(base: pinSize.circleRadiusExpression)
            let expectedIconScale = PinLayers.trackReplayPulseExpression(base: pinSize.categoryIconScaleExpression)
            debugReportPinLayerSize(
                "pin-layer-size:\(pinSize.accessibilityValue) " +
                    "circle:\(Self.expression(circle?.circleRadius, matches: expectedCircleRadius)) " +
                    "icon:\(Self.expression(icon?.iconScale, matches: expectedIconScale)) " +
                    "bookmark:\(Self.expression(bookmark?.iconScale, matches: pinSize.badgeIconScaleExpression)) " +
                    "heart:\(Self.expression(heart?.iconScale, matches: pinSize.badgeIconScaleExpression))"
            )
        }

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
            debugReportProjectedFeatureDiagnostics(diagnostics)
        }
#endif

        private func addBadge(id: String, icon: String, filter: JSONValue, pinSize: PinSize, offset: JSONValue, source: MLNShapeSource, style: MLNStyle) {
            let layer = MLNSymbolStyleLayer(identifier: id, source: source)
            layer.iconImageName = NSExpression(forConstantValue: icon)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconScale = Self.mapExpression(pinSize.badgeIconScaleExpression)
            setIconOffset(offset, on: layer)
            layer.predicate = NSPredicate(mglJSONObject: filter.foundationObject)
            style.addLayer(layer)
        }

        private static func mapExpression(_ value: JSONValue) -> NSExpression {
            NSExpression(mglJSONObject: value.foundationObject)
        }

        private static func shape(from data: Data) -> MLNShape? {
            try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
        }

        private static func emptyTrackShape() -> MLNShape? {
            shape(from: TrackSourceSnapshot.empty.data)
        }

        private static func expression(_ expression: NSExpression?, matches expected: JSONValue) -> Bool {
            guard let expression else { return false }
            let expectedExpression = mapExpression(expected)
            return expression.isEqual(expectedExpression)
                || expression.description == expectedExpression.description
        }

        private func setIconOffset(_ offset: JSONValue, on layer: MLNSymbolStyleLayer) {
            if case let .array(values) = offset,
               values.count == 2,
               case let .double(x) = values[0],
               case let .double(y) = values[1] {
                layer.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: x, dy: y)))
            }
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
            let configuration = UIImage.SymbolConfiguration(pointSize: PinLayers.categorySymbolPointSize, weight: .semibold)
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
