import DesignSystem
import SwiftUI

struct MapDoorPresentation: Equatable {
    let title: String
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
