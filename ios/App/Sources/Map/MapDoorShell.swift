import DesignSystem
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
    static let standardDoorBarClearance: CGFloat = 68
    static let accessibilityDoorBarClearance: CGFloat = 124

    static func doorBarClearance(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? accessibilityDoorBarClearance : standardDoorBarClearance
    }
}

struct MapDoorRowPresentation: Equatable {
    let title: String
    let subtitle: String
    let systemImage: String
    let accessibilityIdentifier: String
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
    case lists
    case myTracks

    var presentation: MapDoorRowPresentation {
        switch self {
        case .lists:
            MapDoorRowPresentation(
                title: "Lists",
                subtitle: "Saved places and collections",
                systemImage: "list.bullet",
                accessibilityIdentifier: "tracks.row.lists"
            )
        case .myTracks:
            MapDoorRowPresentation(
                title: "My Tracks",
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

extension MapShellDestination {
    var listDetailPath: [MapShellDestination] {
        switch self {
        case let .listDetail(listID):
            [.lists, .listDetail(listID)]
        default:
            [self]
        }
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
    let door: MapDoor
    let deepLinkDestination: MapShellDestination?
    let openScope: () -> Void
    let destination: (MapShellDestination) -> Destination

    @State private var path: [MapShellDestination] = []

    init(
        door: MapDoor,
        deepLinkDestination: MapShellDestination?,
        openScope: @escaping () -> Void,
        @ViewBuilder destination: @escaping (MapShellDestination) -> Destination
    ) {
        self.door = door
        self.deepLinkDestination = deepLinkDestination
        self.openScope = openScope
        self.destination = destination
    }

    var body: some View {
        MaterialSheet {
            NavigationStack(path: $path) {
                root
                    .navigationDestination(for: MapShellDestination.self) {
                        destination($0)
                    }
            }
        }
        .onAppear {
            applyDeepLink()
        }
        .onChange(of: deepLinkDestination) {
            applyDeepLink()
        }
    }

    @ViewBuilder
    private var root: some View {
        switch door {
        case .world:
            WorldDoorRootView(path: $path, openScope: openScope)
        case .tracks:
            TracksDoorRootView(path: $path)
        }
    }

    private func applyDeepLink() {
        path = deepLinkDestination?.listDetailPath ?? []
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

    var body: some View {
        MapDoorRootLayout(
            title: "Tracks",
            subtitle: "your story through the world"
        ) {
            MapDoorRaisedRow(
                presentation: TracksDoorRow.lists.presentation
            ) {
                path.append(.lists)
            }
            MapDoorHairlineRow(
                presentation: TracksDoorRow.myTracks.presentation
            ) {
                path.append(.tracks)
            }
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
