import SwiftUI

public enum IconographyRole: CaseIterable, Hashable, Sendable {
    case standard
    case compact
}

public enum Iconography {
    public static func font(for role: IconographyRole) -> Font {
        switch role {
        case .standard:
            Font.body.weight(.medium)
        case .compact:
            Font.caption.weight(.medium)
        }
    }
}
