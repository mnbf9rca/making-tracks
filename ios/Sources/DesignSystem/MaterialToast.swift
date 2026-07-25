import SwiftUI

public struct MaterialToastAction {
    public let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public func perform() {
        action()
    }
}

enum MaterialToastContentMode: Equatable {
    case messageOnly
    case messageAndAction
    case messageAndDismiss
    case messageActionAndDismiss
}

enum MaterialToastBackdrop: Equatable {
    case regularMaterial
    case solid(MaterialColor)
}

struct MaterialToastAppearance: Equatable {
    let foreground: MaterialColor
    let action: MaterialColor
    let stroke: MaterialColor
    let backdrop: MaterialToastBackdrop
}

public struct MaterialToast: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let message: String
    private let primaryAction: MaterialToastAction?
    private let dismissAction: (() -> Void)?
    let dismissAccessibilityLabel: String
    private let theme: MaterialTheme

    let contentMode: MaterialToastContentMode

    public init(
        message: String,
        primaryAction: MaterialToastAction? = nil,
        dismissAction: (() -> Void)? = nil,
        dismissAccessibilityLabel: String = "Dismiss",
        theme: MaterialTheme = .snow
    ) {
        self.message = message
        self.primaryAction = primaryAction
        self.dismissAction = dismissAction
        self.dismissAccessibilityLabel = dismissAccessibilityLabel
        self.theme = theme

        switch (primaryAction, dismissAction) {
        case (nil, nil):
            contentMode = .messageOnly
        case (.some, nil):
            contentMode = .messageAndAction
        case (nil, .some):
            contentMode = .messageAndDismiss
        case (.some, .some):
            contentMode = .messageActionAndDismiss
        }
    }

    public var body: some View {
        let appearance = appearance(reduceTransparency: reduceTransparency)

        toastContent
            .padding(12)
            .foregroundStyle(appearance.foreground.swiftUIColor)
            .background {
                switch appearance.backdrop {
                case .regularMaterial:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                case let .solid(color):
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(color.swiftUIColor)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(appearance.stroke.swiftUIColor, lineWidth: 1)
            }
    }

    func appearance(reduceTransparency: Bool) -> MaterialToastAppearance {
        MaterialToastAppearance(
            foreground: theme.tokens.ink,
            action: theme.tokens.accent,
            stroke: theme.tokens.hairline,
            backdrop: reduceTransparency ? .solid(theme.tokens.surface) : .regularMaterial
        )
    }

    @ViewBuilder
    private var toastContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                messageAndActions
            }

            VStack(alignment: .leading, spacing: 12) {
                messageAndActions
            }
        }
    }

    @ViewBuilder
    private var messageAndActions: some View {
        Text(verbatim: message)
            .fixedSize(horizontal: false, vertical: true)

        if let primaryAction {
            Button(primaryAction.title, action: primaryAction.perform)
                .foregroundStyle(theme.tokens.accent.swiftUIColor)
                .buttonStyle(.plain)
        }

        if let dismissAction {
            Button(action: dismissAction) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(dismissAccessibilityLabel)
            .buttonStyle(.plain)
        }
    }
}
