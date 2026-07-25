import SwiftUI

enum MaterialSheetBackground: Equatable {
    case solid(MaterialColor)

    var color: MaterialColor {
        switch self {
        case let .solid(color): color
        }
    }
}

enum MaterialSheetDetent: Equatable {
    case medium
    case large

    var presentationDetent: PresentationDetent {
        switch self {
        case .medium: .medium
        case .large: .large
        }
    }
}

struct MaterialSheetAppearance: Equatable {
    let background: MaterialSheetBackground
    let grabberColor: MaterialColor
    let topCornerRadius: CGFloat
    let detents: [MaterialSheetDetent]
    let closeAccessibilityLabel: String
}

struct MaterialRowAppearance: Equatable {
    let background: MaterialColor?
    let cornerRadius: CGFloat?
    let divider: MaterialColor?
}

public struct MaterialSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    private let content: Content
    let appearance: MaterialSheetAppearance

    public init(
        theme: MaterialTheme = .snow,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        appearance = MaterialSheetAppearance(
            background: .solid(theme.tokens.surface),
            grabberColor: theme.tokens.hairline,
            topCornerRadius: 22,
            detents: [.medium, .large],
            closeAccessibilityLabel: "Close"
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(appearance.grabberColor.swiftUIColor)
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            HStack {
                Spacer()
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(appearance.closeAccessibilityLabel)
                .padding()
            }

            content
        }
        .presentationDetents(Set(appearance.detents.map(\.presentationDetent)))
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(appearance.topCornerRadius)
        .presentationBackground(appearance.background.color.swiftUIColor)
    }
}

public struct MaterialRaisedCardRow<Content: View>: View {
    private let content: Content
    let appearance: MaterialRowAppearance

    public init(
        theme: MaterialTheme = .snow,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        appearance = MaterialRowAppearance(
            background: theme.tokens.surfaceRaised,
            cornerRadius: 14,
            divider: nil
        )
    }

    public var body: some View {
        content
            .padding()
            .background(
                appearance.background!.swiftUIColor,
                in: RoundedRectangle(cornerRadius: appearance.cornerRadius!)
            )
    }
}

public struct MaterialHairlineRow<Content: View>: View {
    private let content: Content
    let appearance: MaterialRowAppearance

    public init(
        theme: MaterialTheme = .snow,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        appearance = MaterialRowAppearance(
            background: nil,
            cornerRadius: nil,
            divider: theme.tokens.hairline
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            content.padding()
            Divider().overlay(appearance.divider!.swiftUIColor)
        }
    }
}
