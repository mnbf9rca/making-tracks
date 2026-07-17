import CoreLocation
import SwiftUI
import UIKit
import ImageIO
import MakingTracksCore
import MakingTracksData
import MakingTracksTiles

struct MapScreen: View {
    let database: AppDatabase
    let startupViewport: ViewportSeed
    var isFixtureMap = false
    var debugInstallOfflineRegion: String?
    var debugForceTileNetworkOffline = false

    @State private var model: MapScreenModel?
    @StateObject private var locationPermission: LocationPermission
    @State private var worldPMTilesURL: String? = WorldBasemap.pmtilesURL()
    @State private var features: [(MapPlace, PinState)] = []
    @State private var regionPMTilesURL: String?
    @State private var attribution: [Attribution] = []
    @State private var debugOfflineStatus: String?
    @State private var cardPresentation = PlaceCardPresentation()
    @State private var showCredits = false
    @State private var loadState: TileLoadState = .unavailable
    @State private var viewportRequestID = 0
    @State private var stateEpoch = 0
    @State private var fixtureVisitCount = 0
    @State private var userLocationFocusRequestID = 0
    private static let primaryFixturePlaceID = fixturePlaces[0].placeID

    init(
        database: AppDatabase,
        startupViewport: ViewportSeed,
        isFixtureMap: Bool = false,
        debugInstallOfflineRegion: String? = nil,
        debugForceTileNetworkOffline: Bool = false,
        locationManager: LocationManaging = CLLocationManager()
    ) {
        self.database = database
        self.startupViewport = startupViewport
        self.isFixtureMap = isFixtureMap
        self.debugInstallOfflineRegion = debugInstallOfflineRegion
        self.debugForceTileNetworkOffline = debugForceTileNetworkOffline
        _locationPermission = StateObject(wrappedValue: LocationPermission(manager: locationManager))
    }

    var body: some View {
        ZStack {
            MLNMapViewRepresentable(
                worldPMTilesURL: worldPMTilesURL,
                regionPMTilesURL: regionPMTilesURL,
                startupViewport: startupViewport,
                features: features,
                showsUserLocation: locationPermission.showsUserLocation,
                userLocationCoordinate: locationPermission.currentCoordinate,
                userLocationFocusRequestID: userLocationFocusRequestID,
                onCameraIdle: { bbox, zoom in
                    Task { @MainActor in
                        let requestID = nextViewportRequestID()
                        let stateEpoch = currentStateEpoch()
                        await refreshViewport(
                            bbox: bbox,
                            zoom: zoom,
                            requestID: requestID,
                            stateEpoch: stateEpoch
                        )
                    }
                },
                onTapPlace: { placeID in
                    cardPresentation.show(placeID: placeID)
                },
                onTapEmpty: {
                    cardPresentation.dismiss()
                }
            )
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                statusChrome
                    .padding(.top, 72)
                    .padding(.trailing, 16)
            }
            .overlay(alignment: .bottomLeading) {
                attributionButton
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .bottomTrailing) {
                locationChrome
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
        .task {
            await start()
            if let model {
                await observeChanges(from: model)
            }
        }
        .sheet(isPresented: $showCredits) {
            CreditsView(attribution: attribution)
        }
        .sheet(item: cardPresentationItemBinding) { presentation in
            PlaceCardSheet(
                placeID: presentation.placeID,
                model: model
            )
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
            }

#if DEBUG
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

    private var attributionButton: some View {
        Button {
            showCredits = true
        } label: {
            Text(verbatim: "© OpenStreetMap")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel("OpenStreetMap attribution")
        .accessibilityHint("Opens credits")
        .accessibilityIdentifier("map.openstreetmap-attribution")
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var locateMeButton: some View {
        Button {
            handleLocateMeTap()
        } label: {
            Image(systemName: "location.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Locate me")
        .accessibilityHint("Centers the map on your location")
        .accessibilityIdentifier("map.locate-me")
    }

    private func start() async {
        if model == nil {
            model = try? MapScreenModel(
                database: database,
                region: "malaysia",
                fixturePlaces: isFixtureMap ? Self.fixturePlaces : [],
                forceTileNetworkOffline: debugForceTileNetworkOffline
            )
        }
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
        switch locationPermission.authorizationStatus {
        case .denied, .restricted:
            openLocationSettings()
        case .notDetermined, .authorizedAlways, .authorizedWhenInUse:
            locationPermission.requestCurrentLocation()
            userLocationFocusRequestID += 1
        @unknown default:
            locationPermission.requestCurrentLocation()
            userLocationFocusRequestID += 1
        }
    }

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
        await MainActor.run {
            guard requestID == viewportRequestID else { return }
            if capturedStateEpoch == stateEpoch {
                features = next
            }
            regionPMTilesURL = nextRegionPMTilesURL
            attribution = nextAttribution
            loadState = nextLoadState
        }
    }

    private func observeChanges(from model: MapScreenModel) async {
        for await ids in model.changes {
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

    private static let fixturePlaces = [
        try! PlaceRef(
            placeID: "mt1_00000000000000000000000000",
            name: "Ghost Sign",
            lat: 3.14,
            lon: 101.69,
            category: "history",
            tier: 3,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: """
            {"category":"history","lat":3.14,"lon":101.69,"name":"Ghost Sign","place_id":"mt1_00000000000000000000000000","score":0.5,"source_refs":["osm:node/1"],"tier":3}
            """
        ),
        try! PlaceRef(
            placeID: "mt1_00000000000000000000000001",
            name: "Art Deco Cinema",
            lat: 3.16,
            lon: 101.702,
            category: "architecture",
            tier: 3,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: """
            {"category":"architecture","lat":3.16,"lon":101.702,"name":"Art Deco Cinema","place_id":"mt1_00000000000000000000000001","score":0.5,"source_refs":["osm:node/2"],"tier":3}
            """
        ),
    ]
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
            outgoing.font = .systemFont(ofSize: 11, weight: .semibold)
            return outgoing
        }
        button.configuration = configuration
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
