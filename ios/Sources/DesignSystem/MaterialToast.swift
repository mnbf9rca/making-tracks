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

public struct MaterialToastSurfaceAction {
    public let accessibilityLabel: String
    public let accessibilityHint: String
    public let accessibilityIdentifier: String
    private let action: () -> Void

    public init(
        accessibilityLabel: String,
        accessibilityHint: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
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

struct MaterialToastControlConfiguration: Equatable {
    let primaryActionAccessibilityIdentifier: String?
    let dismissAccessibilityIdentifier: String?
    let minimumInteractiveTarget: CGSize
    let hasLeadingContent: Bool
    let usesCustomActionContent: Bool
}

struct MaterialToastSurfaceConfiguration: Equatable {
    let accessibilityLabel: String
    let accessibilityHint: String
    let accessibilityIdentifier: String
    let accessibilityValue: String?
    let leadingSystemImage: String?
    let progressState: MaterialProgressState?
}

enum MaterialToastInteractionConfiguration: Equatable {
    case controls(MaterialToastControlConfiguration)
    case surface(MaterialToastSurfaceConfiguration)
}

struct MaterialToastRenderConfiguration: Equatable {
    let appearance: MaterialToastAppearance
    let horizontalMessageWidth: MaterialToastMessageWidth
    let fallbackMessageWidth: MaterialToastMessageWidth
    let interaction: MaterialToastInteractionConfiguration
    let colorScheme: ColorScheme

    var action: MaterialColor {
        appearance.action
    }
}

private struct MaterialToastControlContent {
    let primaryAction: MaterialToastAction?
    let customActionAccessibilityIdentifier: String?
    let dismissAction: (() -> Void)?
    let dismissAccessibilityLabel: String
    let dismissAccessibilityIdentifier: String?
    let accessibilityIdentifier: String?
    let leadingContent: AnyView?
    let customActionContent: AnyView?
}

private struct MaterialToastSurfaceContent {
    let action: MaterialToastSurfaceAction
    let leadingSystemImage: String?
    let progressState: MaterialProgressState?
}

private enum MaterialToastInteraction {
    case controls(MaterialToastControlContent)
    case surface(MaterialToastSurfaceContent)
}

public struct MaterialToast: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let message: String
    private let theme: MaterialTheme
    private let interaction: MaterialToastInteraction

    let contentMode: MaterialToastContentMode

    var dismissAccessibilityLabel: String {
        switch interaction {
        case let .controls(content):
            content.dismissAccessibilityLabel
        case .surface:
            "Dismiss"
        }
    }

    public init(
        message: String,
        primaryAction: MaterialToastAction? = nil,
        dismissAction: (() -> Void)? = nil,
        dismissAccessibilityLabel: String = "Dismiss",
        dismissAccessibilityIdentifier: String? = nil,
        accessibilityIdentifier: String? = nil,
        theme: MaterialTheme = .snow
    ) {
        let content = MaterialToastControlContent(
            primaryAction: primaryAction,
            customActionAccessibilityIdentifier: nil,
            dismissAction: dismissAction,
            dismissAccessibilityLabel: dismissAccessibilityLabel,
            dismissAccessibilityIdentifier: dismissAccessibilityIdentifier,
            accessibilityIdentifier: accessibilityIdentifier,
            leadingContent: nil,
            customActionContent: nil
        )
        self.init(message: message, theme: theme, controlContent: content)
    }

    public init<LeadingContent: View>(
        message: String,
        primaryAction: MaterialToastAction? = nil,
        dismissAction: (() -> Void)? = nil,
        dismissAccessibilityLabel: String = "Dismiss",
        dismissAccessibilityIdentifier: String? = nil,
        accessibilityIdentifier: String? = nil,
        theme: MaterialTheme = .snow,
        @ViewBuilder leadingContent: () -> LeadingContent
    ) {
        let content = MaterialToastControlContent(
            primaryAction: primaryAction,
            customActionAccessibilityIdentifier: nil,
            dismissAction: dismissAction,
            dismissAccessibilityLabel: dismissAccessibilityLabel,
            dismissAccessibilityIdentifier: dismissAccessibilityIdentifier,
            accessibilityIdentifier: accessibilityIdentifier,
            leadingContent: AnyView(leadingContent()),
            customActionContent: nil
        )
        self.init(message: message, theme: theme, controlContent: content)
    }

    /// Creates a toast with caller-supplied interactive action content.
    ///
    /// The supplied control must preserve its own interaction semantics and
    /// provide a minimum 44×44 point hit target. The adopting surface owns
    /// proving that target for its concrete control.
    public init<ActionContent: View>(
        message: String,
        primaryActionAccessibilityIdentifier: String? = nil,
        dismissAction: (() -> Void)? = nil,
        dismissAccessibilityLabel: String = "Dismiss",
        dismissAccessibilityIdentifier: String? = nil,
        accessibilityIdentifier: String? = nil,
        theme: MaterialTheme = .snow,
        @ViewBuilder actionContent: () -> ActionContent
    ) {
        let content = MaterialToastControlContent(
            primaryAction: nil,
            customActionAccessibilityIdentifier: primaryActionAccessibilityIdentifier,
            dismissAction: dismissAction,
            dismissAccessibilityLabel: dismissAccessibilityLabel,
            dismissAccessibilityIdentifier: dismissAccessibilityIdentifier,
            accessibilityIdentifier: accessibilityIdentifier,
            leadingContent: nil,
            customActionContent: AnyView(actionContent())
        )
        self.init(message: message, theme: theme, controlContent: content)
    }

    /// Creates a toast with leading content and a caller-supplied interactive action.
    ///
    /// The supplied control must preserve its own interaction semantics and
    /// provide a minimum 44×44 point hit target. The adopting surface owns
    /// proving that target for its concrete control.
    public init<LeadingContent: View, ActionContent: View>(
        message: String,
        primaryActionAccessibilityIdentifier: String? = nil,
        dismissAction: (() -> Void)? = nil,
        dismissAccessibilityLabel: String = "Dismiss",
        dismissAccessibilityIdentifier: String? = nil,
        accessibilityIdentifier: String? = nil,
        theme: MaterialTheme = .snow,
        @ViewBuilder leadingContent: () -> LeadingContent,
        @ViewBuilder actionContent: () -> ActionContent
    ) {
        let content = MaterialToastControlContent(
            primaryAction: nil,
            customActionAccessibilityIdentifier: primaryActionAccessibilityIdentifier,
            dismissAction: dismissAction,
            dismissAccessibilityLabel: dismissAccessibilityLabel,
            dismissAccessibilityIdentifier: dismissAccessibilityIdentifier,
            accessibilityIdentifier: accessibilityIdentifier,
            leadingContent: AnyView(leadingContent()),
            customActionContent: AnyView(actionContent())
        )
        self.init(message: message, theme: theme, controlContent: content)
    }

    public init(
        message: String,
        surfaceAction: MaterialToastSurfaceAction,
        leadingSystemImage: String? = nil,
        progressState: MaterialProgressState? = nil,
        theme: MaterialTheme = .snow
    ) {
        self.message = message
        self.theme = theme
        interaction = .surface(
            MaterialToastSurfaceContent(
                action: surfaceAction,
                leadingSystemImage: leadingSystemImage,
                progressState: progressState
            )
        )
        contentMode = .messageOnly
    }

    private init(
        message: String,
        theme: MaterialTheme,
        controlContent: MaterialToastControlContent
    ) {
        self.message = message
        self.theme = theme
        interaction = .controls(controlContent)

        let hasAction =
            controlContent.primaryAction != nil
            || controlContent.customActionContent != nil
        switch (hasAction, controlContent.dismissAction != nil) {
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

        switch interaction {
        case let .controls(content):
            decoratedToast(configuration: configuration) {
                controlToastContent(
                    content: content,
                    configuration: configuration
                )
            }
            .materialAccessibilityIdentifier(content.accessibilityIdentifier)
        case let .surface(content):
            if case let .surface(surfaceConfiguration) =
                configuration.interaction {
                Button(action: content.action.perform) {
                    decoratedToast(
                        configuration: configuration,
                        minimumWidth: 44,
                        minimumHeight: 44
                    ) {
                        surfaceToastContent(
                            content: content,
                            configuration: configuration
                        )
                    }
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    surfaceConfiguration.accessibilityLabel
                )
                .accessibilityHint(
                    surfaceConfiguration.accessibilityHint
                )
                .accessibilityIdentifier(
                    surfaceConfiguration.accessibilityIdentifier
                )
                .materialAccessibilityValue(
                    surfaceConfiguration.accessibilityValue
                )
            }
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
        let interactionConfiguration: MaterialToastInteractionConfiguration

        switch interaction {
        case let .controls(content):
            interactionConfiguration = .controls(
                MaterialToastControlConfiguration(
                    primaryActionAccessibilityIdentifier:
                        content.primaryAction?.accessibilityIdentifier
                        ?? content.customActionAccessibilityIdentifier,
                    dismissAccessibilityIdentifier:
                        content.dismissAccessibilityIdentifier,
                    minimumInteractiveTarget: CGSize(width: 44, height: 44),
                    hasLeadingContent: content.leadingContent != nil,
                    usesCustomActionContent:
                        content.customActionContent != nil
                )
            )
        case let .surface(content):
            interactionConfiguration = .surface(
                MaterialToastSurfaceConfiguration(
                    accessibilityLabel: content.action.accessibilityLabel,
                    accessibilityHint: content.action.accessibilityHint,
                    accessibilityIdentifier:
                        content.action.accessibilityIdentifier,
                    accessibilityValue:
                        content.progressState?
                            .presentation.accessibilityValue,
                    leadingSystemImage: content.leadingSystemImage,
                    progressState: content.progressState
                )
            )
        }

        return MaterialToastRenderConfiguration(
            appearance: appearance(reduceTransparency: reduceTransparency),
            horizontalMessageWidth: .intrinsic,
            fallbackMessageWidth: .flexible,
            interaction: interactionConfiguration,
            colorScheme: theme.colorScheme
        )
    }

    private func decoratedToast<Content: View>(
        configuration: MaterialToastRenderConfiguration,
        minimumWidth: CGFloat? = nil,
        minimumHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(12)
            .frame(
                minWidth: minimumWidth,
                minHeight: minimumHeight
            )
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

    private func controlToastContent(
        content: MaterialToastControlContent,
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                controlMessageAndActions(
                    content: content,
                    messageWidth: configuration.horizontalMessageWidth,
                    configuration: configuration
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                controlMessageAndActions(
                    content: content,
                    messageWidth: configuration.fallbackMessageWidth,
                    configuration: configuration
                )
            }
        }
    }

    @ViewBuilder
    private func controlMessageAndActions(
        content: MaterialToastControlContent,
        messageWidth: MaterialToastMessageWidth,
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        if let leadingContent = content.leadingContent {
            leadingContent
        }

        switch contentMode {
        case .messageOnly:
            messageView(width: messageWidth)
        case .messageAndAction:
            messageView(width: messageWidth)
            primaryActionView(
                content: content,
                configuration: configuration
            )
        case .messageAndDismiss:
            messageView(width: messageWidth)
            dismissActionView(
                content: content,
                configuration: configuration
            )
        case .messageActionAndDismiss:
            messageView(width: messageWidth)
            primaryActionView(
                content: content,
                configuration: configuration
            )
            dismissActionView(
                content: content,
                configuration: configuration
            )
        }
    }

    private func surfaceToastContent(
        content: MaterialToastSurfaceContent,
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                surfaceMessageAndProgress(
                    content: content,
                    messageWidth: configuration.horizontalMessageWidth
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                surfaceMessageAndProgress(
                    content: content,
                    messageWidth: configuration.fallbackMessageWidth
                )
            }
        }
    }

    @ViewBuilder
    private func surfaceMessageAndProgress(
        content: MaterialToastSurfaceContent,
        messageWidth: MaterialToastMessageWidth
    ) -> some View {
        if let leadingSystemImage = content.leadingSystemImage {
            Image(systemName: leadingSystemImage)
        }

        messageView(width: messageWidth)

        if let progressState = content.progressState {
            MaterialProgress(state: progressState, theme: theme)
        }
    }

    private func messageView(
        width: MaterialToastMessageWidth
    ) -> some View {
        Text(verbatim: message)
            .font(Typography.font(for: .body))
            .fixedSize(
                horizontal: width.usesIntrinsicWidth,
                vertical: true
            )
    }

    @ViewBuilder
    private func primaryActionView(
        content: MaterialToastControlContent,
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        if case let .controls(controlConfiguration) =
            configuration.interaction {
            if let customActionContent = content.customActionContent {
                customActionContent
                    .materialAccessibilityIdentifier(
                        controlConfiguration
                            .primaryActionAccessibilityIdentifier
                    )
            } else if let primaryAction = content.primaryAction {
                MaterialToastPrimaryActionButton(
                    action: primaryAction,
                    foreground: configuration.action,
                    minimumTarget:
                        controlConfiguration.minimumInteractiveTarget
                )
            }
        }
    }

    @ViewBuilder
    private func dismissActionView(
        content: MaterialToastControlContent,
        configuration: MaterialToastRenderConfiguration
    ) -> some View {
        if
            let dismissAction = content.dismissAction,
            case let .controls(controlConfiguration) =
                configuration.interaction
        {
            MaterialToastDismissButton(
                action: dismissAction,
                accessibilityLabel: content.dismissAccessibilityLabel,
                accessibilityIdentifier:
                    controlConfiguration.dismissAccessibilityIdentifier,
                minimumTarget:
                    controlConfiguration.minimumInteractiveTarget
            )
        }
    }
}

struct MaterialToastPrimaryActionButton: View {
    let action: MaterialToastAction
    let foreground: MaterialColor
    let minimumTarget: CGSize

    var body: some View {
        Button(action: action.perform) {
            Text(verbatim: action.title)
                .font(Typography.font(for: .button))
                .frame(
                    minWidth: minimumTarget.width,
                    minHeight: minimumTarget.height
                )
                .contentShape(Rectangle())
        }
        .foregroundStyle(foreground.swiftUIColor)
        .buttonStyle(.plain)
        .materialAccessibilityIdentifier(action.accessibilityIdentifier)
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
    func materialAccessibilityValue(
        _ accessibilityValue: String?
    ) -> some View {
        if let accessibilityValue {
            self.accessibilityValue(accessibilityValue)
        } else {
            self
        }
    }

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
