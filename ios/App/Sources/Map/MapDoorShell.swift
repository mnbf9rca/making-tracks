import DesignSystem
import MakingTracksData
import MakingTracksMapStyle
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
        door: MapDoor,
        isAccessibilitySize: Bool,
        hasDestination: Bool
    ) -> Bool {
        door == .explore || isAccessibilitySize || hasDestination
    }
}

struct MapDoorRowPresentation: Equatable {
    let title: String
    let subtitle: String
    let systemImage: String
    let accessibilityIdentifier: String
}

struct ExploreScopeControlPresentation: Equatable {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
}

enum ExploreScopeControl: CaseIterable {
    case includeHidden
    case coverageShading

    var presentation: ExploreScopeControlPresentation {
        switch self {
        case .includeHidden:
            ExploreScopeControlPresentation(
                title: "Include hidden places",
                systemImage: "eye.slash",
                accessibilityIdentifier: "map.layers.show-hidden"
            )
        case .coverageShading:
            ExploreScopeControlPresentation(
                title: "Show offline coverage shading",
                systemImage: "map",
                accessibilityIdentifier: "map.layers.coverage-shading"
            )
        }
    }
}

enum ExploreCategoryChipTopology {
    static let gap: CGFloat = 6

    static func rows(
        _ categories: [MapLayerCategory],
        isAccessibilitySize: Bool
    ) -> [[MapLayerCategory]] {
        let rowCapacity = isAccessibilitySize ? 2 : 3
        return stride(from: 0, to: categories.count, by: rowCapacity).map { start in
            Array(categories[start ..< min(start + rowCapacity, categories.count)])
        }
    }

    static func neighborGaps(
        rowIndex: Int,
        rowCount: Int,
        itemIndex: Int,
        itemCount: Int
    ) -> MaterialChipNeighborGaps {
        MaterialChipNeighborGaps(
            top: rowIndex == 0 ? nil : gap,
            leading: itemIndex == 0 ? nil : gap,
            bottom: rowIndex == rowCount - 1 ? nil : gap,
            trailing: itemIndex == itemCount - 1 ? nil : gap
        )
    }
}

struct JournalDoorHeroContent: Equatable {
    let listID: Int64
    let metadata: String
}

struct JournalDoorListContent: Equatable, Identifiable {
    let id: Int64
    let name: String
    let isSystem: Bool
    let progress: ListProgress
}

struct JournalDoorContent: Equatable {
    static let empty = JournalDoorContent(
        hero: nil,
        lists: [],
        lovedCount: 0,
        hiddenCount: 0
    )

    let hero: JournalDoorHeroContent?
    let lists: [JournalDoorListContent]
    let lovedCount: Int
    let hiddenCount: Int

    static func make(
        lists: [PlaceList],
        progress: [Int64: ListProgress],
        visits: [TrackVisit],
        lovedPlaces: [ListPlace],
        hiddenPlaces: [ListPlace]
    ) -> JournalDoorContent {
        let trackList = lists.first {
            $0.isSystem && $0.kind == PlaceList.trackKind
        }
        let hero = trackList.flatMap { list -> JournalDoorHeroContent? in
            guard let id = list.id else { return nil }
            guard let lastVisit = visits.last else {
                return JournalDoorHeroContent(
                    listID: id,
                    metadata: "No visits yet"
                )
            }
            let visitNoun = visits.count == 1 ? "visit" : "visits"
            return JournalDoorHeroContent(
                listID: id,
                metadata: "\(visits.count) \(visitNoun) · last: \(lastVisit.name)"
            )
        }

        let listRows = lists.compactMap { list -> JournalDoorListContent? in
            guard !(list.isSystem && list.kind == PlaceList.trackKind),
                  let id = list.id
            else {
                return nil
            }
            return JournalDoorListContent(
                id: id,
                name: list.name,
                isSystem: list.isSystem,
                progress: progress[id] ?? ListProgress(visited: 0, total: 0)
            )
        }

        return JournalDoorContent(
            hero: hero,
            lists: listRows,
            lovedCount: lovedPlaces.count,
            hiddenCount: hiddenPlaces.count
        )
    }
}

extension MapDoor {
    var presentation: MapDoorPresentation {
        switch self {
        case .explore:
            MapDoorPresentation(
                title: "Explore",
                systemImage: "globe.europe.africa",
                accessibilityIdentifier: "map.door.explore"
            )
        case .journal:
            MapDoorPresentation(
                title: "Journal",
                systemImage: "shoeprints.fill",
                accessibilityIdentifier: "map.door.journal"
            )
        }
    }
}

enum ExploreDoorRow: CaseIterable {
    case settings
    case about

    var presentation: MapDoorRowPresentation {
        switch self {
        case .settings:
            MapDoorRowPresentation(
                title: "Settings",
                subtitle: "appearance, data, location, storage",
                systemImage: "gearshape",
                accessibilityIdentifier: "explore.row.settings"
            )
        case .about:
            MapDoorRowPresentation(
                title: "About",
                subtitle: "the story · privacy · licences",
                systemImage: "book.closed",
                accessibilityIdentifier: "explore.row.about"
            )
        }
    }

    var title: String {
        presentation.title
    }
}

enum JournalDoorRow: CaseIterable {
    case myTracks
    case newList
    case lovedPlaces
    case hiddenPlaces

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
                accessibilityIdentifier: "journal.row.my-tracks"
            )
        case .lovedPlaces:
            MapDoorRowPresentation(
                title: "Loved places",
                subtitle: "Places you've loved",
                systemImage: "heart",
                accessibilityIdentifier: "journal.row.loved"
            )
        case .hiddenPlaces:
            MapDoorRowPresentation(
                title: "Hidden places",
                subtitle: "Places you've hidden",
                systemImage: "eye.slash",
                accessibilityIdentifier: "journal.row.hidden"
            )
        }
    }

    var title: String {
        presentation.title
    }
}

struct MapDoorBar: View {
    let openExplore: () -> Void
    let openJournal: () -> Void

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
        MapDoorButton(door: .explore, action: openExplore)
        MapDoorButton(door: .journal, action: openJournal)
    }
}

struct MapDoorSheet<Destination: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    let door: MapDoor
    let deepLinkDestination: MapShellDestination?
    let model: MapScreenModel?
    @Binding var visibility: MapLayerVisibility
    let prepareTracksHistory: () -> Void
    let onListDeleted: @MainActor (Int64) -> Void
    let destination: (MapShellDestination) -> Destination

    @State private var path: [MapShellDestination] = []
    @State private var selectedDetent = PresentationDetent.medium

    init(
        door: MapDoor,
        deepLinkDestination: MapShellDestination?,
        model: MapScreenModel?,
        visibility: Binding<MapLayerVisibility>,
        prepareTracksHistory: @escaping () -> Void,
        onListDeleted: @escaping @MainActor (Int64) -> Void,
        @ViewBuilder destination: @escaping (MapShellDestination) -> Destination
    ) {
        self.door = door
        self.deepLinkDestination = deepLinkDestination
        self.model = model
        _visibility = visibility
        self.prepareTracksHistory = prepareTracksHistory
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
        case .explore:
            ExploreDoorRootView(path: $path, visibility: $visibility)
        case .journal:
            JournalDoorRootView(
                path: $path,
                model: model,
                prepareTracksHistory: prepareTracksHistory,
                onListDeleted: onListDeleted
            )
        }
    }

    private func applyDeepLink() {
        path = deepLinkDestination.map { [$0] } ?? []
    }

    private func promoteDetentIfNeeded() {
        if MapDoorDetentPolicy.requiresLarge(
            door: door,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            hasDestination: !path.isEmpty
        ) {
            selectedDetent = .large
        }
    }

    @ViewBuilder
    func destinationView(_ shellDestination: MapShellDestination) -> some View {
        if shellDestination == .tracks {
            destination(shellDestination)
        } else {
            destination(shellDestination)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: dismiss.callAsFunction) {
                            MapDoorDestinationCloseIconGlyph()
                        }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("door.destination.close")
                    }
                }
        }
    }
}

struct MapDoorDestinationCloseIconGlyph: View {
    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Image(systemName: "xmark")
            .iconRole(.inline)
            .foregroundStyle(tokens.muted.swiftUIColor)
    }
}

struct ExploreDoorRootView: View {
    @Binding var path: [MapShellDestination]
    @Binding var visibility: MapLayerVisibility

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        MapDoorRootLayout(
            title: "Explore",
            subtitle: "what the map shows right now"
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text("Scope")
                    .font(Typography.font(for: .label))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(tokens.muted.swiftUIColor)

                Spacer(minLength: 8)

                Button(visibility.toggleAllCategoriesTitle) {
                    var next = visibility
                    next.toggleAllCategories()
                    visibility = next
                }
                .font(Typography.font(for: .metadata))
                .foregroundStyle(tokens.accent.swiftUIColor)
                .accessibilityIdentifier("map.layers.show-all-categories")
            }
            .padding(.top, 10)
            .padding(.horizontal, 2)

            let categoryRows = ExploreCategoryChipTopology.rows(
                visibility.categories,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            )
            VStack(alignment: .leading, spacing: ExploreCategoryChipTopology.gap) {
                ForEach(categoryRows.indices, id: \.self) { rowIndex in
                    let row = categoryRows[rowIndex]
                    HStack(spacing: ExploreCategoryChipTopology.gap) {
                        ForEach(row.indices, id: \.self) { itemIndex in
                            let category = row[itemIndex]
                            MaterialChip(
                                category.title,
                                systemImage: PinLayers.categorySymbolNames[category.iconName] ?? "mappin",
                                state: visibility.isCategoryVisible(category.id) ? .active : .available,
                                size: dynamicTypeSize.isAccessibilitySize ? .expanded : .compact,
                                neighborGaps: ExploreCategoryChipTopology.neighborGaps(
                                    rowIndex: rowIndex,
                                    rowCount: categoryRows.count,
                                    itemIndex: itemIndex,
                                    itemCount: row.count
                                )
                            ) {
                                var next = visibility
                                next.setCategory(
                                    category.id,
                                    visible: !visibility.isCategoryVisible(category.id)
                                )
                                visibility = next
                            }
                            .accessibilityIdentifier("map.layers.category.\(category.id)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 5)

            VStack(spacing: 0) {
                ExploreScopeToggleRow(
                    control: .includeHidden,
                    isOn: hiddenPlacesBinding,
                    minimumHeight: scopeControlMinimumHeight
                )
                ExploreScopeToggleRow(
                    control: .coverageShading,
                    isOn: coverageShadingBinding,
                    minimumHeight: scopeControlMinimumHeight
                )
            }
            .padding(.top, 3)

            Spacer(minLength: 16)

            ExploreQuietDestinationRow(
                presentation: ExploreDoorRow.settings.presentation,
                prominent: true
            ) {
                path.append(.settings)
            }
            ExploreQuietDestinationRow(
                presentation: ExploreDoorRow.about.presentation,
                prominent: false
            ) {
                path.append(.about)
            }
        }
        .accessibilityIdentifier("explore.root")
    }

    private var scopeControlMinimumHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 86 : 52
    }

    private var hiddenPlacesBinding: Binding<Bool> {
        Binding(
            get: { visibility.showHiddenPlaces },
            set: { visible in
                var next = visibility
                next.showHiddenPlaces = visible
                visibility = next
            }
        )
    }

    private var coverageShadingBinding: Binding<Bool> {
        Binding(
            get: { visibility.showCoverageShading },
            set: { visible in
                var next = visibility
                next.showCoverageShading = visible
                visibility = next
            }
        )
    }
}

private struct ExploreScopeToggleRow: View {
    let control: ExploreScopeControl
    @Binding var isOn: Bool
    let minimumHeight: CGFloat

    @ScaledMetric(relativeTo: .body)
    private var iconSize = ExploreSurfaceIconGeometry.scopeControl

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        let presentation = control.presentation

        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: presentation.systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(
                        isOn
                            ? tokens.accent.swiftUIColor
                            : tokens.muted.swiftUIColor
                    )
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(verbatim: presentation.title)
                    .font(Typography.font(for: .button))
                    .foregroundStyle(tokens.ink.swiftUIColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.hairline.swiftUIColor)
                .frame(height: 1)
        }
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

private struct ExploreQuietDestinationRow: View {
    let presentation: MapDoorRowPresentation
    let prominent: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body)
    private var iconSize = ExploreSurfaceIconGeometry.quietDestination

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Button(action: action) {
            MaterialHairlineRow {
                HStack(spacing: 10) {
                    Image(systemName: presentation.systemImage)
                        .font(.system(size: iconSize, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            prominent
                                ? tokens.accent.swiftUIColor
                                : tokens.muted.swiftUIColor
                        )
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: presentation.title)
                            .font(Typography.font(for: .listRowTitle))
                            .foregroundStyle(
                                prominent
                                    ? tokens.ink.swiftUIColor
                                    : tokens.muted.swiftUIColor
                            )
                        Text(verbatim: presentation.subtitle)
                            .font(Typography.font(for: .metadata))
                            .foregroundStyle(tokens.muted.swiftUIColor)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .iconRole(.accessory)
                        .foregroundStyle(
                            prominent
                                ? tokens.accent.swiftUIColor
                                : tokens.muted.swiftUIColor
                        )
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

struct JournalDoorHeroIconGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .iconRole(.hero)
    }
}

struct JournalDoorHeroTitle: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(Typography.font(for: .heroTitle))
    }
}

struct JournalDoorRetraceCue: View {
    var body: some View {
        HStack(spacing: 3) {
            Text("Retrace")
            Image(systemName: "chevron.right")
                .iconRole(.accessory)
                .accessibilityHidden(true)
        }
        // R12: ia-doors.html:428-431 and :753 ratify Retrace at SF 13/600.
        .font(Typography.font(for: .action))
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct JournalDoorNewListIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .iconRole(.inline)
    }
}

struct JournalDoorVirtualRowIconGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .iconRole(.inline)
    }
}

struct JournalDoorRootView: View {
    @Binding var path: [MapShellDestination]
    let model: MapScreenModel?
    let prepareTracksHistory: () -> Void
    let onListDeleted: @MainActor (Int64) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var content = JournalDoorContent.empty
    @State private var draftName = ""
    @State private var actionError: String?
    @State private var pendingDeleteList: JournalDoorListContent?

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        List {
            journalHeader
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

            virtualPlacesRow(
                JournalDoorRow.lovedPlaces,
                count: content.lovedCount,
                destination: .lovedPlaces
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            virtualPlacesRow(
                JournalDoorRow.hiddenPlaces,
                count: content.hiddenCount,
                destination: .hiddenPlaces,
                quiet: true
            )
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
        .accessibilityIdentifier("journal.root")
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: path) { previous, current in
            if !previous.isEmpty, current.isEmpty {
                Task { await reload() }
            }
        }
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

    private var journalHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Journal")
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

    private func heroRow(_ hero: JournalDoorHeroContent) -> some View {
        Button {
            prepareTracksHistory()
            path.append(.tracks)
        } label: {
            MaterialRaisedCardRow {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            heroIcon
                            heroCopy(hero)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        retraceCue
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                } else {
                    HStack(spacing: 12) {
                        heroIcon
                        heroCopy(hero)
                        Spacer(minLength: 8)
                        retraceCue
                    }
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            JournalDoorRow.myTracks.presentation.accessibilityIdentifier
        )
    }

    private var heroIcon: some View {
        JournalDoorHeroIconGlyph(
            systemName: JournalDoorRow.myTracks.presentation.systemImage
        )
        .foregroundStyle(tokens.accent.swiftUIColor)
        .accessibilityHidden(true)
    }

    private func heroCopy(_ hero: JournalDoorHeroContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            JournalDoorHeroTitle(
                title: JournalDoorRow.myTracks.presentation.title
            )
            .foregroundStyle(tokens.ink.swiftUIColor)

            Text(verbatim: hero.metadata)
                .font(Typography.font(for: .metadata))
                .foregroundStyle(tokens.muted.swiftUIColor)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var retraceCue: some View {
        JournalDoorRetraceCue()
            .foregroundStyle(tokens.accent.swiftUIColor)
    }

    private func listRow(_ list: JournalDoorListContent) -> some View {
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
                    JournalDoorNewListIcon(
                        systemName: JournalDoorRow.newList.presentation.systemImage
                    )
                    .foregroundStyle(tokens.accent.swiftUIColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create list")
                .accessibilityIdentifier(
                    JournalDoorRow.newList.presentation.accessibilityIdentifier
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

    func virtualPlacesRow(
        _ row: JournalDoorRow,
        count: Int,
        destination: MapShellDestination,
        quiet: Bool = false
    ) -> some View {
        let presentation = row.presentation
        let primary = quiet ? tokens.muted.swiftUIColor : tokens.ink.swiftUIColor

        return Button {
            path.append(destination)
        } label: {
            MaterialHairlineRow {
                HStack(spacing: 12) {
                    JournalDoorVirtualRowIconGlyph(systemName: presentation.systemImage)
                        .foregroundStyle(
                            quiet
                                ? tokens.muted.swiftUIColor
                                : tokens.accent.swiftUIColor
                        )
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    Text(verbatim: presentation.title)
                        .font(Typography.font(for: .listRowTitle))
                        .foregroundStyle(primary)

                    Spacer(minLength: 8)

                    Text(verbatim: String(count))
                        .font(Typography.font(for: .metadata))
                        .foregroundStyle(tokens.muted.swiftUIColor)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: presentation.title))
        .accessibilityValue(
            Text(verbatim: "\(count) \(count == 1 ? "place" : "places")")
        )
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
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
        let lovedPlaces = await model.lovedPlaces()
        let hiddenPlaces = await model.hiddenPlaces()
        content = JournalDoorContent.make(
            lists: lists,
            progress: progress,
            visits: visits,
            lovedPlaces: lovedPlaces,
            hiddenPlaces: hiddenPlaces
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
        GeometryReader { proxy in
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
                .frame(
                    minHeight: proxy.size.height,
                    alignment: .top
                )
            }
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

struct MapDoorRowIconGlyph: View {
    let systemName: String

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Image(systemName: systemName)
            // ia-doors.html:676,690,698 and :710,717 ratifies 20px
            // raised and 18px quiet row glyphs. IconRole expresses neither;
            // retain this pre-existing 17pt literal unchanged and non-compliant
            // pending the metrics-table/fourth-row-role amendment ruling.
            .font(.headline.weight(.medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tokens.accent.swiftUIColor)
    }
}

struct MapDoorRowLabel: View {
    let presentation: MapDoorRowPresentation

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        HStack(spacing: 12) {
            MapDoorRowIconGlyph(systemName: presentation.systemImage)
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

struct MapDoorButtonIconGlyph: View {
    let systemName: String

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Image(systemName: systemName)
            .iconRole(.inline)
            .foregroundStyle(tokens.accent.swiftUIColor)
    }
}

struct MapDoorButton: View {
    let door: MapDoor
    let action: () -> Void

    private let theme = MaterialTheme.snow

    var body: some View {
        let presentation = door.presentation
        let tokens = theme.tokens

        Button(action: action) {
            HStack(spacing: 8) {
                MapDoorButtonIconGlyph(systemName: presentation.systemImage)
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
