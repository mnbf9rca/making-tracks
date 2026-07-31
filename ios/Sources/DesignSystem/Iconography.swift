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

/// Ratified pairing constants for the Explore surface; these are not new icon roles.
public enum ExploreSurfaceIconGeometry {
    public static let scopeControl: CGFloat = 20
    public static let quietDestination: CGFloat = 18
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
