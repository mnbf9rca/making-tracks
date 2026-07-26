import DesignSystem
import MakingTracksData
import SwiftUI

struct MapDoorPresentation: Equatable {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
}

struct MapDoorChromeSpec {
    static let attributionTypographyRole = TypographyRole.label
    static let attributionHasBackground = false
    static let locateMinimumHitTarget: CGFloat = 44
    static let usesBuiltInCompass = true
    static let doorBarBottomPadding: CGFloat = 12
    static let placeCardDoorGap: CGFloat = 28
    static let standardDoorBarClearance: CGFloat = 68
    static let accessibilityDoorBarClearance: CGFloat = 124

    static func doorBarClearance(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? accessibilityDoorBarClearance : standardDoorBarClearance
    }

    static func effectiveDoorBarBottomPadding(
        containerHeight: CGFloat,
        isPlaceCardPresented: Bool
    ) -> CGFloat {
        guard isPlaceCardPresented else { return doorBarBottomPadding }
        return (containerHeight / 2) + placeCardDoorGap
    }
}

enum MapDoorDetentPolicy {
    static func requiresLarge(
        isAccessibilitySize: Bool,
        hasDestination: Bool
    ) -> Bool {
        isAccessibilitySize || hasDestination
    }
}

struct MapDoorRowPresentation: Equatable {
    let title: String
    let subtitle: String
    let systemImage: String
    let accessibilityIdentifier: String
}

struct TracksDoorHeroContent: Equatable {
    let listID: Int64
    let metadata: String
}

struct TracksDoorListContent: Equatable, Identifiable {
    let id: Int64
    let name: String
    let isSystem: Bool
    let progress: ListProgress
}

struct TracksDoorContent: Equatable {
    static let empty = TracksDoorContent(hero: nil, lists: [])

    let hero: TracksDoorHeroContent?
    let lists: [TracksDoorListContent]

    static func make(
        lists: [PlaceList],
        progress: [Int64: ListProgress],
        visits: [TrackVisit]
    ) -> TracksDoorContent {
        let trackList = lists.first {
            $0.isSystem && $0.kind == PlaceList.trackKind
        }
        let hero = trackList.flatMap { list -> TracksDoorHeroContent? in
            guard let id = list.id else { return nil }
            guard let lastVisit = visits.last else {
                return TracksDoorHeroContent(
                    listID: id,
                    metadata: "No visits yet"
                )
            }
            let visitNoun = visits.count == 1 ? "visit" : "visits"
            return TracksDoorHeroContent(
                listID: id,
                metadata: "\(visits.count) \(visitNoun) · last: \(lastVisit.name)"
            )
        }

        let listRows = lists.compactMap { list -> TracksDoorListContent? in
            guard !(list.isSystem && list.kind == PlaceList.trackKind),
                  let id = list.id
            else {
                return nil
            }
            return TracksDoorListContent(
                id: id,
                name: list.name,
                isSystem: list.isSystem,
                progress: progress[id] ?? ListProgress(visited: 0, total: 0)
            )
        }

        return TracksDoorContent(hero: hero, lists: listRows)
    }
}

extension MapDoor {
    var presentation: MapDoorPresentation {
        switch self {
        case .world:
            MapDoorPresentation(
                title: "World",
                systemImage: "globe.europe.africa",
                accessibilityIdentifier: "map.door.world"
            )
        case .tracks:
            MapDoorPresentation(
                title: "Tracks",
                systemImage: "shoeprints.fill",
                accessibilityIdentifier: "map.door.tracks"
            )
        }
    }
}

enum WorldDoorRow: CaseIterable {
    case scope
    case settings
    case about

    var presentation: MapDoorRowPresentation {
        switch self {
        case .scope:
            MapDoorRowPresentation(
                title: "Scope",
                subtitle: "What the map shows",
                systemImage: "slider.horizontal.3",
                accessibilityIdentifier: "world.row.scope"
            )
        case .settings:
            MapDoorRowPresentation(
                title: "Settings",
                subtitle: "Appearance, data, location, and storage",
                systemImage: "gearshape",
                accessibilityIdentifier: "world.row.settings"
            )
        case .about:
            MapDoorRowPresentation(
                title: "About",
                subtitle: "The story, privacy, and licences",
                systemImage: "book.closed",
                accessibilityIdentifier: "world.row.about"
            )
        }
    }

    var title: String {
        presentation.title
    }
}

enum TracksDoorRow: CaseIterable {
    case myTracks
    case newList

    var presentation: MapDoorRowPresentation {
        switch self {
        case .newList:
            MapDoorRowPresentation(
                title: "New list",
                subtitle: "Create a list",
                systemImage: "plus",
                accessibilityIdentifier: "lists.create"
            )
        case .myTracks:
            MapDoorRowPresentation(
                title: "My tracks",
                subtitle: "Places you've seen",
                systemImage: "shoeprints.fill",
                accessibilityIdentifier: "tracks.row.my-tracks"
            )
        }
    }

    var title: String {
        presentation.title
    }
}

struct MapDoorBar: View {
    let openWorld: () -> Void
    let openTracks: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                doorButtons
            }

            VStack(spacing: 8) {
                doorButtons
            }
        }
    }

    @ViewBuilder
    private var doorButtons: some View {
        MapDoorButton(door: .world, action: openWorld)
        MapDoorButton(door: .tracks, action: openTracks)
    }
}

struct MapDoorSheet<Destination: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    let door: MapDoor
    let deepLinkDestination: MapShellDestination?
    let model: MapScreenModel?
    let openScope: () -> Void
    let onListDeleted: @MainActor (Int64) -> Void
    let destination: (MapShellDestination) -> Destination

    @State private var path: [MapShellDestination] = []
    @State private var selectedDetent = PresentationDetent.medium

    init(
        door: MapDoor,
        deepLinkDestination: MapShellDestination?,
        model: MapScreenModel?,
        openScope: @escaping () -> Void,
        onListDeleted: @escaping @MainActor (Int64) -> Void,
        @ViewBuilder destination: @escaping (MapShellDestination) -> Destination
    ) {
        self.door = door
        self.deepLinkDestination = deepLinkDestination
        self.model = model
        self.openScope = openScope
        self.onListDeleted = onListDeleted
        self.destination = destination
    }

    var body: some View {
        NavigationStack(path: $path) {
            MaterialSheet {
                root
            }
            .navigationDestination(for: MapShellDestination.self) { destination in
                destinationView(destination)
            }
        }
        .onAppear {
            applyDeepLink()
            promoteDetentIfNeeded()
        }
        .onChange(of: deepLinkDestination) {
            applyDeepLink()
            promoteDetentIfNeeded()
        }
        .onChange(of: path) {
            promoteDetentIfNeeded()
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .onChange(of: dynamicTypeSize) {
            promoteDetentIfNeeded()
        }
    }

    @ViewBuilder
    private var root: some View {
        switch door {
        case .world:
            WorldDoorRootView(path: $path, openScope: openScope)
        case .tracks:
            TracksDoorRootView(
                path: $path,
                model: model,
                onListDeleted: onListDeleted
            )
        }
    }

    private func applyDeepLink() {
        path = deepLinkDestination.map { [$0] } ?? []
    }

    private func promoteDetentIfNeeded() {
        if MapDoorDetentPolicy.requiresLarge(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            hasDestination: !path.isEmpty
        ) {
            selectedDetent = .large
        }
    }

    @ViewBuilder
    private func destinationView(_ shellDestination: MapShellDestination) -> some View {
        if shellDestination == .tracks {
            destination(shellDestination)
        } else {
            destination(shellDestination)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("door.destination.close")
                    }
                }
        }
    }
}

struct WorldDoorRootView: View {
    @Binding var path: [MapShellDestination]
    let openScope: () -> Void

    var body: some View {
        MapDoorRootLayout(
            title: "World",
            subtitle: "what’s out there"
        ) {
            MapDoorRaisedRow(
                presentation: WorldDoorRow.scope.presentation,
                action: openScope
            )
            MapDoorHairlineRow(
                presentation: WorldDoorRow.settings.presentation
            ) {
                path.append(.settings)
            }
            MapDoorHairlineRow(
                presentation: WorldDoorRow.about.presentation
            ) {
                path.append(.about)
            }
        }
    }
}

struct TracksDoorRootView: View {
    @Binding var path: [MapShellDestination]
    let model: MapScreenModel?
    let onListDeleted: @MainActor (Int64) -> Void

    @State private var content = TracksDoorContent.empty
    @State private var draftName = ""
    @State private var actionError: String?
    @State private var pendingDeleteList: TracksDoorListContent?

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        List {
            tracksHeader
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if let hero = content.hero {
                heroRow(hero)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Text("Lists")
                .font(Typography.font(for: .label))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(tokens.muted.swiftUIColor)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ForEach(content.lists) { list in
                listRow(list)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            newListRow
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if let actionError {
                Text(verbatim: actionError)
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.warning.swiftUIColor)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("lists.error")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(tokens.surface.swiftUIColor)
        .navigationBarBackButtonHidden()
        .accessibilityIdentifier("tracks.root")
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog(
            pendingDeleteList.map { "Delete \($0.name)?" } ?? "Delete list?",
            isPresented: Binding(
                get: { pendingDeleteList != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteList = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let id = pendingDeleteList?.id else { return }
                pendingDeleteList = nil
                Task { await deleteList(id: id) }
            }
            .accessibilityIdentifier("lists.delete.confirm")
            Button("Cancel", role: .cancel) {
                pendingDeleteList = nil
            }
        }
    }

    private var tracksHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tracks")
                .font(Typography.font(for: .sheetTitle))
                .foregroundStyle(tokens.ink.swiftUIColor)

            Text("your story through the world")
                .font(Typography.font(for: .evocativeSubline))
                .foregroundStyle(tokens.muted.swiftUIColor)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroRow(_ hero: TracksDoorHeroContent) -> some View {
        Button {
            path.append(.tracks)
        } label: {
            MaterialRaisedCardRow {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        heroIcon
                        heroCopy(hero)
                        Spacer(minLength: 8)
                        retraceCue
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            heroIcon
                            heroCopy(hero)
                        }
                        retraceCue
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            TracksDoorRow.myTracks.presentation.accessibilityIdentifier
        )
    }

    private var heroIcon: some View {
        Image(systemName: TracksDoorRow.myTracks.presentation.systemImage)
            .font(.headline.weight(.medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tokens.accent.swiftUIColor)
            .accessibilityHidden(true)
    }

    private func heroCopy(_ hero: TracksDoorHeroContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: TracksDoorRow.myTracks.presentation.title)
                .font(Typography.font(for: .listRowTitle))
                .foregroundStyle(tokens.ink.swiftUIColor)

            Text(verbatim: hero.metadata)
                .font(Typography.font(for: .metadata))
                .foregroundStyle(tokens.muted.swiftUIColor)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var retraceCue: some View {
        Label("Retrace", systemImage: "map")
            .font(Typography.font(for: .button))
            .foregroundStyle(tokens.accent.swiftUIColor)
            .fixedSize(horizontal: true, vertical: true)
    }

    private func listRow(_ list: TracksDoorListContent) -> some View {
        Button {
            path.append(.listDetail(list.id))
        } label: {
            MaterialHairlineRow {
                MaterialProgress(
                    state: .count(
                        completed: list.progress.visited,
                        total: list.progress.total,
                        suffix: "seen"
                    ),
                    accessibilityLabel: "\(list.name) progress"
                ) {
                    Text(verbatim: list.name)
                        .font(Typography.font(for: .listRowTitle))
                        .foregroundStyle(tokens.ink.swiftUIColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lists.row.\(list.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !list.isSystem {
                Button("Delete", role: .destructive) {
                    pendingDeleteList = list
                }
                .accessibilityIdentifier("lists.delete.\(list.id)")
            }
        }
    }

    private var newListRow: some View {
        MaterialHairlineRow {
            HStack(spacing: 8) {
                Button {
                    Task { await createList() }
                } label: {
                    Image(systemName: TracksDoorRow.newList.presentation.systemImage)
                        .font(.body.weight(.medium))
                        .foregroundStyle(tokens.accent.swiftUIColor)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create list")
                .accessibilityIdentifier(
                    TracksDoorRow.newList.presentation.accessibilityIdentifier
                )

                TextField("New list", text: $draftName)
                    .font(Typography.font(for: .body))
                    .foregroundStyle(tokens.ink.swiftUIColor)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit {
                        Task { await createList() }
                    }
                    .accessibilityIdentifier("lists.create.name")
            }
        }
    }

    @MainActor
    private func reload() async {
        guard let model else { return }
        let lists = await model.lists()
        var progress: [Int64: ListProgress] = [:]
        for list in lists {
            guard !(list.isSystem && list.kind == PlaceList.trackKind),
                  let id = list.id
            else {
                continue
            }
            progress[id] = await model.listProgress(listID: id)
        }
        let visits = await model.trackVisits()
        content = TracksDoorContent.make(
            lists: lists,
            progress: progress,
            visits: visits
        )
    }

    @MainActor
    private func createList() async {
        guard let model else { return }
        actionError = nil
        do {
            _ = try await model.createList(named: draftName)
            draftName = ""
            await reload()
        } catch {
            actionError = ListsCopy.listNameCreateFailureMessage(
                for: error,
                draftName: draftName
            )
        }
    }

    @MainActor
    private func deleteList(id: Int64) async {
        guard let model else { return }
        do {
            try await model.deleteList(id: id)
            actionError = nil
            await reload()
            onListDeleted(id)
        } catch {
            actionError = "Could not delete that list."
        }
    }
}

private struct MapDoorRootLayout<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: title)
                    .font(Typography.font(for: .sheetTitle))
                    .foregroundStyle(MaterialTheme.snow.tokens.ink.swiftUIColor)

                Text(verbatim: subtitle)
                    .font(Typography.font(for: .evocativeSubline))
                    .foregroundStyle(MaterialTheme.snow.tokens.muted.swiftUIColor)
                    .padding(.bottom, 8)

                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationBarBackButtonHidden()
    }
}

private struct MapDoorRaisedRow: View {
    let presentation: MapDoorRowPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MaterialRaisedCardRow {
                MapDoorRowLabel(presentation: presentation)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

private struct MapDoorHairlineRow: View {
    let presentation: MapDoorRowPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MaterialHairlineRow {
                MapDoorRowLabel(presentation: presentation)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

private struct MapDoorRowLabel: View {
    let presentation: MapDoorRowPresentation

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: presentation.systemImage)
                .font(.headline.weight(.medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tokens.accent.swiftUIColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: presentation.title)
                    .font(Typography.font(for: .listRowTitle))
                    .foregroundStyle(tokens.ink.swiftUIColor)

                Text(verbatim: presentation.subtitle)
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.muted.swiftUIColor)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct MapDoorButton: View {
    let door: MapDoor
    let action: () -> Void

    private let theme = MaterialTheme.snow

    var body: some View {
        let presentation = door.presentation
        let tokens = theme.tokens

        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: presentation.systemImage)
                    .font(.subheadline.weight(.medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tokens.accent.swiftUIColor)
                    .accessibilityHidden(true)

                Text(verbatim: presentation.title)
                    .font(Typography.font(for: .button))
                    .foregroundStyle(tokens.ink.swiftUIColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(tokens.surface.swiftUIColor, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tokens.hairline.swiftUIColor, lineWidth: 1)
            }
            .shadow(
                color: tokens.shadow.swiftUIColor,
                radius: 8,
                x: 0,
                y: 3
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: presentation.title))
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}
