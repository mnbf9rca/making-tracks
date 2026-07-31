import SwiftUI

enum MaterialControlSymbolWeight: Equatable, Sendable {
    case standard
    case emphasized

    var swiftUI: Font.Weight {
        switch self {
        case .standard: .medium
        case .emphasized: .semibold
        }
    }
}

private struct MaterialControlSymbolWeightKey: EnvironmentKey {
    static let defaultValue = MaterialControlSymbolWeight.standard
}

extension EnvironmentValues {
    var materialControlSymbolWeight: MaterialControlSymbolWeight {
        get { self[MaterialControlSymbolWeightKey.self] }
        set { self[MaterialControlSymbolWeightKey.self] = newValue }
    }
}

public enum IconRole: CaseIterable, Hashable, Sendable {
    case hero
    case inline
    case accessory
    case rowRaised
    case rowQuiet

    public var pointSize: CGFloat {
        switch self {
        case .hero: 22
        case .inline: 15
        case .accessory: 11
        case .rowRaised: 20
        case .rowQuiet: 18
        }
    }

    public var typographyRole: TypographyRole {
        switch self {
        case .hero: .heroTitle
        case .inline: .button
        case .accessory: .label
        case .rowRaised: .listRowTitle
        case .rowQuiet: .button
        }
    }
}

/// Ratified pairing constant for the Explore quiet destination row.
public enum ExploreSurfaceIconGeometry {
    public static let quietDestination: CGFloat = 18
}

/// P2R-4's Scope-control icon is semantically distinct from `rowRaised`
/// despite sharing its current point size.
public enum ScopeControlIconGeometry {
    public static let pointSize: CGFloat = 20
    public static let accessibilityPointSize: CGFloat = 30
    public static let typographyRole = TypographyRole.button
    public static let relativeTextStyle = Font.TextStyle.subheadline

    public static func resolvedPointSize(
        scaledPointSize: CGFloat,
        isAccessibilitySize: Bool
    ) -> CGFloat {
        isAccessibilitySize ? accessibilityPointSize : scaledPointSize
    }
}

public extension View {
    func iconRole(_ role: IconRole) -> some View {
        modifier(IconRoleModifier(role: role))
    }
}

private struct IconRoleModifier: ViewModifier {
    private let role: IconRole
    @ScaledMetric private var pointSize: CGFloat
    @Environment(\.materialControlSymbolWeight) private var symbolWeight

    init(role: IconRole) {
        self.role = role
        _pointSize = ScaledMetric(
            wrappedValue: role.pointSize,
            relativeTo: role.typographyRole.specification.textStyle.swiftUI
        )
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: pointSize, weight: symbolWeight.swiftUI))
            .symbolRenderingMode(.monochrome)
    }
}
