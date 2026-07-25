import SwiftUI

public struct MaterialToastAction {
    public let title: String
    public let accessibilityIdentifier: String?
    private let action: () -> Void

    public init(
        _ title: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
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

enum MaterialToastMessageWidth: Equatable {
    case intrinsic
    case flexible

    var usesIntrinsicWidth: Bool {
        self == .intrinsic
    }
}

struct MaterialToastRenderConfiguration: Equatable {
    let appearance: MaterialToastAppearance
    let horizontalMessageWidth: MaterialToastMessageWidth
    let fallbackMessageWidth: MaterialToastMessageWidth
    let primaryActionAccessibilityIdentifier: String?
    let dismissAccessibilityIdentifier: String?
    let surfaceAccessibilityIdentifier: String?
    let dismissMinimumTarget: CGSize
    let hasLeadingContent: Bool
    let usesCustomActionContent: Bool
    let hasSurfaceAction: Bool
    let colorScheme: ColorScheme

    var action: MaterialColor {
        appearance.action
    }
}

public struct MaterialToast: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let message: String
    private let primaryAction: MaterialToastAction?
    private let customActionAccessibilityIdentifier: String?
    private let dismissAction: (() -> Void)?
    let dismissAccessibilityLabel: String
    private let dismissAccessibilityIdentifier: String?
    private let surfaceAction: (() -> Void)?
    private let surfaceAccessibilityIdentifier: String?
    private let theme: MaterialTheme
    private let leadingContent: AnyView?
    private let customActionContent: AnyView?

    let contentMode: MaterialToastContentMode

    public init(
        message: String,
        primaryAction: MaterialToastAction? = nil,
        dismissAction: (() -> Void)? = nil,
        dismissAccessibilityLabel: String = "Dismiss",
        dismissAccessibilityIdentifier: String? = nil,
        surfaceAction: (() -> Void)? = nil,
        surfaceAccessibilityIdentifier: String? = nil,
        theme: MaterialTheme = .snow
    ) {
        self.init(
            message: message,
            primaryAction: primaryAction,
            customActionAccessibilityIdentifier: nil,
            dismissAction: dismissAction,
            dismissAccessibilityLabel: dismissAccessibilityLabel,
            dismissAccessibilityIdentifier: dismissAccessibilityIdentifier,
            surfaceAction: surfaceAction,
            surfaceAccessibilityIdentifier: surfaceAccessibilityIdentifier,
            theme: theme,
            leadingContent: nil,
            customActionContent: nil
        )
    }

    public init<LeadingContent: View>(
        message: String,
        primaryAction: MaterialToastAction? = nil,
        dismissAction: (() -> Void)? = nil,
        dismissAccessibilityLabel: String = "Dismiss",
        dismissAccessibilityIdentifier: String? = nil,
        surfaceAction: (() -> Void)? = nil,
        surfaceAccessibilityIdentifier: String? = nil,
        theme: MaterialTheme = .snow,
        @ViewBuilder leadingContent: () -> LeadingContent
    ) {
        self.init(
            message: message,
            primaryAction: primaryAction,
            customActionAccessibilityIdentifier: nil,
            dismissAction: dismissAction,
            dismissAccessibilityLabel: dismissAccessibilityLabel,
            dismissAccessibilityIdentifier: dismissAccessibilityIdentifier,
            surfaceAction: surfaceAction,
            surfaceAccessibilityIdentifier: surfaceAccessibilityIdentifier,
            theme: theme,
            leadingContent: AnyView(leadingContent()),
            customActionContent: nil
        )
    }

    public init<ActionContent: View>(
        message: String,
        primaryActionAccessibilityIdentifier: String? = nil,
        dismissAction: (() -> Void)? = nil,
        dismissAccessibilityLabel: String = "Dismiss",
        dismissAccessibilityIdentifier: String? = nil,
        surfaceAction: (() -> Void)? = nil,
        surfaceAccessibilityIdentifier: String? = nil,
        theme: MaterialTheme = .snow,
        @ViewBuilder actionContent: () -> ActionContent
    ) {
        self.init(
            message: message,
            primaryAction: nil,
            customActionAccessibilityIdentifier: primaryActionAccessibilityIdentifier,
            dismissAction: dismissAction,
            dismissAccessibilityLabel: dismissAccessibilityLabel,
            dismissAccessibilityIdentifier: dismissAccessibilityIdentifier,
            surfaceAction: surfaceAction,
            surfaceAccessibilityIdentifier: surfaceAccessibilityIdentifier,
            theme: theme,
            leadingContent: nil,
            customActionContent: AnyView(actionContent())
        )
    }

    public init<LeadingContent: View, ActionContent: View>(
        message: String,
        primaryActionAccessibilityIdentifier: String? = nil,
        dismissAction: (() -> Void)? = nil,
        dismissAccessibilityLabel: String = "Dismiss",
        dismissAccessibilityIdentifier: String? = nil,
        surfaceAction: (() -> Void)? = nil,
        surfaceAccessibilityIdentifier: String? = nil,
        theme: MaterialTheme = .snow,
        @ViewBuilder leadingContent: () -> LeadingContent,
        @ViewBuilder actionContent: () -> ActionContent
    ) {
        self.init(
            message: message,
            primaryAction: nil,
            customActionAccessibilityIdentifier: primaryActionAccessibilityIdentifier,
            dismissAction: dismissAction,
            dismissAccessibilityLabel: dismissAccessibilityLabel,
            dismissAccessibilityIdentifier: dismissAccessibilityIdentifier,
            surfaceAction: surfaceAction,
            surfaceAccessibilityIdentifier: surfaceAccessibilityIdentifier,
            theme: theme,
            leadingContent: AnyView(leadingContent()),
            customActionContent: AnyView(actionContent())
        )
    }

    private init(
        message: String,
        primaryAction: MaterialToastAction?,
        customActionAccessibilityIdentifier: String?,
        dismissAction: (() -> Void)?,
        dismissAccessibilityLabel: String,
        dismissAccessibilityIdentifier: String?,
        surfaceAction: (() -> Void)?,
        surfaceAccessibilityIdentifier: String?,
        theme: MaterialTheme,
        leadingContent: AnyView?,
        customActionContent: AnyView?
    ) {
        self.message = message
        self.primaryAction = primaryAction
        self.customActionAccessibilityIdentifier = customActionAccessibilityIdentifier
        self.dismissAction = dismissAction
        self.dismissAccessibilityLabel = dismissAccessibilityLabel
        self.dismissAccessibilityIdentifier = dismissAccessibilityIdentifier
        self.surfaceAction = surfaceAction
        self.surfaceAccessibilityIdentifier = surfaceAccessibilityIdentifier
        self.theme = theme
        self.leadingContent = leadingContent
        self.customActionContent = customActionContent

        let hasAction = primaryAction != nil || customActionContent != nil
        switch (hasAction, dismissAction != nil) {
        case (false, false):
            contentMode = .messageOnly
        case (true, false):
            contentMode = .messageAndAction
        case (false, true):
            contentMode = .messageAndDismiss
        case (true, true):
            contentMode = .messageActionAndDismiss
        }
    }

    public var body: some View {
        let configuration = renderConfiguration(
            reduceTransparency: reduceTransparency
        )

        if let surfaceAction {
            decoratedToast(configuration: configuration)
                .contentShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .onTapGesture(perform: surfaceAction)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    surfaceAction()
                }
                .materialAccessibilityIdentifier(
                    configuration.surfaceAccessibilityIdentifier
                )
        } else {
            decoratedToast(configuration: configuration)
                .materialAccessibilityIdentifier(
                    configuration.surfaceAccessibilityIdentifier
                )
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

    func renderConfiguration(
        reduceTransparency: Bool
    ) -> MaterialToastRenderConfiguration {
        MaterialToastRenderConfiguration(
            appearance: appearance(reduceTransparency: reduceTransparency),
            horizontalMessageWidth: .intrinsic,
            fallbackMessageWidth: .flexible,
            primaryActionAccessibilityIdentifier:
                primaryAction?.accessibilityIdentifier
                ?? customActionAccessibilityIdentifier,
            dismissAccessibilityIdentifier: dismissAccessibilityIdentifier,
            surfaceAccessibilityIdentifier: surfaceAccessibilityIdentifier,
            dismissMinimumTarget: CGSize(width: 44, height: 44),
            hasLeadingContent: leadingContent != nil,
            usesCustomActionContent: customActionContent != nil,
            hasSurfaceAction: surfaceAction != nil,
            colorScheme: .light
        )
    }

    func performSurfaceAction() {
        surfaceAction?()
    }

    private func decoratedToast(
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        toastContent(configuration: configuration)
            .padding(12)
            .foregroundStyle(configuration.appearance.foreground.swiftUIColor)
            .background {
                switch configuration.appearance.backdrop {
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
                    .stroke(configuration.appearance.stroke.swiftUIColor, lineWidth: 1)
            }
            .environment(\.colorScheme, configuration.colorScheme)
    }

    @ViewBuilder
    private func toastContent(
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                messageAndActions(
                    messageWidth: configuration.horizontalMessageWidth,
                    configuration: configuration
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                messageAndActions(
                    messageWidth: configuration.fallbackMessageWidth,
                    configuration: configuration
                )
            }
        }
    }

    @ViewBuilder
    private func messageAndActions(
        messageWidth: MaterialToastMessageWidth,
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        if let leadingContent {
            leadingContent
        }

        switch contentMode {
        case .messageOnly:
            messageView(width: messageWidth)
        case .messageAndAction:
            messageView(width: messageWidth)
            primaryActionView(configuration: configuration)
        case .messageAndDismiss:
            messageView(width: messageWidth)
            dismissActionView(configuration: configuration)
        case .messageActionAndDismiss:
            messageView(width: messageWidth)
            primaryActionView(configuration: configuration)
            dismissActionView(configuration: configuration)
        }
    }

    private func messageView(
        width: MaterialToastMessageWidth
    ) -> some View {
        // Typography remains inherited until T1.2 provides the role API.
        Text(verbatim: message)
            .fixedSize(
                horizontal: width.usesIntrinsicWidth,
                vertical: true
            )
    }

    @ViewBuilder
    private func primaryActionView(
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        if let customActionContent {
            customActionContent
                .materialAccessibilityIdentifier(
                    configuration.primaryActionAccessibilityIdentifier
                )
        } else if let primaryAction {
            Button(primaryAction.title, action: primaryAction.perform)
                .foregroundStyle(configuration.action.swiftUIColor)
                .buttonStyle(.plain)
                .materialAccessibilityIdentifier(
                    configuration.primaryActionAccessibilityIdentifier
                )
        }
    }

    @ViewBuilder
    private func dismissActionView(
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        if let dismissAction {
            MaterialToastDismissButton(
                action: dismissAction,
                accessibilityLabel: dismissAccessibilityLabel,
                accessibilityIdentifier:
                    configuration.dismissAccessibilityIdentifier,
                minimumTarget: configuration.dismissMinimumTarget
            )
        }
    }
}

struct MaterialToastDismissButton: View {
    let action: () -> Void
    let accessibilityLabel: String
    let accessibilityIdentifier: String?
    let minimumTarget: CGSize

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .frame(
                    minWidth: minimumTarget.width,
                    minHeight: minimumTarget.height
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibilityLabel)
        .buttonStyle(.plain)
        .materialAccessibilityIdentifier(accessibilityIdentifier)
    }
}

private extension View {
    @ViewBuilder
    func materialAccessibilityIdentifier(
        _ accessibilityIdentifier: String?
    ) -> some View {
        if let accessibilityIdentifier {
            self.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            self
        }
    }
}
