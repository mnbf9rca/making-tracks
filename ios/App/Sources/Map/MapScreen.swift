import CoreLocation
import Observation
import SwiftUI
import UIKit
@preconcurrency import MapLibre
import MakingTracksCore
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles

struct ViewportSeed: Sendable {
    let bbox: BBox
    let zoom: Int

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: bbox.center.lat, longitude: bbox.center.lon)
    }

    static let kl = ViewportSeed(
        bbox: BBox(minLon: 101.64, minLat: 3.09, maxLon: 101.74, maxLat: 3.19),
        zoom: 12
    )

    static let ocean = ViewportSeed(
        bbox: BBox(minLon: -170, minLat: -10, maxLon: -150, maxLat: 10),
        zoom: 4
    )

    static let uk = ViewportSeed(
        bbox: BBox(minLon: -8.5, minLat: 49.5, maxLon: 2.5, maxLat: 59.5),
        zoom: 6
    )

    static func selected(_ value: String?) -> ViewportSeed {
        switch value {
        case "ocean":
            return .ocean
        case "uk":
            return .uk
        default:
            return .kl
        }
    }
}

enum MenuDestination: Hashable {
    case lists
    case offlineMaps
    case settings
    case about
}

@Observable
final class AppShellModel {
    var isMenuPresented = false
    var deepLinkPath: MenuDestination?
}

struct OfflineDownloadProgress: Sendable {
    let fractionComplete: Double

    var percentComplete: Int {
        Int((boundedFraction * 100).rounded())
    }

    private var boundedFraction: Double {
        guard fractionComplete.isFinite else { return 0 }
        return min(max(fractionComplete, 0), 1)
    }
}

struct MapScreen: View {
    static let themeStorageKey = "map.theme.id"

    let database: AppDatabase
    let startupViewport: ViewportSeed
    var isFixtureMap = false
    var debugInstallOfflineRegion: String?
    var debugForceTileNetworkOffline = false
    var offlineDownloadProgress: OfflineDownloadProgress?
    var debugExposeFixturePinDiagnostics = false

    @State private var model: MapScreenModel?
    @StateObject private var locationPermission: LocationPermission
    @AppStorage(Self.themeStorageKey) private var selectedThemeID = MapTheme.definedPaper.id
    @Environment(\.scenePhase) private var scenePhase
    @State private var worldPMTilesURL: String? = WorldBasemap.pmtilesURL()
    @State private var features: [(MapPlace, PinState)] = []
    @State private var regionPMTilesURL: String?
    @State private var attribution: [Attribution] = []
    @State private var debugOfflineStatus: String?
    @State private var appShell = AppShellModel()
    @State private var cardPresentation = PlaceCardPresentation()
    @State private var showLayers = false
    @State private var layerVisibility = MapLayerVisibility()
    @State private var appliedShowHiddenPlaces = false
    @State private var loadState: TileLoadState = .unavailable
    @State private var isMapReady = false
    @State private var hasLoadedFixtureFeatures = false
    @State private var viewportRequestID = 0
    @State private var stateEpoch = 0
    @State private var currentViewport: ViewportSeed?
    @State private var fixtureVisitCount = 0
    @State private var userTrackingMode: MLNUserTrackingMode = .none
    @State private var pendingLocateMeActivation = false
    @State private var hiddenToast: HiddenToast?
    @State private var hiddenToastDismissTask: Task<Void, Never>?
    @State private var nextHiddenToastID = 0
    private let viewportRefreshDebouncer = ViewportRefreshDebouncer()
    @State private var suppressedNearbyPromptPlaceIDs: Set<String> = []
    @State private var nearbyPromptNames: [String: String] = [:]
    @State private var debugProjectedFixturePins: [ProjectedFeatureDiagnostic] = []
    @State private var debugMapUpdateStatus = "not-updated"
    @State private var debugTapStatus = "not-tapped"
    private let locationManager: AppLocationManager
    private static let primaryFixturePlaceID = fixturePlaces[0].placeID
    private static let nearbyPromptDistanceMeters: CLLocationDistance = 125

    init(
        database: AppDatabase,
        startupViewport: ViewportSeed,
        isFixtureMap: Bool = false,
        debugInstallOfflineRegion: String? = nil,
        debugForceTileNetworkOffline: Bool = false,
        offlineDownloadProgress: OfflineDownloadProgress? = nil,
        debugExposeFixturePinDiagnostics: Bool = false,
        locationManager: AppLocationManager = AppLocationManager()
    ) {
        self.database = database
        self.startupViewport = startupViewport
        self.isFixtureMap = isFixtureMap
        self.debugInstallOfflineRegion = debugInstallOfflineRegion
        self.debugForceTileNetworkOffline = debugForceTileNetworkOffline
        self.offlineDownloadProgress = offlineDownloadProgress
        self.debugExposeFixturePinDiagnostics = debugExposeFixturePinDiagnostics
        self.locationManager = locationManager
        _features = State(initialValue: isFixtureMap ? Self.initialFixtureFeatures() : [])
        _locationPermission = StateObject(wrappedValue: LocationPermission(manager: locationManager))
    }

    var body: some View {
        ZStack {
            MLNMapViewRepresentable(
                worldPMTilesURL: worldPMTilesURL,
                regionPMTilesURL: regionPMTilesURL,
                theme: selectedTheme,
                startupViewport: startupViewport,
                features: features,
                visibleCategories: layerVisibility.visibleCategories,
                locationManager: locationManager,
                showsUserLocation: showsUserLocation,
                userTrackingMode: userTrackingMode,
                onCameraIdle: { bbox, zoom in
                    Task { @MainActor in
                        currentViewport = ViewportSeed(bbox: bbox, zoom: zoom)
                        scheduleViewportRefresh(
                            bbox: bbox,
                            zoom: zoom,
                            requestID: nextViewportRequestID(),
                            stateEpoch: currentStateEpoch()
                        )
                    }
                },
                onUserPanned: {
                    userTrackingMode = .none
                },
                onTapPlace: { placeID in
                    cardPresentation.show(placeID: placeID)
                },
                onTapEmpty: {
                    cardPresentation.dismiss()
                },
                onMapReady: {
                    isMapReady = true
                },
                onFeaturesApplied: {
                    hasLoadedFixtureFeatures = true
                },
                onStyleWillReload: {
                    isMapReady = false
                    hasLoadedFixtureFeatures = false
                    debugProjectedFixturePins = []
                },
                debugReportProjectedFeatureDiagnostics: { diagnostics in
                    guard debugExposeFixturePinDiagnostics else { return }
                    debugProjectedFixturePins = diagnostics
                },
                debugReportMapUpdateStatus: { status in
                    guard debugExposeFixturePinDiagnostics else { return }
                    debugMapUpdateStatus = status
                },
                debugReportTapStatus: { status in
                    guard debugExposeFixturePinDiagnostics else { return }
                    debugTapStatus = status
                }
            )
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                shellChrome
                    .padding(.top, 72)
                    .padding(.leading, 16)
            }
            .overlay {
                if !isMapReady || (isFixtureMap && !hasLoadedFixtureFeatures) {
                    ZStack {
                        Color.black.opacity(0.04)
                            .ignoresSafeArea()
                        ProgressView()
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("map.loading")
                }
            }
#if DEBUG
            .overlay(alignment: .topLeading) {
                if isFixtureMap && debugExposeFixturePinDiagnostics {
                    VStack(alignment: .leading, spacing: 2) {
                        if hasLoadedFixtureFeatures {
                            Text(verbatim: "applied")
                                .font(.system(size: 8))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 18)
                                .accessibilityIdentifier("map.features-applied")
                                .allowsHitTesting(false)
                        }

                        ForEach(debugProjectedFixturePins) { pin in
                            Text(verbatim: pin.isHitTestable ? "hit" : "miss")
                                .font(.system(size: 8))
                                .foregroundStyle(.red)
                                .frame(width: 96, height: 18, alignment: .leading)
                                .accessibilityIdentifier("map.fixture-pin.\(pin.placeID)")
                                .accessibilityValue(
                                    "x:\(pin.normalizedX.formatted(.number.precision(.fractionLength(6)))) y:\(pin.normalizedY.formatted(.number.precision(.fractionLength(6))))"
                                )
                                .allowsHitTesting(false)
                            }
                    }
                    .allowsHitTesting(false)
                }
            }
#endif
            .overlay(alignment: .topTrailing) {
                statusChrome
                    .padding(.top, 72)
                    .padding(.trailing, 16)
            }
            .overlay(alignment: .bottomLeading) {
                attributionText
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .bottomTrailing) {
                locationChrome
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .bottom) {
                if let prompt = nearbyPromptCandidate {
                    nearbyPromptView(for: prompt)
                        .padding(.bottom, 88)
                        .padding(.horizontal, 16)
                }
            }
            .overlay(alignment: .bottom) {
                if let hiddenToast {
                    hiddenToastView(for: hiddenToast)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 16)
                }
            }
        }
        .sheet(isPresented: $appShell.isMenuPresented) {
            AppMenuSheet(
                shell: appShell,
                attribution: attribution,
                selectedThemeID: $selectedThemeID,
                locationStatus: locationMenuStatus,
                openLocationSettings: openLocationSettings
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            LocationSessionPolicies.handleScenePhaseChange(
                newPhase,
                userTrackingMode: &userTrackingMode,
                stopUpdatingLocation: { locationManager.stopUpdatingLocation() },
                stopUpdatingHeading: { locationManager.stopUpdatingHeading() }
            )
        }
        .onChange(of: locationPermission.authorizationStatus) { _, newStatus in
            LocationSessionPolicies.handleAuthorizationStatusChange(
                newStatus,
                userTrackingMode: &userTrackingMode,
                pendingLocateMeActivation: &pendingLocateMeActivation
            )
        }
        .task {
            await start()
            if let model {
                await observeChanges(from: model)
            }
        }
        .onChange(of: layerVisibility) { _, visibility in
            Task { @MainActor in
                await applyLayerVisibility(visibility)
            }
        }
        .sheet(isPresented: $showLayers) {
            LayersSheet(
                visibility: $layerVisibility
            )
                .presentationDetents([.medium, .large])
        }
        .sheet(item: cardPresentationItemBinding) { presentation in
            PlaceCardSheet(
                placeID: presentation.placeID,
                model: model,
                onHide: { placeID, name in
                    showHiddenToast(placeID: placeID, name: name)
                },
                showHiddenMode: layerVisibility.showHiddenPlaces
            )
        }
        .onDisappear {
            cancelHiddenToastDismissTask()
        }
    }

    private var cardPresentationItemBinding: Binding<PlaceCardPresentation.Item?> {
        Binding(
            get: { cardPresentation.item },
            set: { item in
                if item == nil {
                    cardPresentation.dismiss()
                }
            }
        )
    }

    private func showHiddenToast(placeID: String, name: String) {
        nextHiddenToastID += 1
        let toast = HiddenToast(id: nextHiddenToastID, placeID: placeID, name: name)
        hiddenToast = toast
        UIAccessibility.post(notification: .announcement, argument: "\(name) hidden. Undo available.")
        cancelHiddenToastDismissTask()
        hiddenToastDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if hiddenToast == toast {
                    hiddenToast = nil
                    hiddenToastDismissTask = nil
                }
            }
        }
    }

    private func undoHiddenToast() async {
        guard let toast = hiddenToast, let model else { return }
        do {
            try await model.setHidden(placeID: toast.placeID, hidden: false)
            await MainActor.run {
                guard hiddenToast == toast else { return }
                cancelHiddenToastDismissTask()
                self.hiddenToast = nil
                UIAccessibility.post(notification: .announcement, argument: "\(toast.name) restored.")
            }
        } catch {
            return
        }
    }

    private func cancelHiddenToastDismissTask() {
        hiddenToastDismissTask?.cancel()
        hiddenToastDismissTask = nil
    }

    private func hiddenToastView(for _: HiddenToast) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "Hidden — Undo")
                .font(.callout.weight(.medium))
            Button("Undo") {
                Task { await undoHiddenToast() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("place-card.hide.undo")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }

    private var mapChrome: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if loadState != .ok {
                Text(verbatim: loadState.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            if isFixtureMap {
                Text(verbatim: "Tracks visits: \(fixtureVisitCount)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("tracks.visit-count.\(Self.primaryFixturePlaceID)")
#if DEBUG
                HStack(spacing: 6) {
                    Button("Hide fixture") {
                        Task { await setPrimaryFixtureHidden(true) }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("debug.hide-fixture")

                    Button("Unhide fixture") {
                        Task { await setPrimaryFixtureHidden(false) }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("debug.unhide-fixture")
                }
                Text(verbatim: "Fixture hidden: \(isPrimaryFixtureHidden ? "true" : "false")")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("debug.fixture-hidden-state")
#endif
            }

#if DEBUG
            if debugExposeFixturePinDiagnostics {
                Text(verbatim: "ready:\(isMapReady) applied:\(hasLoadedFixtureFeatures) features:\(features.count)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-readiness")

                Text(verbatim: debugMapUpdateStatus)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-source-status")

                Text(verbatim: debugTapStatus)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-tap-status")
            }

            if let debugOfflineStatus {
                Text(verbatim: debugOfflineStatus)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("debug.offline-status")
            }
#endif
        }
    }

    private var statusChrome: some View {
        mapChrome
    }

    private var selectedTheme: MapTheme {
        MapTheme.named(selectedThemeID)
    }

#if DEBUG
    private var isPrimaryFixtureHidden: Bool {
        model?.hiddenIDs.contains(Self.primaryFixturePlaceID) ?? false
    }
#endif

    private var shellChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                appShell.deepLinkPath = nil
                appShell.isMenuPresented = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Menu")
            .accessibilityHint("Opens app menu")
            .accessibilityIdentifier("map.menu")

            if let offlineDownloadProgress {
                Button {
                    appShell.deepLinkPath = .offlineMaps
                    appShell.isMenuPresented = true
                } label: {
                    Label(
                        "Offline maps \(offlineDownloadProgress.percentComplete)%",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityIdentifier("map.download-progress")
            }

            layersButton
        }
    }

    private var attributionText: some View {
        Text(verbatim: "© OpenStreetMap")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityLabel("OpenStreetMap attribution")
            .accessibilityIdentifier("map.openstreetmap-attribution")
    }

    private var locationMenuStatus: LocationMenuStatus {
        LocationMenuStatus(
            label: locationPermission.isLocationOff ? "Location off" : "Location available",
            canOpenSettings: locationPermission.isLocationOff
        )
    }

    private var layersButton: some View {
        Button {
            showLayers = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .foregroundStyle(layerVisibility.isDefault ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
                .frame(width: 44, height: 44)
                .background(layerVisibility.isDefault ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.accentColor), in: Circle())
        }
        .accessibilityLabel("Layers")
        .accessibilityHint("Shows map layer controls")
        .accessibilityValue(layerVisibility.isDefault ? "Default" : "Custom")
        .accessibilityIdentifier("map.layers")
    }

    private var locationChrome: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if locationPermission.isLocationOff {
                locationOffBanner
            }

            locateMeButton
        }
    }

    private var locationOffBanner: some View {
        HStack(spacing: 8) {
            Text("Location is off")
                .font(.caption2)
                .fontWeight(.semibold)

            LocationSettingsButton {
                openLocationSettings()
            }
            .frame(width: 68, height: 16)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var locateMeButton: some View {
        Button {
            handleLocateMeTap()
        } label: {
            Image(systemName: locateMeButtonSystemName)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(locateMeButtonAccessibilityLabel)
        .accessibilityHint("Centers the map on your location")
        .accessibilityIdentifier("map.locate-me")
    }

    private var locateMeButtonSystemName: String {
        switch userTrackingMode {
        case .none:
            return "location"
        case .follow:
            return "location.fill"
        case .followWithHeading:
            return "location.north.line"
        default:
            return "location"
        }
    }

    private var locateMeButtonAccessibilityLabel: String {
        switch userTrackingMode {
        case .none:
            return "Locate me"
        case .follow:
            return "Follow me"
        case .followWithHeading:
            return "Follow me with heading"
        default:
            return "Locate me"
        }
    }

    private var nearbyPromptCandidate: NearbyPromptCandidate? {
        guard showsUserLocation,
              userTrackingMode != .none,
              let coordinate = locationPermission.currentCoordinate
        else { return nil }

        guard let candidate = NearbyPromptSelector.candidate(
            features: features,
            names: nearbyPromptNames,
            userLatitude: coordinate.latitude,
            userLongitude: coordinate.longitude,
            maxDistanceMeters: Self.nearbyPromptDistanceMeters,
            suppressedPlaceIDs: suppressedNearbyPromptPlaceIDs,
            hiddenPlaceIDs: model?.hiddenIDs ?? []
        ) else { return nil }
        return NearbyPromptCandidate(
            placeID: candidate.placeID,
            name: candidate.name,
            distanceMeters: candidate.distanceMeters
        )
    }

    @ViewBuilder
    private func nearbyPromptView(for prompt: NearbyPromptCandidate) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(verbatim: "You're near \(prompt.name) — seen it?")
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Seen it") {
                handleNearbyPromptSeen(prompt)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("map.nearby-prompt.seen")

            Button {
                suppressedNearbyPromptPlaceIDs.insert(prompt.placeID)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Dismiss nearby prompt")
            .accessibilityIdentifier("map.nearby-prompt.dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.nearby-prompt")
    }

    private func start() async {
        if model == nil {
            model = try? MapScreenModel(
                database: database,
                fixturePlaces: isFixtureMap ? Self.fixturePlaces : [],
                forceTileNetworkOffline: debugForceTileNetworkOffline
            )
        }
        model?.setShowHidden(layerVisibility.showHiddenPlaces)
        appliedShowHiddenPlaces = layerVisibility.showHiddenPlaces
#if DEBUG
        if let debugInstallOfflineRegion, let model {
            await MainActor.run {
                debugOfflineStatus = "Installing \(debugInstallOfflineRegion)"
            }
            let status = await model.installDebugOfflineRegion(debugInstallOfflineRegion)
            await MainActor.run {
                debugOfflineStatus = status
            }
        } else if debugForceTileNetworkOffline {
            await MainActor.run {
                debugOfflineStatus = "Network disabled"
            }
        }
#endif
        await model?.refreshManifest()
        let nextRegionPMTilesURL = await model?.pmtilesURL
        let nextAttribution = await model?.attribution ?? []
        let nextLoadState = await model?.loadState ?? .unavailable
        await MainActor.run {
            regionPMTilesURL = nextRegionPMTilesURL
            attribution = nextAttribution
            loadState = nextLoadState
        }
        await refreshViewport(
            bbox: startupViewport.bbox,
            zoom: startupViewport.zoom,
            requestID: nextViewportRequestID(),
            stateEpoch: currentStateEpoch()
        )
        await refreshFixtureVisitCount()
    }

    @MainActor
    private func handleLocateMeTap() {
        LocationSessionPolicies.handleLocateMeTap(
            authorizationStatus: locationPermission.authorizationStatus,
            userTrackingMode: &userTrackingMode,
            requestCurrentLocation: { locationPermission.requestCurrentLocation() },
            openSettings: { openLocationSettings() },
            deferFollowUntilAuthorized: { pendingLocateMeActivation = true }
        )
    }

    @MainActor
    private func scheduleViewportRefresh(
        bbox: BBox,
        zoom: Int,
        requestID: Int,
        stateEpoch capturedStateEpoch: Int
    ) {
        viewportRefreshDebouncer.schedule { [bbox, zoom, requestID, capturedStateEpoch] in
            await refreshViewport(
                bbox: bbox,
                zoom: zoom,
                requestID: requestID,
                stateEpoch: capturedStateEpoch
            )
        }
    }

    @MainActor
    private func handleNearbyPromptSeen(_ prompt: NearbyPromptCandidate) {
        suppressedNearbyPromptPlaceIDs.insert(prompt.placeID)
        Task { @MainActor in
            do {
                try await model?.setVisited(placeID: prompt.placeID, visited: true)
            } catch {
                suppressedNearbyPromptPlaceIDs.remove(prompt.placeID)
                assertionFailure("Failed to persist nearby prompt seen state: \(error)")
            }
        }
    }

#if DEBUG
    @MainActor
    private func setPrimaryFixtureHidden(_ hidden: Bool) async {
        do {
            try await model?.setHidden(placeID: Self.primaryFixturePlaceID, hidden: hidden)
        } catch {
            assertionFailure("Failed to persist fixture hidden state: \(error)")
        }
    }
#endif

    private func openLocationSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    @MainActor
    private func nextViewportRequestID() -> Int {
        viewportRequestID += 1
        return viewportRequestID
    }

    @MainActor
    private func currentStateEpoch() -> Int {
        stateEpoch
    }

    private var showsUserLocation: Bool {
        LocationSessionPolicies.shouldShowUserLocation(
            authorizationStatus: locationPermission.authorizationStatus,
            userTrackingMode: userTrackingMode
        )
    }

    private func refreshViewport(
        bbox: BBox,
        zoom: Int,
        requestID: Int,
        stateEpoch capturedStateEpoch: Int
    ) async {
        guard let model else { return }
        let next = await model.features(in: bbox, zoom: zoom)
        let nextRegionPMTilesURL = await model.pmtilesURL
        let nextAttribution = await model.attribution
        let nextLoadState = await model.loadState
        var nextNearbyPromptNames: [String: String] = [:]
        for (place, _) in next {
            if let card = await model.cardModel(for: place.id) {
                nextNearbyPromptNames[place.id] = card.name
            }
        }
        await MainActor.run {
            guard requestID == viewportRequestID else { return }
            if capturedStateEpoch == stateEpoch {
                features = next
                nearbyPromptNames = nextNearbyPromptNames
                currentViewport = ViewportSeed(bbox: bbox, zoom: zoom)
            }
            regionPMTilesURL = nextRegionPMTilesURL
            attribution = nextAttribution
            loadState = nextLoadState
        }
    }

    @MainActor
    private func refreshCurrentViewport() async {
        stateEpoch += 1
        let viewport = currentViewport ?? startupViewport
        await refreshViewport(
            bbox: viewport.bbox,
            zoom: viewport.zoom,
            requestID: nextViewportRequestID(),
            stateEpoch: currentStateEpoch()
        )
    }

    private func observeChanges(from model: MapScreenModel) async {
        for await ids in model.changes {
            if model.consumeHiddenMembershipChange(overlapping: ids) {
                let refresh = await MainActor.run { () -> (viewport: ViewportSeed, requestID: Int, stateEpoch: Int) in
                    stateEpoch += 1
                    return (
                        viewport: currentViewport ?? startupViewport,
                        requestID: nextViewportRequestID(),
                        stateEpoch: currentStateEpoch()
                    )
                }
                await refreshViewport(
                    bbox: refresh.viewport.bbox,
                    zoom: refresh.viewport.zoom,
                    requestID: refresh.requestID,
                    stateEpoch: refresh.stateEpoch
                )
                await refreshFixtureVisitCount()
                continue
            }
            let states = await model.states(for: ids)
            await MainActor.run {
                stateEpoch += 1
                features = features.map { place, state in
                    (place, states[place.id] ?? state)
                }
            }
            await refreshFixtureVisitCount()
        }
    }

    private func refreshFixtureVisitCount() async {
        guard isFixtureMap, let model else { return }
        let count = await model.visitCount(placeID: Self.primaryFixturePlaceID)
        await MainActor.run {
            fixtureVisitCount = count
        }
    }

    @MainActor
    private func applyLayerVisibility(_ visibility: MapLayerVisibility) async {
        guard visibility.showHiddenPlaces != appliedShowHiddenPlaces else { return }
        guard let model else { return }
        model.setShowHidden(visibility.showHiddenPlaces)
        appliedShowHiddenPlaces = visibility.showHiddenPlaces
        await refreshCurrentViewport()
    }

    private struct NearbyPromptCandidate {
        let placeID: String
        let name: String
        let distanceMeters: CLLocationDistance
    }

    private struct HiddenToast: Equatable {
        let id: Int
        let placeID: String
        let name: String
    }

    private static let fixturePlaces = [
        try! PlaceRef(
            placeID: "mt1_00000000000000000000000000",
            name: "Ghost Sign",
            lat: 3.14,
            lon: 101.69,
            category: "attraction",
            tier: 3,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: """
            {"blurb":"A hand-painted sign still visible above the old shopfront.","category":"attraction","lat":3.14,"lon":101.69,"name":"Ghost Sign","place_id":"mt1_00000000000000000000000000","score":0.5,"source_refs":["osm:node/1"],"tier":3}
            """
        ),
        try! PlaceRef(
            placeID: "mt1_00000000000000000000000001",
            name: "Art Deco Cinema",
            lat: 3.16,
            lon: 101.702,
            category: "historic_building",
            tier: 3,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: """
            {"blurb":"A restored neighborhood cinema with stepped plasterwork and neon trim.","category":"historic_building","lat":3.16,"lon":101.702,"name":"Art Deco Cinema","place_id":"mt1_00000000000000000000000001","score":0.5,"source_refs":["osm:node/2"],"tier":3}
            """
        ),
    ]

    private static func initialFixtureFeatures() -> [(MapPlace, PinState)] {
        fixturePlaces.map { fixturePlace in
            (
                MapPlace(id: fixturePlace.placeID, lat: fixturePlace.lat, lon: fixturePlace.lon, tier: fixturePlace.tier),
                PinState(saved: false, visit: .none)
            )
        }
    }
}

private struct LocationMenuStatus: Sendable {
    let label: String
    let canOpenSettings: Bool
}

private struct AppMenuSheet: View {
    @Bindable var shell: AppShellModel
    let attribution: [Attribution]
    @Binding var selectedThemeID: String
    let locationStatus: LocationMenuStatus
    let openLocationSettings: () -> Void

    @State private var path: [MenuDestination] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            AppMenuRootView(path: $path)
                .navigationTitle("Menu")
                .navigationDestination(for: MenuDestination.self) { destination in
                    destinationView(destination)
                }
                .toolbar {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("menu.done")
                }
        }
        .onAppear {
            applyDeepLinkIfNeeded(resetToRootWhenNoDeepLink: true)
        }
        .onChange(of: shell.deepLinkPath) { _, _ in
            applyDeepLinkIfNeeded(resetToRootWhenNoDeepLink: false)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: MenuDestination) -> some View {
        switch destination {
        case .lists:
            destinationWithDone(ListsPlaceholderView())
        case .offlineMaps:
            destinationWithDone(OfflineMapsPlaceholderView())
        case .settings:
            destinationWithDone(SettingsView(
                selectedThemeID: $selectedThemeID,
                locationStatus: locationStatus,
                openLocationSettings: openLocationSettings
            ))
        case .about:
            destinationWithDone(AboutView(attribution: attribution))
        }
    }

    private func destinationWithDone<Content: View>(_ content: Content) -> some View {
        content.toolbar {
            Button("Done") { dismiss() }
                .accessibilityIdentifier("menu.done")
        }
    }

    private func applyDeepLinkIfNeeded(resetToRootWhenNoDeepLink: Bool) {
        guard let destination = shell.deepLinkPath else {
            if resetToRootWhenNoDeepLink {
                path = []
            }
            return
        }
        path = [destination]
        shell.deepLinkPath = nil
    }
}

private struct AppMenuRootView: View {
    @Binding var path: [MenuDestination]

    var body: some View {
        List {
            Button {
                path.append(.lists)
            } label: {
                menuRow(title: "Lists", subtitle: "Saved places and collections", systemImage: "list.bullet")
            }
            .accessibilityIdentifier("menu.row.lists")

            Button {
                path.append(.offlineMaps)
            } label: {
                menuRow(title: "Offline maps", subtitle: "Download regions for later", systemImage: "arrow.down.circle")
            }
            .accessibilityIdentifier("menu.row.offline-maps")

            Button {
                path.append(.settings)
            } label: {
                menuRow(title: "Settings", subtitle: "Map theme, location, and storage", systemImage: "gearshape")
            }
            .accessibilityIdentifier("menu.row.settings")

            Button {
                path.append(.about)
            } label: {
                menuRow(title: "About", subtitle: "Credits, attribution, and build info", systemImage: "info.circle")
            }
            .accessibilityIdentifier("menu.row.about")
        }
    }

    private func menuRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }
}

private struct ListsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Lists",
            systemImage: "list.bullet",
            description: Text("Saved lists will appear here.")
        )
        .navigationTitle("Lists")
    }
}

private struct OfflineMapsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Offline maps",
            systemImage: "arrow.down.circle",
            description: Text("Region downloads will appear here.")
        )
        .navigationTitle("Offline maps")
    }
}

private struct SettingsView: View {
    @Binding var selectedThemeID: String
    let locationStatus: LocationMenuStatus
    let openLocationSettings: () -> Void

    var body: some View {
        List {
            Section("Map theme") {
                Text(MapTheme.named(selectedThemeID).displayName)
                    .accessibilityIdentifier("settings.theme.selected")
                ForEach(MapTheme.allCandidates, id: \.id) { theme in
                    Button {
                        selectedThemeID = theme.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: theme.displayName)
                                Text(verbatim: theme.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if MapTheme.named(selectedThemeID).id == theme.id {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.theme.\(theme.id)")
                }
            }

            Section("Location") {
                HStack {
                    Label(locationStatus.label, systemImage: "location")
                    Spacer()
                    if locationStatus.canOpenSettings {
                        Button("Settings", action: openLocationSettings)
                            .accessibilityIdentifier("settings.location.open-system")
                    }
                }
            }

            Section("Storage") {
                Label("Storage details coming soon", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.storage.stub")
            }
        }
        .navigationTitle("Settings")
    }
}

private struct AboutView: View {
    let attribution: [Attribution]

    private static let buildCommit = loadBuildCommit()
    private static let ossCredits = loadOSSCredits()
    private static let osmCopyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!

    private static func loadBuildCommit() -> String {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let commit = plist["GitCommit"]
        else { return "unknown" }
        return commit
    }

    private static func loadOSSCredits() -> [OSSCreditEntry] {
        guard let url = Bundle.main.url(forResource: "OSSCredits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(OSSCreditsManifest.self, from: data)
        else { return [] }
        return manifest.credits
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Build")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "Build \(Self.buildCommit)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Map attribution")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Map data © OpenStreetMap contributors.")
                    Link(destination: Self.osmCopyrightURL) {
                        Text("OpenStreetMap copyright")
                    }
                    .accessibilityValue(Self.osmCopyrightURL.absoluteString)
                    .accessibilityIdentifier("about.openstreetmap-copyright")
                }

                if !attribution.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Manifest attribution")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(attribution.enumerated()), id: \.offset) { _, item in
                                CreditEntryView(
                                    title: item.source,
                                    subtitle: item.license,
                                    text: item.text
                                )
                            }
                        }
                    }
                }

                if !Self.ossCredits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Open source acknowledgements")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(Self.ossCredits) { credit in
                                OpenSourceCreditView(credit: credit)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("About")
    }
}

private struct CreditEntryView: View {
    let title: String
    let subtitle: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.headline)
            Text(verbatim: subtitle)
                .font(.subheadline)
            Text(verbatim: text)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("credits.manifest.\(title)")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OpenSourceCreditView: View {
    let credit: OSSCreditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: credit.name)
                    .font(.headline)
                Text(verbatim: credit.acknowledgement)
                    .font(.subheadline)
                Text(verbatim: "\(credit.category) | \(credit.versionOrPin)")
                    .font(.caption)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("credits.oss.\(credit.id)")
            if let licenseURL = credit.licenseURL {
                Link(destination: licenseURL) {
                    Text("License")
                        .font(.caption)
                }
                .accessibilityLabel("License for \(credit.name)")
                .accessibilityValue(licenseURL.absoluteString)
                .accessibilityIdentifier("credits.oss.\(credit.id).license")
            }
            Text(verbatim: credit.noticeText)
                .font(.footnote)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OSSCreditsManifest: Decodable {
    let credits: [OSSCreditEntry]
}

private struct OSSCreditEntry: Decodable, Identifiable {
    let acknowledgement: String
    let category: String
    let licenseURLString: String
    let name: String
    let noticeText: String
    let versionOrPin: String

    var id: String { "\(name)|\(versionOrPin)" }

    var licenseURL: URL? {
        guard let url = URL(string: licenseURLString), url.scheme == "https" else { return nil }
        return url
    }

    private enum CodingKeys: String, CodingKey {
        case acknowledgement
        case category
        case licenseURLString = "license_url"
        case name
        case noticeText = "notice_text"
        case versionOrPin = "version_or_pin"
    }
}

private struct LocationSettingsButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "gearshape.fill")
        configuration.title = "Settings"
        configuration.imagePadding = 4
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = .label
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            let baseFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
            outgoing.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont)
            return outgoing
        }
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityLabel = "Settings"
        button.accessibilityHint = "Opens location settings"
        button.accessibilityIdentifier = "map.location-settings"
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tap() {
            action()
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? bounds.width

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> CGSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                width = max(width, rowWidth)
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }

        width = max(width, rowWidth)
        height += rowHeight
        return CGSize(width: width, height: height)
    }
}

private struct LayersSheet: View {
    @Binding var visibility: MapLayerVisibility
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(
                        "Include hidden places",
                        isOn: Binding(
                            get: { visibility.showHiddenPlaces },
                            set: { visible in
                                var next = visibility
                                next.showHiddenPlaces = visible
                                visibility = next
                            }
                        )
                    )
                        .accessibilityIdentifier("map.layers.show-hidden")
                }

                Section("Categories") {
                    ForEach(visibility.categories) { category in
                        Toggle(
                            isOn: Binding(
                                get: { visibility.isCategoryVisible(category.id) },
                                set: { visible in
                                    var next = visibility
                                    next.setCategory(category.id, visible: visible)
                                    visibility = next
                                }
                            )
                        ) {
                            Label {
                                Text(verbatim: category.title)
                            } icon: {
                                Image(systemName: PinLayers.categorySymbolNames[category.iconName] ?? "mappin")
                            }
                        }
                        .accessibilityIdentifier("map.layers.category.\(category.id)")
                    }
                    Button("Show all categories") {
                        var next = visibility
                        next.showAllCategories()
                        visibility = next
                    }
                    .accessibilityIdentifier("map.layers.show-all-categories")
                }
            }
            .navigationTitle("Layers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("map.layers.done")
                }
            }
        }
    }
}

private struct PlaceCardSheet: View {
    let placeID: String
    let model: MapScreenModel?
    let onHide: (String, String) -> Void
    let showHiddenMode: Bool

    @State private var sheetInstanceID = UUID().uuidString
    @State private var card: PlaceCardModel?
    @State private var isLoading = true
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let card {
                    HStack {
                        Spacer()
                        Button("Close") {
                            dismiss()
                        }
                        .accessibilityIdentifier("place-card.close")
                    }
                    Text(verbatim: card.name)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("place-card.title")
                    typeRow(card)
                    if let blurb = card.blurb {
                        Text(verbatim: blurb)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("place-card.description")
                    }
                    photoSlot(card)
                    listChips(card.listNames)
                    if let actionError {
                        Text(verbatim: actionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("place-card.action-error")
                    }
                    actionButtons(card)
                    attributionText(card)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(verbatim: "Place unavailable")
                        .font(.headline)
                    Text(verbatim: placeID)
                        .font(.caption2)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .accessibilityIdentifier("place-card.instance.\(sheetInstanceID)")
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium])
        .presentationBackgroundInteraction(.enabled(upThrough: dynamicTypeSize.isAccessibilitySize ? .large : .medium))
        .task(id: placeID) {
            await loadCard()
        }
    }

    @ViewBuilder
    private func typeRow(_ card: PlaceCardModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: categorySymbolName(for: card.category))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: categoryLabel(card.category))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("place-card.type.label")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func photoSlot(_ card: PlaceCardModel) -> some View {
        if let photo = card.photo {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
                Image(systemName: "photo")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photo.accessibilityLabel)
            .accessibilityIdentifier("place-card.photo")
        }
    }

    @ViewBuilder
    private func listChips(_ names: [String]) -> some View {
        if !names.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    Text(verbatim: name)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .accessibilityIdentifier("place-card.list-chips")
        }
    }

    @ViewBuilder
    private func attributionText(_ card: PlaceCardModel) -> some View {
        let parts = attributionParts(card)
        if !parts.isEmpty {
            Text(verbatim: parts.joined(separator: " / "))
                .font(.caption2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("place-card.attribution")
        }
    }

    @ViewBuilder
    private func actionButtons(_ card: PlaceCardModel) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                saveButton(card)
                seenButton(card)
                if card.pinState.visit != .none {
                    loveButton(card)
                }
                if card.pinState.hidden {
                    if showHiddenMode {
                        unhideButton()
                    }
                } else {
                    hideButton(card)
                }
            }
        } else {
            HStack(spacing: 10) {
                saveButton(card)
                seenButton(card)
                if card.pinState.visit != .none {
                    loveButton(card)
                }
                if card.pinState.hidden {
                    if showHiddenMode {
                        unhideButton()
                    }
                } else {
                    hideButton(card)
                }
            }
        }
    }

    private func saveButton(_ card: PlaceCardModel) -> some View {
        Button(card.pinState.saved ? "Saved" : "Save") {
            Task { await setSaved(!card.pinState.saved) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("place-card.save")
        .accessibilityValue(card.pinState.saved ? "Saved" : "Not saved")
    }

    private func seenButton(_ card: PlaceCardModel) -> some View {
        Button(card.pinState.visit == .none ? "Seen" : "Unsee") {
            Task { await setVisited(card.pinState.visit == .none) }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("place-card.visited")
        .accessibilityValue(card.pinState.visit == .none ? "Not seen" : "Seen")
    }

    private func loveButton(_ card: PlaceCardModel) -> some View {
        Button(card.pinState.visit == .loved ? "Loved" : "Love") {
            Task { await setLoved(card.pinState.visit != .loved) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("place-card.loved")
        .accessibilityValue(card.pinState.visit == .loved ? "Loved" : "Not loved")
    }

    private func hideButton(_ card: PlaceCardModel) -> some View {
        Button("Hide", role: .destructive) {
            Task { await setHidden(card) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("place-card.hide")
        .accessibilityValue("Not hidden")
    }

    private func unhideButton() -> some View {
        Button("Unhide") {
            Task { await setHidden(false) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("place-card.unhide")
        .accessibilityValue("Hidden")
    }

    private func loadCard() async {
        await MainActor.run {
            card = nil
            actionError = nil
            isLoading = true
        }
        let nextCard = await model?.cardModel(for: placeID)
        await MainActor.run {
            card = nextCard
            isLoading = false
        }
    }

    private func refreshCard() async {
        let nextCard = await model?.cardModel(for: placeID)
        await MainActor.run {
            card = nextCard
        }
    }

    private func setSaved(_ saved: Bool) async {
        await performAction {
            try await model?.setSaved(placeID: placeID, saved: saved)
        }
    }

    private func setVisited(_ visited: Bool) async {
        await performAction {
            try await model?.setVisited(placeID: placeID, visited: visited)
        }
    }

    private func setLoved(_ loved: Bool) async {
        await performAction {
            try await model?.setLoved(placeID: placeID, loved: loved)
        }
    }

    private func setHidden(_ card: PlaceCardModel) async {
        await MainActor.run {
            actionError = nil
        }
        do {
            try await model?.setHidden(placeID: placeID, hidden: true)
            await MainActor.run {
                self.card = nil
                dismiss()
                onHide(placeID, card.name)
            }
        } catch {
            await MainActor.run {
                actionError = "Could not save that change."
            }
        }
    }

    private func setHidden(_ hidden: Bool) async {
        await performAction {
            try await model?.setHidden(placeID: placeID, hidden: hidden)
        }
    }

    private func performAction(_ action: () async throws -> Void) async {
        do {
            try await action()
            await MainActor.run { actionError = nil }
            await refreshCard()
        } catch {
            await MainActor.run {
                actionError = "Could not save that change."
            }
        }
    }

    private func categoryLabel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func categorySymbolName(for raw: String) -> String {
        let iconName = PinLayers.categoryIconNames[raw.lowercased()] ?? PinLayers.fallbackCategoryIconName
        return PinLayers.categorySymbolNames[iconName] ?? "mappin"
    }

    private func attributionParts(_ card: PlaceCardModel) -> [String] {
        var parts: [String] = []
        if let photo = card.photo {
            parts.append(photo.attribution)
        }
        if !card.sourceNames.isEmpty {
            parts.append(card.sourceNames.joined(separator: " / "))
        }
        return parts
    }

}

private enum MapScreenActionError: Error {
    case placeUnavailable
}

@MainActor
private final class MapScreenModel {
    private let database: AppDatabase
    private let tileCache: TileCache?
    private let offlineStore: OfflineRegionStore?
    private let forceTileNetworkOffline: Bool
    private let fixturePlaces: [String: PlaceRef]
    private let coreLoop: CoreLoopController
    private var tileClients: [MapRegion: TileClient] = [:]
    private var selectedRegion: MapRegion = .malaysia
    private var hiddenTracker: HiddenMembershipTracker
    private var showHiddenPlaces = false

    var changes: AsyncStream<Set<String>> { coreLoop.changes }

    init(
        database: AppDatabase,
        fixturePlaces: [PlaceRef] = [],
        forceTileNetworkOffline: Bool = false
    ) throws {
        self.database = database
        self.forceTileNetworkOffline = forceTileNetworkOffline
        self.fixturePlaces = Dictionary(uniqueKeysWithValues: fixturePlaces.map { ($0.placeID, $0) })
        coreLoop = CoreLoopController(database: database)
        hiddenTracker = HiddenMembershipTracker(hiddenPlaceIDs: try database.hiddenPlaceIDs())
        if fixturePlaces.isEmpty {
            let cacheRoot = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("MakingTracks/Tiles", isDirectory: true)
            tileCache = try TileCache(directory: cacheRoot)
            offlineStore = try? OfflineRegionStore.documentsStore()
        } else {
            tileCache = nil
            offlineStore = nil
        }
    }

#if DEBUG
    func installDebugOfflineRegion(_ region: String) async -> String {
        guard fixturePlaces.isEmpty,
              let offlineStore,
              Self.isValidRegion(region)
        else { return "Offline install unavailable" }
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let downloader = OfflineRegionDownloader(
                region: region,
                fetcher: HTTPTileFetcher(),
                store: offlineStore,
                availableBytes: { StorageHeadroom.availableBytes(at: documents) }
            )
            let result = try await downloader.downloadCurrentRegion()
            return "Installed \(result.publish.publishVersion)"
        } catch {
            return "Install failed: \(String(describing: error))"
        }
    }

    private static func isValidRegion(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9_]{0,63}$", options: .regularExpression) == value.startIndex..<value.endIndex
    }
#endif

    func refreshManifest() async {
        guard let client = tileClient(for: selectedRegion) else { return }
        try? await client.refreshPin()
    }

    func features(in bbox: BBox, zoom: Int) async -> [(MapPlace, PinState)] {
        if !fixturePlaces.isEmpty {
            let sortedFixtures = fixturePlaces.values.sorted { $0.placeID < $1.placeID }
            let states = await states(for: Set(sortedFixtures.map(\.placeID)))
            let next = sortedFixtures.map { fixturePlace in
                let place = MapPlace(
                    id: fixturePlace.placeID,
                    lat: fixturePlace.lat,
                    lon: fixturePlace.lon,
                    tier: fixturePlace.tier,
                    category: fixturePlace.category
                )
                return (place, states[fixturePlace.placeID] ?? PinState(saved: false, visit: .none))
            }
            return PinFeatureFilter.discoveryFeatures(next, showHidden: showHiddenPlaces)
        }
        guard let client = await selectClient(for: bbox) else { return [] }
        let places = await client.places(inViewport: bbox, zoom: zoom)
        let ids = places.map(\.id)
        let states = await states(for: Set(ids))
        let next = places.map { ($0, states[$0.id] ?? PinState(saved: false, visit: .none)) }
        return PinFeatureFilter.discoveryFeatures(next, showHidden: showHiddenPlaces)
    }

    func setShowHidden(_ showHidden: Bool) {
        showHiddenPlaces = showHidden
    }

    func states(for ids: Set<String>) async -> [String: PinState] {
        let db = database
        var resolved = await Task.detached {
            (try? db.viewportState(Array(ids))) ?? [:]
        }.value
        for id in ids {
            var state = resolved[id] ?? PinState(saved: false, visit: .none)
            state.hidden = hiddenTracker.hiddenIDs.contains(id)
            resolved[id] = state
        }
        return resolved
    }

    var hiddenIDs: Set<String> {
        hiddenTracker.hiddenIDs
    }

    func consumeHiddenMembershipChange(overlapping ids: Set<String>) -> Bool {
        hiddenTracker.consumeHiddenMembershipChange(overlapping: ids)
    }

    func visitCount(placeID: String) async -> Int {
        let db = database
        return await Task.detached {
            (try? db.visitCount(placeID: placeID)) ?? 0
        }.value
    }

    func cardModel(for placeID: String) async -> PlaceCardModel? {
        let pinState = await states(for: [placeID])[placeID] ?? PinState(saved: false, visit: .none)
        guard let source = await cardSource(for: placeID) else { return nil }

        let base: PlaceCardModel?
        switch source {
        case let .tile(placeRef):
            base = PlaceCardModel.from(placeRef: placeRef, pinState: pinState)
        case let .snapshot(_, snapshot):
            base = PlaceCardModel.from(snapshot: snapshot, pinState: pinState)
        case .unavailable:
            return nil
        }
        guard let base else { return nil }
        let lists = await userListNames(containing: placeID)
        return base.enriching(photo: fixturePhoto(for: placeID, name: base.name), listNames: lists)
    }

    private func userListNames(containing placeID: String) async -> [String] {
        let db = database
        return await Task.detached {
            (try? db.userListNames(containing: placeID)) ?? []
        }.value
    }

    private func fixturePhoto(for placeID: String, name: String) -> PlaceCardPhoto? {
        guard fixturePlaces[placeID] != nil else { return nil }
        return PlaceCardPhoto(
            accessibilityLabel: "Photo of \(name)",
            attribution: "Fixture photo"
        )
    }

    func setSaved(placeID: String, saved: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        try coreLoop.setSaved(placeRef, saved)
    }

    func setVisited(placeID: String, visited: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        try coreLoop.setVisited(placeRef, visited)
    }

    func setLoved(placeID: String, loved: Bool) async throws {
        try coreLoop.setLoved(placeID: placeID, loved)
    }

    func setHidden(placeID: String, hidden: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        let rollback = hiddenTracker.beginSetHidden(placeID: placeID, hidden: hidden)
        do {
            try coreLoop.setHidden(placeRef, hidden)
        } catch {
            hiddenTracker.rollback(rollback)
            throw error
        }
    }

    private func cardSource(for placeID: String) async -> CardSource? {
        if let fixturePlace = fixturePlaces[placeID] {
            if let snapshot = try? database.snapshot(for: placeID),
               let placeRef = try? PlaceRef(
                placeID: snapshot.placeID,
                name: snapshot.name,
                lat: snapshot.lat,
                lon: snapshot.lon,
                category: snapshot.category,
                tier: snapshot.tier,
                schemaVersion: snapshot.snapshotSchemaVersion,
                fetchedAt: snapshot.fetchedAt,
                rawJSON: snapshot.snapshotJSON
               ) {
                return .snapshot(placeRef, snapshot)
            }
            return .tile(fixturePlace)
        }
        guard let tileClient = tileClient(for: selectedRegion) else { return nil }
        return await PlaceResolver(tile: tileClient, snapshots: database).source(for: placeID)
    }

    private func actionPlaceRef(for placeID: String) async -> PlaceRef? {
        guard let source = await cardSource(for: placeID) else { return nil }
        switch source {
        case let .tile(placeRef), let .snapshot(placeRef, _):
            return placeRef
        case .unavailable:
            return nil
        }
    }

    var pmtilesURL: String? {
        get async {
            guard let client = tileClient(for: selectedRegion),
                  let url = await client.basemapURL,
                  await client.basemapIntegrity != nil
            else { return nil }
            return "pmtiles://\(url.absoluteString)"
        }
    }

    var attribution: [Attribution] {
        get async {
            guard let client = tileClient(for: selectedRegion) else {
                return [Attribution(source: "osm", license: "ODbL-1.0", text: "OSM credit")]
            }
            return await client.attribution
        }
    }

    var loadState: TileLoadState {
        get async {
            guard let client = tileClient(for: selectedRegion) else { return .ok }
            return await client.loadState
        }
    }

    private func selectClient(for bbox: BBox) async -> TileClient? {
        let nextRegion = MapRegion.select(for: bbox, current: selectedRegion)
        let changed = nextRegion != selectedRegion
        selectedRegion = nextRegion
        guard let client = tileClient(for: nextRegion) else { return nil }
        if changed {
            try? await client.refreshPin()
        }
        return client
    }

    private func tileClient(for region: MapRegion) -> TileClient? {
        guard let tileCache else { return nil }
        if let cached = tileClients[region] {
            return cached
        }
#if DEBUG
        let fetcher: TileFetching = forceTileNetworkOffline ? OfflineProofFetcher() : HTTPTileFetcher()
#else
        let fetcher: TileFetching = HTTPTileFetcher()
#endif
        let client = TileClient(
            region: region.rawValue,
            fetcher: fetcher,
            cache: tileCache,
            offlineStore: offlineStore
        )
        tileClients[region] = client
        return client
    }
}

#if DEBUG
private struct OfflineProofFetcher: TileFetching {
    func fetch(_ url: URL) async throws -> Data {
        throw URLError(.notConnectedToInternet)
    }
}
#endif
