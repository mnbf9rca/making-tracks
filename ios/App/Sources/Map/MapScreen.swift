import SwiftUI
import UIKit
import ImageIO
import MakingTracksCore
import MakingTracksData
import MakingTracksTiles

struct MapScreen: View {
    let database: AppDatabase
    var isFixtureMap = false

    @State private var model: MapScreenModel?
    @State private var features: [(MapPlace, PinState)] = []
    @State private var pmtilesURL: String?
    @State private var attribution: [Attribution] = []
    @State private var cardPresentation = PlaceCardPresentation()
    @State private var showCredits = false
    @State private var loadState: TileLoadState = .unavailable
    @State private var viewportRequestID = 0
    @State private var stateEpoch = 0
    @State private var fixtureVisitCount = 0
    private static let primaryFixturePlaceID = fixturePlaces[0].placeID

    var body: some View {
        ZStack {
            MLNMapViewRepresentable(
                pmtilesURL: pmtilesURL,
                features: features,
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
                mapChrome
                    .padding(.top, 72)
                    .padding(.trailing, 16)
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

            creditsButton
        }
    }

    private var creditsButton: some View {
        Button {
            showCredits = true
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Credits")
    }

    private func start() async {
        if model == nil {
            model = try? MapScreenModel(
                database: database,
                region: "malaysia",
                fixturePlaces: isFixtureMap ? Self.fixturePlaces : []
            )
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
            requestID: nextViewportRequestID(),
            stateEpoch: currentStateEpoch()
        )
        await refreshFixtureVisitCount()
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
        let nextPMTilesURL = await model.pmtilesURL
        let nextAttribution = await model.attribution
        let nextLoadState = await model.loadState
        await MainActor.run {
            guard requestID == viewportRequestID else { return }
            if capturedStateEpoch == stateEpoch {
                features = next
            }
            pmtilesURL = nextPMTilesURL
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

private struct CreditsView: View {
    let attribution: [Attribution]
    @Environment(\.dismiss) private var dismiss

    private static let buildCommit = loadBuildCommit()

    private static func loadBuildCommit() -> String {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let commit = plist["GitCommit"]
        else { return "unknown" }
        return commit
    }

    var body: some View {
        NavigationStack {
            List {
                Text(verbatim: "Build \(Self.buildCommit)")
                    .font(.caption)
                    .fontDesign(.monospaced)

                ForEach(Array(attribution.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: item.source)
                            .font(.headline)
                        Text(verbatim: item.license)
                            .font(.subheadline)
                        Text(verbatim: item.text)
                            .font(.body)
                    }
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

    @State private var sheetInstanceID = UUID().uuidString
    @State private var card: PlaceCardModel?
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss

    private static let maxDecodedImagePixels = 16_000_000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let card {
                    HStack {
                        Spacer()
                        Button("Close") {
                            dismiss()
                        }
                        .accessibilityIdentifier("place-card.close")
                    }
                    Text(verbatim: card.name)
                        .font(.headline)
                    Text(verbatim: card.category)
                        .font(.subheadline)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                    }
                    if let blurb = card.blurb {
                        Text(verbatim: blurb)
                            .font(.body)
                    }
                    if let actionError {
                        Text(verbatim: actionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("place-card.action-error")
                    }
                    actionButtons(card)
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
        .accessibilityIdentifier("place-card.instance.\(sheetInstanceID)")
        .presentationDetents([.medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .task(id: placeID) {
            await loadCard()
        }
    }

    @ViewBuilder
    private func actionButtons(_ card: PlaceCardModel) -> some View {
        HStack(spacing: 10) {
            Button(card.pinState.saved ? "Saved" : "Save") {
                Task { await setSaved(!card.pinState.saved) }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("place-card.save")

            Button(card.pinState.visit == .none ? "Visited" : "Unvisit") {
                Task { await setVisited(card.pinState.visit == .none) }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("place-card.visited")

            if card.pinState.visit != .none {
                Button(card.pinState.visit == .loved ? "Loved" : "Love") {
                    Task { await setLoved(card.pinState.visit != .loved) }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("place-card.loved")
            }
        }
    }

    private func loadCard() async {
        await MainActor.run {
            card = nil
            image = nil
            actionError = nil
            isLoading = true
        }
        let nextCard = await model?.cardModel(for: placeID)
        await MainActor.run {
            card = nextCard
            image = nil
            isLoading = false
        }
        guard let imageURL = nextCard?.imageURL,
              let data = await ImageLoader().fetch(imageURL),
              Self.isSafeDecodedImage(data),
              let nextImage = UIImage(data: data)
        else { return }
        await MainActor.run {
            image = nextImage
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

    private static func isSafeDecodedImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0
        else { return false }
        return width <= maxDecodedImagePixels / height
    }
}

private final class MapScreenModel: Sendable {
    private let database: AppDatabase
    private let tileClient: TileClient?
    private let fixturePlaces: [String: PlaceRef]
    private let coreLoop: CoreLoopController

    var changes: AsyncStream<Set<String>> { coreLoop.changes }

    init(database: AppDatabase, region: String, fixturePlaces: [PlaceRef] = []) throws {
        self.database = database
        self.fixturePlaces = Dictionary(uniqueKeysWithValues: fixturePlaces.map { ($0.placeID, $0) })
        coreLoop = CoreLoopController(database: database)
        if fixturePlaces.isEmpty {
            let cacheRoot = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("MakingTracks/Tiles", isDirectory: true)
            tileClient = try TileClient(region: region, fetcher: HTTPTileFetcher(), cache: TileCache(directory: cacheRoot))
        } else {
            tileClient = nil
        }
    }

    func refreshManifest() async {
        try? await tileClient?.refreshPin()
    }

    func features(in bbox: BBox, zoom: Int) async -> [(MapPlace, PinState)] {
        if !fixturePlaces.isEmpty {
            let sortedFixtures = fixturePlaces.values.sorted { $0.placeID < $1.placeID }
            let states = await states(for: Set(sortedFixtures.map(\.placeID)))
            return sortedFixtures.map { fixturePlace in
                let place = MapPlace(id: fixturePlace.placeID, lat: fixturePlace.lat, lon: fixturePlace.lon, tier: fixturePlace.tier)
                return (place, states[fixturePlace.placeID] ?? PinState(saved: false, visit: .none))
            }
        }
        guard let tileClient else { return [] }
        let places = await tileClient.places(inViewport: bbox, zoom: zoom)
        let ids = places.map(\.id)
        let states = await states(for: Set(ids))
        return places.map { ($0, states[$0.id] ?? PinState(saved: false, visit: .none)) }
    }

    func states(for ids: Set<String>) async -> [String: PinState] {
        let db = database
        return await Task.detached {
            (try? db.viewportState(Array(ids))) ?? [:]
        }.value
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

        switch source {
        case let .tile(placeRef):
            return PlaceCardModel.from(placeRef: placeRef, pinState: pinState)
        case let .snapshot(_, snapshot):
            return PlaceCardModel.from(snapshot: snapshot, pinState: pinState)
        case .unavailable:
            return nil
        }
    }

    func setSaved(placeID: String, saved: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { return }
        try coreLoop.setSaved(placeRef, saved)
    }

    func setVisited(placeID: String, visited: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { return }
        try coreLoop.setVisited(placeRef, visited)
    }

    func setLoved(placeID: String, loved: Bool) async throws {
        try coreLoop.setLoved(placeID: placeID, loved)
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
        guard let tileClient else { return nil }
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
            guard let tileClient,
                  let url = await tileClient.basemapURL,
                  await tileClient.basemapIntegrity != nil
            else { return nil }
            return "pmtiles://\(url.absoluteString)"
        }
    }

    var attribution: [Attribution] {
        get async {
            guard let tileClient else {
                return [Attribution(source: "osm", license: "ODbL-1.0", text: "OSM credit")]
            }
            return await tileClient.attribution
        }
    }

    var loadState: TileLoadState {
        get async { await tileClient?.loadState ?? .ok }
    }
}
