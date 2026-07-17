import SwiftUI
import MakingTracksData
import MakingTracksTiles

struct MapScreen: View {
    let database: AppDatabase
    @State private var model: MapScreenModel?
    @State private var features: [(MapPlace, PinState)] = []
    @State private var pmtilesURL: String?
    @State private var attribution: [Attribution] = []
    @State private var selectedPlaceID: String?
    @State private var showCredits = false
    @State private var loadState: TileLoadState = .unavailable
    @State private var viewportRequestID = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MLNMapViewRepresentable(
                pmtilesURL: pmtilesURL,
                features: features,
                onCameraIdle: { bbox, zoom in
                    let requestID = nextViewportRequestID()
                    Task { await refreshViewport(bbox: bbox, zoom: zoom, requestID: requestID) }
                },
                onTapPlace: { placeID in
                    selectedPlaceID = placeID
                }
            )
            .ignoresSafeArea()

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    showCredits = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.title3)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Credits")

                if loadState != .ok {
                    Text(verbatim: loadState.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding()
        }
        .task { await start() }
        .sheet(isPresented: $showCredits) {
            CreditsView(attribution: attribution)
        }
        .sheet(item: selectedBinding) { place in
            PlaceholderPlaceCard(placeID: place.id)
        }
    }

    private var selectedBinding: Binding<SelectedPlace?> {
        Binding(
            get: { selectedPlaceID.map(SelectedPlace.init(id:)) },
            set: { selectedPlaceID = $0?.id }
        )
    }

    private func start() async {
        if model == nil {
            model = try? MapScreenModel(database: database, region: "malaysia")
        }
        await model?.refreshManifest()
        let nextPMTilesURL = await model?.pmtilesURL
        let nextAttribution = await model?.attribution ?? []
        let nextLoadState = await model?.loadState ?? .unavailable
        await MainActor.run {
            pmtilesURL = nextPMTilesURL
            attribution = nextAttribution
            loadState = nextLoadState
        }
        await refreshViewport(
            bbox: BBox(minLon: 101.64, minLat: 3.09, maxLon: 101.74, maxLat: 3.19),
            zoom: 12,
            requestID: nextViewportRequestID()
        )
    }

    @MainActor
    private func nextViewportRequestID() -> Int {
        viewportRequestID += 1
        return viewportRequestID
    }

    private func refreshViewport(bbox: BBox, zoom: Int, requestID: Int) async {
        guard let model else { return }
        let next = await model.features(in: bbox, zoom: zoom)
        let nextPMTilesURL = await model.pmtilesURL
        let nextAttribution = await model.attribution
        let nextLoadState = await model.loadState
        await MainActor.run {
            guard requestID == viewportRequestID else { return }
            features = next
            pmtilesURL = nextPMTilesURL
            attribution = nextAttribution
            loadState = nextLoadState
        }
    }
}

private struct SelectedPlace: Identifiable {
    let id: String
}

private struct CreditsView: View {
    let attribution: [Attribution]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(attribution, id: \.source) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: item.source)
                        .font(.headline)
                    Text(verbatim: item.license)
                        .font(.subheadline)
                    Text(verbatim: item.text)
                        .font(.body)
                }
            }
            .navigationTitle("Credits")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct PlaceholderPlaceCard: View {
    let placeID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Place")
                .font(.headline)
            Text(verbatim: placeID)
                .font(.footnote)
                .textSelection(.enabled)
        }
        .padding()
        .presentationDetents([.medium])
    }
}

private final class MapScreenModel: Sendable {
    private let database: AppDatabase
    private let tileClient: TileClient

    init(database: AppDatabase, region: String) throws {
        self.database = database
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MakingTracks/Tiles", isDirectory: true)
        tileClient = try TileClient(region: region, fetcher: HTTPTileFetcher(), cache: TileCache(directory: cacheRoot))
    }

    func refreshManifest() async {
        try? await tileClient.refreshPin()
    }

    func features(in bbox: BBox, zoom: Int) async -> [(MapPlace, PinState)] {
        let places = await tileClient.places(inViewport: bbox, zoom: zoom)
        let ids = places.map(\.id)
        let db = database
        let states = await Task.detached {
            (try? db.viewportState(ids)) ?? [:]
        }.value
        return places.map { ($0, states[$0.id] ?? PinState(saved: false, visit: .none)) }
    }

    var pmtilesURL: String? {
        get async {
            guard let url = await tileClient.basemapURL,
                  await tileClient.basemapIntegrity != nil
            else { return nil }
            return "pmtiles://\(url.absoluteString)"
        }
    }

    var attribution: [Attribution] {
        get async { await tileClient.attribution }
    }

    var loadState: TileLoadState {
        get async { await tileClient.loadState }
    }
}
