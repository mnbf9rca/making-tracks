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
    let icon: ExploreScopeControlIcon
    let accessibilityIdentifier: String
}

enum ExploreScopePolicy {
    struct State: Equatable {
        let discoveryScope: DiscoveryScope
        let listFilter: TracksVisitFilter?
    }

    static func isAdjusted(
        discoveryScope: DiscoveryScope,
        listFilter: TracksVisitFilter?,
        showVisited: Bool
    ) -> Bool {
        discoveryScope.differsFromDefault
            || (showVisited && listFilter?.isActive == true)
    }

    static func effectiveCategoryIDs(
        discoveryScope: DiscoveryScope,
        listFilter: TracksVisitFilter?
    ) -> Set<String>? {
        if let listFilter {
            return listFilter.categories
        }
        return discoveryScope.visibleCategoryIDs
    }

    static func cleared(
        discoveryScope _: DiscoveryScope,
        listFilter: TracksVisitFilter?,
        showVisited: Bool
    ) -> State {
        State(
            discoveryScope: .defaults,
            listFilter: showVisited && listFilter != nil ? .all : listFilter
        )
    }
}

struct ExploreScopeListOption: Equatable, Identifiable {
    let id: Int64
    let title: String
}

struct ExploreListScopeContext {
    let activeListID: Int64
    let activeListName: String
    let filter: Binding<TracksVisitFilter>
    let showVisited: Binding<Bool>
    let listOptions: [ExploreScopeListOption]
}

enum ExploreScopeListOptions {
    static func eligible(
        from lists: [PlaceList],
        excludingActiveListID activeListID: Int64
    ) -> [ExploreScopeListOption] {
        lists.compactMap { list in
            guard !list.isSystem,
                  let id = list.id,
                  id != activeListID
            else {
                return nil
            }
            return ExploreScopeListOption(id: id, title: list.name)
        }
        .sorted { lhs, rhs in
            let lhsKey = lhs.title.lowercased()
            let rhsKey = rhs.title.lowercased()
            if lhsKey == rhsKey {
                return lhs.id < rhs.id
            }
            return lhsKey < rhsKey
        }
    }

    static func summary(
        selectedIDs: Set<Int64>,
        options: [ExploreScopeListOption]
    ) -> String {
        let selected = options.filter { selectedIDs.contains($0.id) }
        guard let first = selected.first else {
            return "None selected"
        }
        guard selected.count > 1 else {
            return first.title
        }
        return "\(first.title) · \(selected.count) selected"
    }
}

enum ExploreCategorySymbolPair {
    struct Symbols: Equatable {
        let selected: String
        let available: String
    }

    private static let pairs: [String: Symbols] = [
        "pin-category-archaeological": Symbols(selected: "hammer.fill", available: "hammer"),
        "pin-category-artwork": Symbols(selected: "paintpalette.fill", available: "paintpalette"),
        "pin-category-attraction": Symbols(selected: "star.fill", available: "star"),
        "pin-category-historic-building": Symbols(selected: "building.2.fill", available: "building.2"),
        "pin-category-memorial": Symbols(selected: "flag.fill", available: "flag"),
        "pin-category-museum": Symbols(selected: "camera.fill", available: "camera"),
        "pin-category-religious": Symbols(selected: "building.columns.fill", available: "building.columns"),
        PinLayers.fallbackCategoryIconName: Symbols(
            selected: "questionmark.circle.fill",
            available: "questionmark.circle"
        ),
    ]

    static func symbols(for iconName: String) -> Symbols {
        pairs[iconName] ?? pairs[PinLayers.fallbackCategoryIconName]!
    }
}

enum ExploreScopeControlIcon: Equatable {
    case system(String)
    case coverageShading
}

enum ExploreScopeControl: CaseIterable {
    case includeHidden
    case showSaved
    case coverageShading

    var presentation: ExploreScopeControlPresentation {
        switch self {
        case .includeHidden:
            ExploreScopeControlPresentation(
                title: "Include hidden places",
                icon: .system("eye.slash"),
                accessibilityIdentifier: "explore.scope.include-hidden"
            )
        case .showSaved:
            ExploreScopeControlPresentation(
                title: "Show saved places",
                icon: .system("bookmark"),
                accessibilityIdentifier: "explore.scope.show-saved"
            )
        case .coverageShading:
            ExploreScopeControlPresentation(
                title: "Show coverage shading",
                icon: .coverageShading,
                accessibilityIdentifier: "explore.scope.coverage-shading"
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
        rowItemCounts: [Int],
        itemIndex: Int
    ) -> MaterialChipNeighborGaps {
        let itemCount = rowItemCounts[rowIndex]
        let hasTopNeighbor = rowIndex > 0 && rowItemCounts[rowIndex - 1] > itemIndex
        let hasBottomNeighbor =
            rowIndex + 1 < rowItemCounts.count
            && rowItemCounts[rowIndex + 1] > itemIndex

        return MaterialChipNeighborGaps(
            top: hasTopNeighbor ? gap : nil,
            leading: itemIndex == 0 ? nil : gap,
            bottom: hasBottomNeighbor ? gap : nil,
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
    var isExploreScopeAdjusted = false

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
        MapDoorButton(
            door: .explore,
            isScopeAdjusted: isExploreScopeAdjusted,
            action: openExplore
        )
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
    let listScope: ExploreListScopeContext?
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
        listScope: ExploreListScopeContext? = nil,
        prepareTracksHistory: @escaping () -> Void,
        onListDeleted: @escaping @MainActor (Int64) -> Void,
        @ViewBuilder destination: @escaping (MapShellDestination) -> Destination
    ) {
        self.door = door
        self.deepLinkDestination = deepLinkDestination
        self.model = model
        _visibility = visibility
        self.listScope = listScope
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
            ExploreDoorRootView(
                path: $path,
                visibility: $visibility,
                listScope: listScope
            )
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
    let listScope: ExploreListScopeContext?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsOtherLists = false

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        MapDoorRootLayout(
            title: "Explore",
            subtitle: listScope == nil
                ? "what the map shows right now"
                : "scope for this list and your discovery map"
        ) {
            if listScope != nil {
                scopeSectionLabel("This list map")
                Text("Categories below narrow visits in this list.")
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.muted.swiftUIColor)
            }
            categoryHeader
            categoryChips

            if let listScope {
                listVisitControls(listScope)

                scopeSectionLabel("Discovery map defaults")
                Text("Apply after leaving this list; never filter its story.")
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.muted.swiftUIColor)
            }

            discoveryScopeRows

            if isScopeAdjusted {
                ExploreClearScopeRow(
                    includesListFilter: listScope != nil,
                    action: clearScope
                )
            }

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
        .navigationDestination(isPresented: $showsOtherLists) {
            if let listScope {
                ExploreOtherListsView(
                    visibility: $visibility,
                    listScope: listScope,
                    onBack: { showsOtherLists = false },
                    onClear: clearScope
                )
            }
        }
    }

    @ViewBuilder
    private var categoryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            if listScope == nil {
                scopeSectionLabel("Scope")
            }

            Spacer(minLength: 8)

            Button(toggleAllCategoriesTitle, action: toggleAllCategories)
                .font(Typography.font(for: .metadata))
                .foregroundStyle(tokens.accent.swiftUIColor)
                .frame(minHeight: 44)
                .accessibilityIdentifier("explore.scope.categories.toggle-all")
        }
        .padding(.horizontal, 2)
    }

    private var categoryChips: some View {
        let categoryRows = ExploreCategoryChipTopology.rows(
            visibility.categories,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        let rowItemCounts = categoryRows.map(\.count)
        return VStack(alignment: .leading, spacing: ExploreCategoryChipTopology.gap) {
            ForEach(categoryRows.indices, id: \.self) { rowIndex in
                let row = categoryRows[rowIndex]
                HStack(spacing: ExploreCategoryChipTopology.gap) {
                    ForEach(row.indices, id: \.self) { itemIndex in
                        let category = row[itemIndex]
                        let isVisible = isCategoryVisible(category.id)
                        let symbols = ExploreCategorySymbolPair.symbols(
                            for: category.iconName
                        )
                        MaterialChip(
                            category.title,
                            systemImage: isVisible
                                ? symbols.selected
                                : symbols.available,
                            state: isVisible ? .active : .available,
                            size: dynamicTypeSize.isAccessibilitySize
                                ? .expanded
                                : .compact,
                            neighborGaps: ExploreCategoryChipTopology.neighborGaps(
                                rowIndex: rowIndex,
                                rowItemCounts: rowItemCounts,
                                itemIndex: itemIndex
                            )
                        ) {
                            setCategory(category.id, visible: !isVisible)
                        }
                        .accessibilityIdentifier("explore.scope.category.\(category.id)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, listScope == nil ? 5 : 10)
    }

    @ViewBuilder
    private func listVisitControls(_ context: ExploreListScopeContext) -> some View {
        scopeSectionLabel("Visits in this list")

        let loved = context.filter.wrappedValue.lovedOnly
        MaterialChip(
            "Loved",
            systemImage: loved ? "heart.fill" : "heart",
            state: loved ? .active : .available,
            size: dynamicTypeSize.isAccessibilitySize ? .expanded : .compact
        ) {
            var filter = context.filter.wrappedValue
            filter.lovedOnly.toggle()
            context.filter.wrappedValue = filter
        }
        .accessibilityIdentifier("explore.scope.list-visits.loved")

        ExploreOtherListsRow(
            summary: ExploreScopeListOptions.summary(
                selectedIDs: context.filter.wrappedValue.listIDs,
                options: context.listOptions
            ),
            action: { showsOtherLists = true }
        )
    }

    private var discoveryScopeRows: some View {
        VStack(spacing: 0) {
            ExploreScopeToggleRow(
                control: .includeHidden,
                isOn: hiddenPlacesBinding
            )
            ExploreScopeToggleRow(
                control: .showSaved,
                isOn: savedPlacesBinding
            )
            ExploreScopeToggleRow(
                control: .coverageShading,
                isOn: coverageShadingBinding
            )
        }
        .padding(.top, listScope == nil ? 3 : 0)
    }

    private var effectiveCategoryIDs: Set<String>? {
        ExploreScopePolicy.effectiveCategoryIDs(
            discoveryScope: visibility.discoveryScope,
            listFilter: listScope?.filter.wrappedValue
        )
    }

    private var allCategoryIDs: Set<String> {
        Set(visibility.categories.map(\.id))
    }

    private func isCategoryVisible(_ categoryID: String) -> Bool {
        effectiveCategoryIDs?.contains(categoryID) ?? true
    }

    private var toggleAllCategoriesTitle: String {
        let allVisible = effectiveCategoryIDs == nil
            || effectiveCategoryIDs == allCategoryIDs
        return allVisible ? "Hide all" : "Show all"
    }

    private func setCategory(_ categoryID: String, visible: Bool) {
        guard allCategoryIDs.contains(categoryID) else { return }
        var next = effectiveCategoryIDs ?? allCategoryIDs
        if visible {
            next.insert(categoryID)
        } else {
            next.remove(categoryID)
        }
        setEffectiveCategoryIDs(next == allCategoryIDs ? nil : next)
    }

    private func toggleAllCategories() {
        let allVisible = effectiveCategoryIDs == nil
            || effectiveCategoryIDs == allCategoryIDs
        setEffectiveCategoryIDs(allVisible ? [] : nil)
    }

    private func setEffectiveCategoryIDs(_ categoryIDs: Set<String>?) {
        if let listScope {
            var filter = listScope.filter.wrappedValue
            filter.categories = categoryIDs
            listScope.filter.wrappedValue = filter
        } else {
            var next = visibility
            next.showAllCategories()
            if let categoryIDs {
                for category in next.categories {
                    next.setCategory(
                        category.id,
                        visible: categoryIDs.contains(category.id)
                    )
                }
            }
            visibility = next
        }
    }

    private var isScopeAdjusted: Bool {
        ExploreScopePolicy.isAdjusted(
            discoveryScope: visibility.discoveryScope,
            listFilter: listScope?.filter.wrappedValue,
            showVisited: listScope?.showVisited.wrappedValue ?? false
        )
    }

    private func clearScope() {
        let cleared = ExploreScopePolicy.cleared(
            discoveryScope: visibility.discoveryScope,
            listFilter: listScope?.filter.wrappedValue,
            showVisited: listScope?.showVisited.wrappedValue ?? false
        )
        visibility = MapLayerVisibility(
            categories: visibility.categories,
            scope: cleared.discoveryScope
        )
        if let listScope,
           let listFilter = cleared.listFilter,
           listFilter != listScope.filter.wrappedValue
        {
            listScope.filter.wrappedValue = listFilter
        }
    }

    private func scopeSectionLabel(_ title: String) -> some View {
        Text(verbatim: title)
            .font(Typography.font(for: .label))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(tokens.muted.swiftUIColor)
            .padding(.top, 10)
            .padding(.horizontal, 2)
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

    private var savedPlacesBinding: Binding<Bool> {
        Binding(
            get: { visibility.showSavedPlaces },
            set: { visible in
                var next = visibility
                next.showSavedPlaces = visible
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

private struct ExploreOtherListsRow: View {
    let summary: String
    let action: () -> Void

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Button(action: action) {
            MaterialHairlineRow {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet")
                        .iconRole(.rowQuiet)
                        .foregroundStyle(tokens.muted.swiftUIColor)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Other lists")
                            .font(Typography.font(for: .button))
                            .foregroundStyle(tokens.ink.swiftUIColor)
                        Text(verbatim: summary)
                            .font(Typography.font(for: .metadata))
                            .foregroundStyle(tokens.muted.swiftUIColor)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .iconRole(.accessory)
                        .foregroundStyle(tokens.muted.swiftUIColor)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Other lists")
        .accessibilityValue(Text(verbatim: summary))
        .accessibilityIdentifier("explore.scope.list-visits.lists")
    }
}

private struct ExploreClearScopeRow: View {
    let includesListFilter: Bool
    let action: () -> Void

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Button(action: action) {
            MaterialHairlineRow {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise")
                        .iconRole(.rowQuiet)
                        .foregroundStyle(tokens.muted.swiftUIColor)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear scope")
                            .font(Typography.font(for: .button))
                            .foregroundStyle(tokens.muted.swiftUIColor)
                        Text(
                            includesListFilter
                                ? "Reset this list filter and discovery defaults"
                                : "Restore discovery defaults"
                        )
                            .font(Typography.font(for: .metadata))
                            .foregroundStyle(tokens.muted.swiftUIColor)
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear scope")
        .accessibilityIdentifier("explore.scope.clear")
    }
}

private struct ExploreOtherListsView: View {
    @Binding var visibility: MapLayerVisibility
    let listScope: ExploreListScopeContext
    let onBack: () -> Void
    let onClear: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onBack) {
                Label("Scope", systemImage: "chevron.left")
                    .font(Typography.font(for: .button))
                    .foregroundStyle(tokens.accent.swiftUIColor)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 54 : 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("explore.scope.list-visits.lists.back")

            Text("Other lists")
                .font(Typography.font(for: .sheetTitle))
                .foregroundStyle(tokens.ink.swiftUIColor)

            Text("narrow \(listScope.activeListName) visits by saved-list membership")
                .font(Typography.font(for: .evocativeSubline))
                .foregroundStyle(tokens.muted.swiftUIColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            if listScope.listOptions.isEmpty {
                Text("No other saved lists; the active and system lists are excluded.")
                    .font(Typography.font(for: .body))
                    .foregroundStyle(tokens.muted.swiftUIColor)
                    .frame(maxWidth: .infinity, minHeight: 86)
                    .accessibilityIdentifier("explore.scope.list-visits.lists.empty")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(listScope.listOptions) { option in
                            listOptionRow(option)
                        }
                    }
                }
                .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 350 : 360)
            }

            Spacer(minLength: 8)

            if isScopeAdjusted {
                ExploreClearScopeRow(
                    includesListFilter: true,
                    action: onClear
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .navigationBarBackButtonHidden()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("explore.scope.list-visits.lists.root")
    }

    private func listOptionRow(_ option: ExploreScopeListOption) -> some View {
        let isSelected = listScope.filter.wrappedValue.listIDs.contains(option.id)
        return Button {
            var filter = listScope.filter.wrappedValue
            if isSelected {
                filter.listIDs.remove(option.id)
            } else {
                filter.listIDs.insert(option.id)
            }
            listScope.filter.wrappedValue = filter
        } label: {
            MaterialHairlineRow {
                HStack(spacing: 10) {
                    Text(verbatim: option.title)
                        .font(Typography.font(for: .button))
                        .foregroundStyle(tokens.ink.swiftUIColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .iconRole(.accessory)
                            .accessibilityHidden(true)
                        Text(isSelected ? "Included" : "Off")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(
                        isSelected
                            ? tokens.accentContrast.swiftUIColor
                            : tokens.accent.swiftUIColor
                    )
                    .padding(.horizontal, 9)
                    .frame(minHeight: 28)
                    .background(
                        isSelected
                            ? tokens.accent.swiftUIColor
                            : tokens.accent.swiftUIColor.opacity(0.12),
                        in: Capsule()
                    )
                    .accessibilityHidden(true)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: dynamicTypeSize.isAccessibilitySize ? 86 : 52,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: option.title))
        .accessibilityValue(isSelected ? "Included" : "Off")
        .accessibilityIdentifier("explore.scope.list-visits.list.\(option.id)")
    }

    private var isScopeAdjusted: Bool {
        ExploreScopePolicy.isAdjusted(
            discoveryScope: visibility.discoveryScope,
            listFilter: listScope.filter.wrappedValue,
            showVisited: listScope.showVisited.wrappedValue
        )
    }
}

private struct ExploreScopeToggleRow: View {
    let control: ExploreScopeControl
    @Binding var isOn: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: ScopeControlIconGeometry.relativeTextStyle)
    private var iconSize = ScopeControlIconGeometry.pointSize

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        let presentation = control.presentation
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let resolvedIconSize = ScopeControlIconGeometry.resolvedPointSize(
            scaledPointSize: iconSize,
            isAccessibilitySize: isAccessibilitySize
        )

        Toggle(isOn: $isOn) {
            HStack(spacing: isAccessibilitySize ? 14 : 10) {
                ExploreScopeControlGlyph(
                    icon: presentation.icon,
                    size: resolvedIconSize
                )
                    .foregroundStyle(
                        isOn
                            ? tokens.accent.swiftUIColor
                            : tokens.muted.swiftUIColor
                    )
                    .frame(width: isAccessibilitySize ? 30 : 24)
                    .accessibilityHidden(true)

                Text(verbatim: presentation.title)
                    .font(Typography.font(for: .button))
                    .foregroundStyle(tokens.ink.swiftUIColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 2)
        .padding(.vertical, isAccessibilitySize ? 10 : 6)
        .frame(
            maxWidth: .infinity,
            minHeight: isAccessibilitySize ? 86 : 52,
            alignment: .leading
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.hairline.swiftUIColor)
                .frame(height: 1)
        }
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

private struct ExploreScopeControlGlyph: View {
    let icon: ExploreScopeControlIcon
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        switch icon {
        case let .system(systemName):
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .symbolRenderingMode(.monochrome)
        case .coverageShading:
            ExploreCoverageGlyphShape()
                .stroke(
                    style: StrokeStyle(
                        lineWidth: 1.8,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [3, 2.6]
                    )
                )
                .frame(width: size, height: size)
        }
    }
}

private struct ExploreCoverageGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: 5 / 24, y: 9.6 / 24),
            CGPoint(x: 9.4 / 24, y: 4.6 / 24),
            CGPoint(x: 16.2 / 24, y: 5.8 / 24),
            CGPoint(x: 19.6 / 24, y: 12 / 24),
            CGPoint(x: 16 / 24, y: 18.8 / 24),
            CGPoint(x: 8 / 24, y: 18.2 / 24),
        ].map { point in
            CGPoint(
                x: rect.minX + point.x * rect.width,
                y: rect.minY + point.y * rect.height
            )
        }

        var path = Path()
        guard let first = points.first else {
            return path
        }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

struct ExploreQuietDestinationRow: View {
    let presentation: MapDoorRowPresentation
    let prominent: Bool
    let action: () -> Void

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Button(action: action) {
            MaterialHairlineRow {
                HStack(spacing: 10) {
                    ExploreQuietDestinationIconColumn(
                        systemName: presentation.systemImage
                    )
                        .foregroundStyle(
                            prominent
                                ? tokens.accent.swiftUIColor
                                : tokens.muted.swiftUIColor
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: presentation.title)
                            .font(Typography.font(for: .button))
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

struct ExploreQuietDestinationIconColumn: View {
    let systemName: String

    @ScaledMetric(relativeTo: .subheadline) private var width = 24.0

    var body: some View {
        ExploreQuietDestinationIconGlyph(systemName: systemName)
            .frame(width: width)
    }
}

struct ExploreQuietDestinationIconGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .iconRole(.rowQuiet)
            // T2.3 preserve ruling: destination rows adopt rowQuiet's
            // size/anchor but do not join A5's weight-pulse family yet.
            .fontWeight(.medium)
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

struct MapDoorRaisedRow: View {
    let presentation: MapDoorRowPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MaterialRaisedCardRow {
                MapDoorRowLabel(
                    presentation: presentation,
                    iconRole: .rowRaised
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

struct MapDoorHairlineRow: View {
    let presentation: MapDoorRowPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MaterialHairlineRow {
                MapDoorRowLabel(
                    presentation: presentation,
                    iconRole: .rowQuiet
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

struct MapDoorRowIconGlyph: View {
    let systemName: String
    let role: IconRole

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Image(systemName: systemName)
            .iconRole(role)
            .foregroundStyle(tokens.accent.swiftUIColor)
    }
}

struct MapDoorRowIconColumn: View {
    let systemName: String
    let role: IconRole

    @ScaledMetric(relativeTo: .headline) private var raisedWidth = 32.0
    @ScaledMetric(relativeTo: .subheadline) private var quietWidth = 28.0

    private var width: Double {
        role == .rowRaised ? raisedWidth : quietWidth
    }

    var body: some View {
        MapDoorRowIconGlyph(
            systemName: systemName,
            role: role
        )
        .frame(width: width)
    }
}

struct MapDoorRowLabel: View {
    let presentation: MapDoorRowPresentation
    let iconRole: IconRole

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        HStack(spacing: 12) {
            MapDoorRowIconColumn(
                systemName: presentation.systemImage,
                role: iconRole
            )
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

#if DEBUG
struct DoorGlyphEvidenceFixture: View {
    let legacy: Bool

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Door glyph contract")
                    .font(Typography.font(for: .heroTitle))
                    .foregroundStyle(tokens.ink.swiftUIColor)

                Text(legacy ? "Before — 17pt literal" : "After — semantic roles")
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.muted.swiftUIColor)
                    .accessibilityIdentifier("door-glyph.fixture.state")

                DoorGlyphEvidenceRow(
                    title: "Raised row",
                    subtitle: legacy ? "headline literal · 17pt" : "rowRaised · 20pt headline",
                    role: .rowRaised,
                    raised: true,
                    legacy: legacy
                )

                DoorGlyphEvidenceRow(
                    title: "Quiet row",
                    subtitle: legacy ? "headline literal · 17pt" : "rowQuiet · 18pt subheadline",
                    role: .rowQuiet,
                    raised: false,
                    legacy: legacy
                )
            }
            .padding(24)
        }
        .background(tokens.background.swiftUIColor)
    }
}

private struct DoorGlyphEvidenceRow: View {
    let title: String
    let subtitle: String
    let role: IconRole
    let raised: Bool
    let legacy: Bool

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Group {
            if raised {
                MaterialRaisedCardRow { label }
            } else {
                MaterialHairlineRow { label }
            }
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            Group {
                if legacy {
                    Image(systemName: "cloud.sun.rain.fill")
                        // Deliberately the retired 17pt path, retained only to
                        // regenerate before/after evidence. Do not migrate it.
                        .font(.headline.weight(.medium))
                        .symbolRenderingMode(.monochrome)
                        .frame(width: 28)
                } else {
                    MapDoorRowIconColumn(
                        systemName: "cloud.sun.rain.fill",
                        role: role
                    )
                }
            }
            .foregroundStyle(tokens.accent.swiftUIColor)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) icon")
            .accessibilityIdentifier("door-glyph.fixture.\(roleName).icon")

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(Typography.font(for: .listRowTitle))
                    .foregroundStyle(tokens.ink.swiftUIColor)

                Text(verbatim: subtitle)
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.muted.swiftUIColor)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("door-glyph.fixture.\(roleName).copy")
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var roleName: String {
        role == .rowRaised ? "raised" : "quiet"
    }
}
#endif

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
    var isScopeAdjusted = false
    let action: () -> Void

    private let theme = MaterialTheme.snow

    var body: some View {
        let presentation = door.presentation
        let tokens = theme.tokens
        let iconName = door == .explore && isScopeAdjusted
            ? "line.3.horizontal.decrease.circle.fill"
            : presentation.systemImage

        Button(action: action) {
            HStack(spacing: 8) {
                MapDoorButtonIconGlyph(systemName: iconName)
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
        .accessibilityValue(
            Text(
                verbatim: door == .explore
                    ? (isScopeAdjusted ? "Scope adjusted" : "Default scope")
                    : ""
            )
        )
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}
