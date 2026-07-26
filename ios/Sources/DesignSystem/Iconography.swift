import SwiftUI

public enum IconRole: CaseIterable, Hashable, Sendable {
    case hero
    case inline
    case accessory

    public var pointSize: CGFloat {
        switch self {
        case .hero: 22
        case .inline: 15
        case .accessory: 11
        }
    }

    public var typographyRole: TypographyRole {
        switch self {
        case .hero: .heroTitle
        case .inline: .button
        case .accessory: .label
        }
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

    init(role: IconRole) {
        self.role = role
        _pointSize = ScaledMetric(
            wrappedValue: role.pointSize,
            relativeTo: role.typographyRole.specification.textStyle.swiftUI
        )
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: pointSize, weight: .medium))
            .symbolRenderingMode(.monochrome)
    }
}
