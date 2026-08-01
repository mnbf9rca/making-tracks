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
            backgroundOpacity: tokens.tonalContainerCompositeOpacity
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

enum MaterialControlInteractionFeedback {
    static func semanticControlOpacity(
        isEnabled: Bool,
        tokens: MaterialTokenSheet
    ) -> Double {
        isEnabled ? 1 : tokens.disabledAlpha
    }

    static func semanticControlScale(
        isPressed: Bool,
        tokens: MaterialTokenSheet
    ) -> CGFloat {
        isPressed ? tokens.pressScale : 1
    }
}

enum MaterialControlDisabledAppearance {
    case dim
    case preserveSemanticState

    func opacity(
        isEnabled: Bool,
        tokens: MaterialTokenSheet
    ) -> Double {
        switch self {
        case .dim:
            MaterialControlInteractionFeedback.semanticControlOpacity(
                isEnabled: isEnabled,
                tokens: tokens
            )
        case .preserveSemanticState:
            1
        }
    }
}

enum MaterialControlPressFeedback: Equatable, Sendable {
    case scale
    case symbolWeightPulse
    case textInset(points: CGFloat)

    static let textInsetTypographyAnchor =
        TypographyRole.button.specification.textStyle

    func scale(isPressed: Bool, tokens: MaterialTokenSheet) -> CGFloat {
        MaterialControlInteractionFeedback.semanticControlScale(
            isPressed: isPressed,
            tokens: tokens
        )
    }

    func symbolWeight(isPressed: Bool) -> MaterialControlSymbolWeight {
        switch self {
        case .scale:
            .standard
        case .symbolWeightPulse:
            isPressed ? .emphasized : .standard
        case .textInset:
            .standard
        }
    }

    var textInsetBasePoints: CGFloat {
        switch self {
        case let .textInset(points):
            points
        case .scale, .symbolWeightPulse:
            0
        }
    }

    func verticalOffset(
        isPressed: Bool,
        isEnabled: Bool,
        scaledTextInsetPoints: CGFloat
    ) -> CGFloat {
        guard isPressed, isEnabled else {
            return 0
        }
        return switch self {
        case .textInset:
            scaledTextInsetPoints
        case .scale, .symbolWeightPulse:
            0
        }
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

    var pressFeedback: MaterialControlPressFeedback {
        .scale
    }

    func accessibilityValue(isEnabled: Bool) -> String? {
        isEnabled ? nil : "Unavailable"
    }

    public func makeBody(configuration: Configuration) -> some View {
        MaterialButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            appearance: appearance,
            tokens: theme.tokens,
            pressFeedback: pressFeedback,
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

    var pressFeedback: MaterialControlPressFeedback {
        .scale
    }

    func accessibilityValue(isEnabled: Bool) -> String? {
        isEnabled ? nil : "Unavailable"
    }

    public func makeBody(configuration: Configuration) -> some View {
        MaterialButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            appearance: appearance,
            tokens: theme.tokens,
            pressFeedback: pressFeedback,
            accessibilityValue: accessibilityValue
        )
    }
}

/// The muted, background-free action for controls that should visually recede.
public struct MaterialQuietButtonStyle: ButtonStyle {
    private let theme: MaterialTheme
    let pressFeedback: MaterialControlPressFeedback

    public init(theme: MaterialTheme = .snow) {
        self.init(theme: theme, pressFeedback: .symbolWeightPulse)
    }

    private init(
        theme: MaterialTheme,
        pressFeedback: MaterialControlPressFeedback
    ) {
        self.theme = theme
        self.pressFeedback = pressFeedback
    }

    /// The text-only quiet variant ruled by `amendment-wave.md` A9.
    ///
    /// The 1pt figure is the migration base input. `MaterialButtonStyleBody`
    /// scales it with the paired button typography role before rendering.
    public static func textOnly(
        theme: MaterialTheme = .snow
    ) -> MaterialQuietButtonStyle {
        MaterialQuietButtonStyle(
            theme: theme,
            pressFeedback: .textInset(points: 1)
        )
    }

    var appearance: MaterialControlAppearance {
        .quiet(tokens: theme.tokens)
    }

    func accessibilityValue(isEnabled: Bool) -> String? {
        isEnabled ? nil : "Unavailable"
    }

    public func makeBody(configuration: Configuration) -> some View {
        MaterialButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            appearance: appearance,
            tokens: theme.tokens,
            pressFeedback: pressFeedback,
            accessibilityValue: accessibilityValue
        )
    }
}

/// The quiet press treatment for rows that already own their resting chrome.
///
/// This adapter deliberately delegates to the same feedback modifier as
/// `MaterialQuietButtonStyle`; it adds no capsule, padding, foreground, or
/// content shape of its own.
public struct MaterialQuietRowButtonStyle: ButtonStyle {
    private let tokens: MaterialTokenSheet
    let pressFeedback: MaterialControlPressFeedback

    public init(theme: MaterialTheme = .snow) {
        tokens = theme.tokens
        pressFeedback = .symbolWeightPulse
    }

    public func makeBody(configuration: Configuration) -> some View {
        MaterialQuietRowButtonStyleBody(
            label: configuration.label,
            liveIsPressed: configuration.isPressed,
            tokens: tokens,
            pressFeedback: pressFeedback
        )
    }

    func body<Label: View>(label: Label, isPressed: Bool) -> some View {
        label.modifier(
            MaterialControlPressFeedbackModifier(
                isPressed: isPressed,
                tokens: tokens,
                pressFeedback: pressFeedback
            )
        )
    }

    static func effectiveIsPressed(
        liveIsPressed: Bool,
        evidenceIsLatched: Bool?
    ) -> Bool {
        liveIsPressed || (evidenceIsLatched ?? false)
    }
}

private struct MaterialQuietRowPressEvidenceLatch {
    let isLatched: Binding<Bool>
    let edgeCount: Binding<Int>
}

private struct MaterialQuietRowPressEvidenceLatchKey: EnvironmentKey {
    static let defaultValue: MaterialQuietRowPressEvidenceLatch? = nil
}

private extension EnvironmentValues {
    var materialQuietRowPressEvidenceLatch: MaterialQuietRowPressEvidenceLatch? {
        get { self[MaterialQuietRowPressEvidenceLatchKey.self] }
        set { self[MaterialQuietRowPressEvidenceLatchKey.self] = newValue }
    }
}

@_spi(PressEvidence)
public extension View {
    func materialQuietRowPressEvidenceLatch(
        isLatched: Binding<Bool>,
        edgeCount: Binding<Int>
    ) -> some View {
        environment(
            \.materialQuietRowPressEvidenceLatch,
            MaterialQuietRowPressEvidenceLatch(
                isLatched: isLatched,
                edgeCount: edgeCount
            )
        )
    }
}

private struct MaterialQuietRowButtonStyleBody<Label: View>: View {
    let label: Label
    let liveIsPressed: Bool
    let tokens: MaterialTokenSheet
    let pressFeedback: MaterialControlPressFeedback

    @Environment(\.materialQuietRowPressEvidenceLatch) private var evidenceLatch

    private var effectiveIsPressed: Bool {
        MaterialQuietRowButtonStyle.effectiveIsPressed(
            liveIsPressed: liveIsPressed,
            evidenceIsLatched: evidenceLatch?.isLatched.wrappedValue
        )
    }

    var body: some View {
        label
            .modifier(
                MaterialControlPressFeedbackModifier(
                    isPressed: effectiveIsPressed,
                    tokens: tokens,
                    pressFeedback: pressFeedback
                )
            )
            .onChange(of: liveIsPressed) { previous, current in
                guard current, !previous, let evidenceLatch else { return }
                evidenceLatch.edgeCount.wrappedValue += 1
                evidenceLatch.isLatched.wrappedValue = true
            }
    }
}

public struct MaterialStateToggleButtonStyle: ButtonStyle {
    private let foreground: SemanticColorToken
    private let background: SemanticColorToken
    private let theme: MaterialTheme

    public init(
        foreground: SemanticColorToken,
        background: SemanticColorToken,
        theme: MaterialTheme = .snow
    ) {
        self.foreground = foreground
        self.background = background
        self.theme = theme
    }

    var appearance: MaterialControlAppearance {
        MaterialControlAppearance(
            foreground: theme.tokens[foreground],
            background: theme.tokens[background],
            backgroundOpacity: 1
        )
    }

    var pressFeedback: MaterialControlPressFeedback { .scale }

    public func makeBody(configuration: Configuration) -> some View {
        MaterialButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            appearance: appearance,
            tokens: theme.tokens,
            pressFeedback: pressFeedback,
            disabledAppearance: .preserveSemanticState,
            accessibilityValue: { $0 ? nil : "Unavailable" }
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

/// Visual geometry for the compact chip family and its ruled accessibility expansion.
public enum MaterialChipSize: Hashable, Sendable {
    case compact
    case expanded

    public var minimumHeight: CGFloat {
        switch self {
        case .compact: 22
        case .expanded: 38
        }
    }

    public var horizontalPadding: CGFloat {
        switch self {
        case .compact: 9
        case .expanded: 14
        }
    }

    public var verticalPadding: CGFloat {
        switch self {
        case .compact: 0
        case .expanded: 5
        }
    }

    public var labelSpacing: CGFloat {
        switch self {
        case .compact: 4
        case .expanded: 6
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
/// supply their per-edge neighbor gaps so interaction cells fill those gaps
/// without overlapping. Omitted edges retain the full free-space outset.
/// Neighbor gaps change hit testing only, never visuals.
/// Tiled interaction cells are rectangular so adjacent targets have no gaps.
public struct MaterialChip: View {
    /// `ia-doors.html` ratifies 12pt/600, which no `TypographyRole` expresses.
    static let titleFont = Font.caption.weight(.semibold)

    @Environment(\.isEnabled) private var isEnabled

    private let title: String
    private let systemImage: String?
    private let state: MaterialChipState
    private let size: MaterialChipSize
    private let theme: MaterialTheme
    private let neighborGaps: MaterialChipNeighborGaps?
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        state: MaterialChipState,
        size: MaterialChipSize = .compact,
        theme: MaterialTheme = .snow,
        neighborGaps: MaterialChipNeighborGaps? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.state = state
        self.size = size
        self.theme = theme
        self.neighborGaps = neighborGaps
        self.action = action
    }

    public var body: some View {
        styledButton
    }

    @ViewBuilder
    private var styledButton: some View {
        let button = Button(action: action) {
            HStack(spacing: size.labelSpacing) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .iconRole(.accessory)
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
                appearance: .filled(tokens: theme.tokens),
                tokens: theme.tokens,
                size: size
            ))
            .contentShape(
                .interaction,
                MaterialChipHitTargetShape(
                    neighborGaps: neighborGaps
                )
            )
        case .tonal:
            button.buttonStyle(MaterialChipButtonStyle(
                appearance: .tonal(tokens: theme.tokens),
                tokens: theme.tokens,
                size: size
            ))
            .contentShape(
                .interaction,
                MaterialChipHitTargetShape(
                    neighborGaps: neighborGaps
                )
            )
        }
    }
}

/// Distances from a chip to distinct-action neighbors on each edge.
///
/// Supply `nil` for an edge facing free space. The component retains the
/// dimension-aware free-space outset there, up to 11pt for the 22pt axis.
/// Negative gaps normalize to zero; non-finite gaps normalize to `nil` so
/// transient layout values fall back to free space.
public struct MaterialChipNeighborGaps: Hashable, Sendable {
    public let top: CGFloat?
    public let leading: CGFloat?
    public let bottom: CGFloat?
    public let trailing: CGFloat?

    public init(
        top: CGFloat? = nil,
        leading: CGFloat? = nil,
        bottom: CGFloat? = nil,
        trailing: CGFloat? = nil
    ) {
        self.top = Self.normalized(top)
        self.leading = Self.normalized(leading)
        self.bottom = Self.normalized(bottom)
        self.trailing = Self.normalized(trailing)
    }

    public static func all(_ gap: CGFloat) -> Self {
        Self(
            top: gap,
            leading: gap,
            bottom: gap,
            trailing: gap
        )
    }

    private static func normalized(_ gap: CGFloat?) -> CGFloat? {
        guard let gap else {
            return nil
        }
        guard gap.isFinite else {
            return nil
        }
        return max(0, gap)
    }
}

/// Public chip metrics for layouts that need to calculate row and column pitch.
public enum MaterialChipGeometry {
    public static let visualHeight: CGFloat = 22
    static let horizontalPadding: CGFloat = 9
    static let labelSpacing: CGFloat = 4
    public static let minimumHitTarget: CGFloat = 44

    /// Returns the free-space expansion needed to reach 44pt.
    public static func hitOutset(for dimension: CGFloat) -> CGFloat {
        max(
            0,
            (minimumHitTarget - dimension) / 2
        )
    }

    /// Returns half a neighbor gap capped at the free-space expansion needed
    /// for `dimension`. `nil` denotes a free edge and returns that expansion.
    public static func tiledHitOutset(
        for dimension: CGFloat,
        neighborGap: CGFloat?
    ) -> CGFloat {
        let freeSpaceOutset = hitOutset(for: dimension)
        guard let neighborGap else {
            return freeSpaceOutset
        }
        guard neighborGap.isFinite else {
            return freeSpaceOutset
        }
        return min(freeSpaceOutset, max(0, neighborGap) / 2)
    }
}

struct MaterialChipHitTargetShape: Shape {
    let neighborGaps: MaterialChipNeighborGaps?

    func path(in rect: CGRect) -> Path {
        guard let neighborGaps else {
            let targetRect = rect.insetBy(
                dx: -MaterialChipGeometry.hitOutset(for: rect.width),
                dy: -MaterialChipGeometry.hitOutset(for: rect.height)
            )
            return Capsule().path(in: targetRect)
        }

        let topOutset = MaterialChipGeometry.tiledHitOutset(
            for: rect.height,
            neighborGap: neighborGaps.top
        )
        let leftOutset = MaterialChipGeometry.tiledHitOutset(
            for: rect.width,
            neighborGap: neighborGaps.leading
        )
        let bottomOutset = MaterialChipGeometry.tiledHitOutset(
            for: rect.height,
            neighborGap: neighborGaps.bottom
        )
        let rightOutset = MaterialChipGeometry.tiledHitOutset(
            for: rect.width,
            neighborGap: neighborGaps.trailing
        )
        let targetRect = CGRect(
            x: rect.minX - leftOutset,
            y: rect.minY - topOutset,
            width: rect.width + leftOutset + rightOutset,
            height: rect.height + topOutset + bottomOutset
        )
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
    let tokens: MaterialTokenSheet
    let size: MaterialChipSize

    func makeBody(configuration: Configuration) -> some View {
        MaterialChipStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            appearance: appearance,
            tokens: tokens,
            size: size
        )
    }
}

struct MaterialChipStyleBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let appearance: MaterialControlAppearance
    let tokens: MaterialTokenSheet
    let size: MaterialChipSize

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .foregroundStyle(appearance.foreground.swiftUIColor)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(minHeight: size.minimumHeight)
            .background(backgroundStyle, in: Capsule())
            .opacity(
                MaterialControlInteractionFeedback.semanticControlOpacity(
                    isEnabled: isEnabled,
                    tokens: tokens
                )
            )
            .scaleEffect(
                MaterialControlInteractionFeedback.semanticControlScale(
                    isPressed: isPressed,
                    tokens: tokens
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

}

struct MaterialControlPressFeedbackModifier: ViewModifier {
    let isPressed: Bool
    let tokens: MaterialTokenSheet
    let pressFeedback: MaterialControlPressFeedback

    @ScaledMetric private var scaledTextInsetPoints: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    init(
        isPressed: Bool,
        tokens: MaterialTokenSheet,
        pressFeedback: MaterialControlPressFeedback
    ) {
        self.isPressed = isPressed
        self.tokens = tokens
        self.pressFeedback = pressFeedback
        _scaledTextInsetPoints = ScaledMetric(
            wrappedValue: pressFeedback.textInsetBasePoints,
            relativeTo:
                MaterialControlPressFeedback
                    .textInsetTypographyAnchor.swiftUI
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(
                \.materialControlSymbolWeight,
                pressFeedback.symbolWeight(isPressed: isPressed)
            )
            .scaleEffect(
                pressFeedback.scale(
                    isPressed: isPressed,
                    tokens: tokens
                )
            )
            .offset(
                y: pressFeedback.verticalOffset(
                    isPressed: isPressed,
                    isEnabled: isEnabled,
                    scaledTextInsetPoints: scaledTextInsetPoints
                )
            )
    }
}

struct MaterialButtonStyleBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let appearance: MaterialControlAppearance
    let tokens: MaterialTokenSheet
    let pressFeedback: MaterialControlPressFeedback
    var disabledAppearance: MaterialControlDisabledAppearance = .dim
    let accessibilityValue: (Bool) -> String?

    @Environment(\.isEnabled) private var isEnabled

    init(
        label: Label,
        isPressed: Bool,
        appearance: MaterialControlAppearance,
        tokens: MaterialTokenSheet,
        pressFeedback: MaterialControlPressFeedback,
        disabledAppearance: MaterialControlDisabledAppearance = .dim,
        accessibilityValue: @escaping (Bool) -> String?
    ) {
        self.label = label
        self.isPressed = isPressed
        self.appearance = appearance
        self.tokens = tokens
        self.pressFeedback = pressFeedback
        self.disabledAppearance = disabledAppearance
        self.accessibilityValue = accessibilityValue
    }

    var body: some View {
        label
            .labelStyle(MaterialControlLabelStyle())
            .font(Typography.font(for: .button))
            .foregroundStyle(appearance.foreground.swiftUIColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(backgroundStyle, in: Capsule())
            .opacity(
                disabledAppearance.opacity(
                    isEnabled: isEnabled,
                    tokens: tokens
                )
            )
            .modifier(
                MaterialControlPressFeedbackModifier(
                    isPressed: isPressed,
                    tokens: tokens,
                    pressFeedback: pressFeedback
                )
            )
            .contentShape(Capsule())
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

}

private struct MaterialControlLabelStyle: LabelStyle {
    @Environment(\.materialControlSymbolWeight) private var symbolWeight

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.body.weight(symbolWeight.swiftUI))
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
