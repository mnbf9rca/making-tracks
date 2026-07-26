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
///
/// The interaction shape expands each axis only when needed to reach the
/// 44pt free-space minimum. Layouts that tile reversible, distinct actions
/// supply their nonnegative neighbor gap so interaction cells fill that gap
/// without overlapping. The gap changes hit testing only, never visuals.
public struct MaterialChip: View {
    /// `ia-doors.html` ratifies 12pt/600, which no `TypographyRole` expresses.
    static let titleFont = Font.caption.weight(.semibold)
    static let iconFont =
        Typography.font(for: .label).weight(.medium)

    @Environment(\.isEnabled) private var isEnabled

    private let title: String
    private let systemImage: String?
    private let state: MaterialChipState
    private let theme: MaterialTheme
    private let neighborGap: CGFloat?
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        state: MaterialChipState,
        theme: MaterialTheme = .snow,
        neighborGap: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.state = state
        self.theme = theme
        self.neighborGap = neighborGap
        self.action = action
    }

    public var body: some View {
        styledButton
    }

    @ViewBuilder
    private var styledButton: some View {
        let button = Button(action: action) {
            HStack(spacing: MaterialChipGeometry.labelSpacing) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Self.iconFont)
                        .symbolRenderingMode(.monochrome)
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
                    .font(Self.titleFont)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(
            Text(verbatim: state.accessibilityValue(isEnabled: isEnabled))
        )

        switch state.style {
        case .filled:
            button.buttonStyle(MaterialChipButtonStyle(
                appearance: .filled(tokens: theme.tokens)
            ))
            .contentShape(
                .interaction,
                MaterialChipHitTargetShape(neighborGap: neighborGap)
            )
        case .tonal:
            button.buttonStyle(MaterialChipButtonStyle(
                appearance: .tonal(tokens: theme.tokens)
            ))
            .contentShape(
                .interaction,
                MaterialChipHitTargetShape(neighborGap: neighborGap)
            )
        }
    }
}

/// Public chip metrics for layouts that need to calculate row and column pitch.
public enum MaterialChipGeometry {
    public static let visualHeight: CGFloat = 22
    public static let horizontalPadding: CGFloat = 9
    public static let labelSpacing: CGFloat = 4
    public static let minimumHitTarget: CGFloat = 44

    /// Returns the free-space expansion for `dimension`, or half the supplied
    /// gap capped at the 11pt free-space maximum for a tiled interaction cell.
    public static func hitOutset(
        for dimension: CGFloat,
        neighborGap: CGFloat? = nil
    ) -> CGFloat {
        let freeSpaceOutset = max(
            0,
            (minimumHitTarget - dimension) / 2
        )
        guard let neighborGap else {
            return freeSpaceOutset
        }
        let maximumTiledOutset = max(
            0,
            (minimumHitTarget - visualHeight) / 2
        )
        return min(maximumTiledOutset, neighborGap / 2)
    }
}

struct MaterialChipHitTargetShape: Shape {
    let neighborGap: CGFloat?

    func path(in rect: CGRect) -> Path {
        let horizontalOutset = MaterialChipGeometry.hitOutset(
            for: rect.width,
            neighborGap: neighborGap
        )
        let verticalOutset = MaterialChipGeometry.hitOutset(
            for: rect.height,
            neighborGap: neighborGap
        )
        let targetRect = rect.insetBy(
            dx: -horizontalOutset,
            dy: -verticalOutset
        )
        if neighborGap == nil {
            return Capsule().path(in: targetRect)
        }
        return Rectangle().path(in: targetRect)
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

private struct MaterialChipButtonStyle: ButtonStyle {
    let appearance: MaterialControlAppearance

    func makeBody(configuration: Configuration) -> some View {
        MaterialChipStyleBody(
            configuration: configuration,
            appearance: appearance
        )
    }
}

private struct MaterialChipStyleBody: View {
    let configuration: ButtonStyle.Configuration
    let appearance: MaterialControlAppearance

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(appearance.foreground.swiftUIColor)
            .padding(.horizontal, MaterialChipGeometry.horizontalPadding)
            .frame(minHeight: MaterialChipGeometry.visualHeight)
            .background(backgroundStyle, in: Capsule())
            .opacity(controlOpacity)
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
