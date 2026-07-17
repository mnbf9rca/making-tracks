import SwiftUI
import MakingTracksCore
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
            PlaceCardSheet(placeID: place.id, model: model)
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

private struct PlaceCardSheet: View {
    let placeID: String
    let model: MapScreenModel?
    @State private var card: PlaceCardModel?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let card {
                    Text(verbatim: card.name)
                        .font(.headline)
                    Text(verbatim: card.category)
                        .font(.subheadline)
                    if let blurb = card.blurb {
                        Text(verbatim: blurb)
                            .font(.body)
                    }
                    if !card.altNames.isEmpty {
                        Text(verbatim: card.altNames.joined(separator: ", "))
                            .font(.footnote)
                    }
                    if !card.sourceNames.isEmpty {
                        Text(verbatim: card.sourceNames.joined(separator: " / "))
                            .font(.caption)
                    }
                    Text(verbatim: card.placeID)
                        .font(.caption2)
                        .textSelection(.enabled)
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
        .presentationDetents([.medium])
        .task(id: placeID) {
            isLoading = true
            card = await model?.cardModel(for: placeID)
            isLoading = false
        }
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

    func cardModel(for placeID: String) async -> PlaceCardModel? {
        let resolver = PlaceResolver(tile: tileClient, snapshots: database)
        let source = await resolver.source(for: placeID)
        let db = database
        let pinState = await Task.detached {
            (try? db.viewportState([placeID])[placeID]) ?? PinState(saved: false, visit: .none)
        }.value

        switch source {
        case let .tile(placeRef):
            return PlaceCardModel.from(placeRef: placeRef, pinState: pinState)
        case let .snapshot(_, snapshot):
            return PlaceCardModel.from(snapshot: snapshot, pinState: pinState)
        case .unavailable:
            return nil
        }
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
