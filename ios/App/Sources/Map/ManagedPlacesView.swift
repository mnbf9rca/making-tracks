import DesignSystem
import MakingTracksData
import SwiftUI

struct ManagedPlacesInlineIconGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .iconRole(.inline)
            .fixedSize()
    }
}

struct ManagedPlacesEmptyIconGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .iconRole(.hero)
    }
}

struct ManagedPlacesPresentation: Equatable {
    let title: String
    let systemImage: String
    let emptyTitle: String
    let emptyGuidance: String
    let surfaceIdentifier: String
    let rowIdentifierPrefix: String
    let primaryActionIdentifierPrefix: String
    let secondaryActionIdentifierPrefix: String?
    let failureMessage: String

    func primaryActionIdentifier(placeID: String) -> String {
        "\(primaryActionIdentifierPrefix).\(placeID)"
    }

    func secondaryActionIdentifier(placeID: String) -> String {
        guard let secondaryActionIdentifierPrefix else {
            preconditionFailure("This managed-places mode has no secondary action.")
        }
        return "\(secondaryActionIdentifierPrefix).\(placeID)"
    }
}

enum ManagedPlacesMode: Equatable {
    case loved
    case hidden

    var presentation: ManagedPlacesPresentation {
        switch self {
        case .loved:
            ManagedPlacesPresentation(
                title: "Loved places",
                systemImage: "heart",
                emptyTitle: "No loved places yet",
                emptyGuidance: "Love a place you’ve seen and it’ll wait here.",
                surfaceIdentifier: "tracks.loved.surface",
                rowIdentifierPrefix: "tracks.loved.row",
                primaryActionIdentifierPrefix: "tracks.loved.remove",
                secondaryActionIdentifierPrefix: nil,
                failureMessage: "Could not update that loved place."
            )
        case .hidden:
            ManagedPlacesPresentation(
                title: "Hidden places",
                systemImage: "eye.slash",
                emptyTitle: "No hidden places",
                emptyGuidance: "Places you hide will wait here until you bring them back.",
                surfaceIdentifier: "tracks.hidden.surface",
                rowIdentifierPrefix: "tracks.hidden.row",
                primaryActionIdentifierPrefix: "tracks.hidden.unhide",
                secondaryActionIdentifierPrefix: "tracks.hidden.save",
                failureMessage: "Could not unhide that place."
            )
        }
    }

    func actionAccessibilityLabel(placeName: String) -> String {
        switch self {
        case .loved:
            "Remove loved from \(placeName)"
        case .hidden:
            "Unhide \(placeName)"
        }
    }

    func metadata(for place: ListPlace) -> String {
        let category = Self.categoryLabel(place.category)
        if self == .loved, place.pinState.hidden {
            return "\(category) · Hidden"
        }
        return category
    }

    private static func categoryLabel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

struct ManagedPlacesState: Equatable {
    var places: [ListPlace]
    var pendingPlaceIDs: Set<String>
    var errorMessage: String?

    init(
        places: [ListPlace],
        pendingPlaceIDs: Set<String> = [],
        errorMessage: String? = nil
    ) {
        self.places = places
        self.pendingPlaceIDs = pendingPlaceIDs
        self.errorMessage = errorMessage
    }

    mutating func replacePlaces(_ next: [ListPlace]) {
        places = next
        pendingPlaceIDs = []
        errorMessage = nil
    }

    mutating func beginAction(placeID: String) {
        pendingPlaceIDs.insert(placeID)
        errorMessage = nil
    }

    mutating func finishAction(
        placeID: String,
        succeeded: Bool,
        failureMessage: String
    ) {
        guard pendingPlaceIDs.remove(placeID) != nil else { return }
        if succeeded {
            places.removeAll { $0.placeID == placeID }
        } else {
            errorMessage = failureMessage
        }
    }

    mutating func removePlace(placeID: String) {
        places.removeAll { $0.placeID == placeID }
        pendingPlaceIDs.remove(placeID)
        errorMessage = nil
    }

    func isPending(placeID: String) -> Bool {
        pendingPlaceIDs.contains(placeID)
    }
}

@MainActor
enum ManagedPlacesActionCoordinator {
    static func perform(
        begin: () -> Void,
        finish: (Bool) -> Void,
        operation: () async throws -> Void
    ) async {
        begin()
        do {
            try await operation()
            finish(true)
        } catch {
            finish(false)
        }
    }
}

struct ManagedPlacesView: View {
    let model: MapScreenModel?
    let mode: ManagedPlacesMode

    @State private var state = ManagedPlacesState(places: [])
    @State private var didLoad = false
    @State private var saveTarget: ListPlace?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        List {
            titleRow
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if let errorMessage = state.errorMessage {
                Text(verbatim: errorMessage)
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.warning.swiftUIColor)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("\(mode.presentation.surfaceIdentifier).error")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if state.places.isEmpty {
                if didLoad {
                    emptyRow
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityIdentifier("\(mode.presentation.surfaceIdentifier).loading")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(state.places) { place in
                    placeRow(place)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(tokens.surface.swiftUIColor)
        .accessibilityIdentifier(mode.presentation.surfaceIdentifier)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $saveTarget) { place in
            ListPickerView(
                placeID: place.placeID,
                model: model,
                onChanged: { change in
                    if case .added = change {
                        state.removePlace(placeID: place.placeID)
                    }
                }
            )
        }
    }

    var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ManagedPlacesInlineIconGlyph(systemName: mode.presentation.systemImage)
                .foregroundStyle(
                    mode == .hidden
                        ? tokens.muted.swiftUIColor
                        : tokens.accent.swiftUIColor
                )
                .accessibilityHidden(true)

            Text(verbatim: mode.presentation.title)
                .font(Typography.font(for: .sheetTitle))
                .foregroundStyle(
                    mode == .hidden
                        ? tokens.muted.swiftUIColor
                        : tokens.ink.swiftUIColor
                )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var emptyRow: some View {
        ContentUnavailableView {
            Label {
                Text(verbatim: mode.presentation.emptyTitle)
            } icon: {
                ManagedPlacesEmptyIconGlyph(systemName: mode.presentation.systemImage)
            }
        } description: {
            Text(verbatim: mode.presentation.emptyGuidance)
        }
        .foregroundStyle(tokens.muted.swiftUIColor)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 220)
        .accessibilityIdentifier("\(mode.presentation.surfaceIdentifier).empty")
    }

    func placeRow(_ place: ListPlace) -> some View {
        MaterialHairlineRow {
            if mode == .hidden, dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    placeIdentity(place)
                    actionButton(for: place)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    placeIdentity(place)
                    actionButton(for: place)
                }
                .frame(minHeight: 44)
            }
        }
    }

    func placeIdentity(_ place: ListPlace) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ManagedPlacesInlineIconGlyph(systemName: mode.presentation.systemImage)
                .foregroundStyle(
                    mode == .hidden
                        ? tokens.muted.swiftUIColor
                        : tokens.accent.swiftUIColor
                )
                .frame(minWidth: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: place.name)
                    .font(Typography.font(for: .listRowTitle))
                    .foregroundStyle(
                        mode == .hidden
                            ? tokens.muted.swiftUIColor
                            : tokens.ink.swiftUIColor
                    )

                Text(verbatim: mode.metadata(for: place))
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.muted.swiftUIColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(
                "\(mode.presentation.rowIdentifierPrefix).\(place.placeID)"
            )
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    @ViewBuilder
    func actionButton(for place: ListPlace) -> some View {
        switch mode {
        case .loved:
            Button {
                Task { await performAction(for: place) }
            } label: {
                ManagedPlacesInlineIconGlyph(systemName: "heart.slash")
            }
            .foregroundStyle(tokens.accent.swiftUIColor)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(state.isPending(placeID: place.placeID))
            .opacity(
                state.isPending(placeID: place.placeID)
                    ? tokens.disabledAlpha
                    : 1
            )
            .accessibilityLabel(
                mode.actionAccessibilityLabel(placeName: place.name)
            )
            .accessibilityIdentifier(
                mode.presentation.primaryActionIdentifier(placeID: place.placeID)
            )

        case .hidden:
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 8))

            layout {
                Button("Unhide") {
                    Task { await performAction(for: place) }
                }
                .buttonStyle(MaterialTonalButtonStyle())
                .accessibilityLabel("Unhide \(place.name)")
                .accessibilityIdentifier(
                    mode.presentation.primaryActionIdentifier(placeID: place.placeID)
                )

                Button("Save") {
                    saveTarget = place
                }
                .buttonStyle(MaterialQuietButtonStyle())
                .accessibilityLabel("Save \(place.name)")
                .accessibilityIdentifier(
                    mode.presentation.secondaryActionIdentifier(placeID: place.placeID)
                )
            }
            .disabled(state.isPending(placeID: place.placeID))
        }
    }

    @MainActor
    private func reload() async {
        guard state.pendingPlaceIDs.isEmpty else { return }
        let places: [ListPlace]
        switch mode {
        case .loved:
            places = await model?.lovedPlaces() ?? []
        case .hidden:
            places = await model?.hiddenPlaces() ?? []
        }
        state.replacePlaces(places)
        didLoad = true
    }

    @MainActor
    private func performAction(for place: ListPlace) async {
        guard let model, !state.isPending(placeID: place.placeID) else { return }
        await ManagedPlacesActionCoordinator.perform {
            state.beginAction(placeID: place.placeID)
        } finish: { succeeded in
            state.finishAction(
                placeID: place.placeID,
                succeeded: succeeded,
                failureMessage: mode.presentation.failureMessage
            )
        } operation: {
            switch mode {
            case .loved:
                try await model.setLoved(placeID: place.placeID, loved: false)
            case .hidden:
                try await model.setHidden(placeID: place.placeID, hidden: false)
            }
        }
    }
}
