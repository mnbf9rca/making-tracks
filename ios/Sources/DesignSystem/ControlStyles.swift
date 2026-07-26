import SwiftUI

struct MaterialControlAppearance: Equatable, Sendable {
    let foreground: MaterialColor
    let background: MaterialColor?
    let backgroundOpacity: Double

    static func filled(tokens: MaterialTokenSheet) -> MaterialControlAppearance {
        MaterialControlAppearance(
            foreground: tokens.accentContrast,
            background: tokens.accent,
            backgroundOpacity: 1
        )
    }

    static func tonal(tokens: MaterialTokenSheet) -> MaterialControlAppearance {
        MaterialControlAppearance(
            foreground: tokens.accent,
            background: tokens.accent,
            backgroundOpacity: 0.12
        )
    }

    static func quiet(tokens: MaterialTokenSheet) -> MaterialControlAppearance {
        MaterialControlAppearance(
            foreground: tokens.muted,
            background: nil,
            backgroundOpacity: 0
        )
    }
}

/// The accent-filled primary action. Adopting screens keep at most one visible.
///
/// Use a SwiftUI `Label` when an action has an icon so the style can apply the
/// module's monochrome, medium-weight SF Symbol convention. Icon-only buttons
/// remain responsible for an explicit accessibility label at the call site.
public struct MaterialFilledButtonStyle: ButtonStyle {
    private let theme: MaterialTheme

    public init(theme: MaterialTheme = .snow) {
        self.theme = theme
    }

    var appearance: MaterialControlAppearance {
        .filled(tokens: theme.tokens)
    }

    func accessibilityValue(isEnabled: Bool) -> String? {
        isEnabled ? nil : "Unavailable"
    }

    public func makeBody(configuration: Configuration) -> some View {
        MaterialButtonStyleBody(
            configuration: configuration,
            appearance: appearance,
            accessibilityValue: accessibilityValue
        )
    }
}

/// The 12%-accent secondary action for controls that are available but inactive.
public struct MaterialTonalButtonStyle: ButtonStyle {
    private let theme: MaterialTheme

    public init(theme: MaterialTheme = .snow) {
        self.theme = theme
    }

    var appearance: MaterialControlAppearance {
        .tonal(tokens: theme.tokens)
    }

    func accessibilityValue(isEnabled: Bool) -> String? {
        isEnabled ? nil : "Unavailable"
    }

    public func makeBody(configuration: Configuration) -> some View {
        MaterialButtonStyleBody(
            configuration: configuration,
            appearance: appearance,
            accessibilityValue: accessibilityValue
        )
    }
}

/// The muted, background-free action for controls that should visually recede.
public struct MaterialQuietButtonStyle: ButtonStyle {
    private let theme: MaterialTheme

    public init(theme: MaterialTheme = .snow) {
        self.theme = theme
    }

    var appearance: MaterialControlAppearance {
        .quiet(tokens: theme.tokens)
    }

    func accessibilityValue(isEnabled: Bool) -> String? {
        isEnabled ? nil : "Unavailable"
    }

    public func makeBody(configuration: Configuration) -> some View {
        MaterialButtonStyleBody(
            configuration: configuration,
            appearance: appearance,
            accessibilityValue: accessibilityValue
        )
    }
}

/// The complete chip state vocabulary: filled when active, tonal when available.
public enum MaterialChipState: Hashable, Sendable {
    case active
    case available

    var style: MaterialChipStyle {
        switch self {
        case .active:
            .filled
        case .available:
            .tonal
        }
    }

    var appearance: MaterialControlAppearance {
        appearance(theme: .snow)
    }

    func appearance(theme: MaterialTheme) -> MaterialControlAppearance {
        style.appearance(theme: theme)
    }

    func accessibilityValue(isEnabled: Bool) -> String {
        guard isEnabled else {
            return "Unavailable"
        }

        switch self {
        case .active:
            return "Selected"
        case .available:
            return "Not selected"
        }
    }
}

/// A token-backed capsule control with explicit selected and disabled semantics.
///
/// `systemImage` accepts an SF Symbol name; arbitrary image content is
/// intentionally outside the family.
public struct MaterialChip: View {
    @Environment(\.isEnabled) private var isEnabled

    private let title: String
    private let systemImage: String?
    private let state: MaterialChipState
    private let theme: MaterialTheme
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        state: MaterialChipState,
        theme: MaterialTheme = .snow,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.state = state
        self.theme = theme
        self.action = action
    }

    public var body: some View {
        styledButton
    }

    @ViewBuilder
    private var styledButton: some View {
        let button = Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Typography.font(for: .label).weight(.medium))
                        .symbolRenderingMode(.monochrome)
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
                    .font(Typography.font(for: .label))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(
            Text(verbatim: state.accessibilityValue(isEnabled: isEnabled))
        )

        switch state.style {
        case .filled:
            button.buttonStyle(MaterialFilledButtonStyle(theme: theme))
        case .tonal:
            button.buttonStyle(MaterialTonalButtonStyle(theme: theme))
        }
    }
}

enum MaterialChipStyle: Equatable, Sendable {
    case filled
    case tonal

    func appearance(theme: MaterialTheme) -> MaterialControlAppearance {
        switch self {
        case .filled:
            .filled(tokens: theme.tokens)
        case .tonal:
            .tonal(tokens: theme.tokens)
        }
    }
}

private struct MaterialButtonStyleBody: View {
    let configuration: ButtonStyle.Configuration
    let appearance: MaterialControlAppearance
    let accessibilityValue: (Bool) -> String?

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .labelStyle(MaterialControlLabelStyle())
            .font(Typography.font(for: .button))
            .foregroundStyle(appearance.foreground.swiftUIColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(backgroundStyle, in: Capsule())
            .contentShape(Capsule())
            .opacity(controlOpacity)
            .modifier(
                OptionalAccessibilityValue(
                    value: accessibilityValue(isEnabled)
                )
            )
    }

    private var backgroundStyle: AnyShapeStyle {
        guard let background = appearance.background else {
            return AnyShapeStyle(Color.clear)
        }
        return AnyShapeStyle(
            background.swiftUIColor.opacity(appearance.backgroundOpacity)
        )
    }

    private var controlOpacity: Double {
        guard isEnabled else {
            return 0.46
        }
        return configuration.isPressed ? 0.78 : 1
    }
}

private struct MaterialControlLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.body.weight(.medium))
                .symbolRenderingMode(.monochrome)
            configuration.title
                .font(Typography.font(for: .button))
        }
    }
}

private struct OptionalAccessibilityValue: ViewModifier {
    let value: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(Text(verbatim: value))
        } else {
            content
        }
    }
}
