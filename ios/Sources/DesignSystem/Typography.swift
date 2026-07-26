import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

public enum TypographyRole: CaseIterable, Hashable, Sendable {
    case display
    case sheetTitle
    case placeName
    case listRowTitle
    case heroTitle
    case evocativeSubline
    case button
    case action
    case label
    case metadata
    case body
    case data
}

public enum Typography {
    public static func font(for role: TypographyRole) -> Font {
        let specification = role.specification

        if let newsreaderName = specification.newsreaderName {
            guard customFontIsAvailable(
                named: newsreaderName,
                size: specification.pointSize
            ) else {
                var fallback = Font.system(
                    specification.textStyle.swiftUI,
                    design: .serif,
                    weight: specification.weight.swiftUI
                )
                if specification.isItalic {
                    fallback = fallback.italic()
                }
                return fallback
            }

            return .custom(
                newsreaderName,
                size: specification.pointSize,
                relativeTo: specification.textStyle.swiftUI
            )
        }

        return .system(
            specification.textStyle.swiftUI,
            design: .default,
            weight: specification.weight.swiftUI
        )
    }

    private static func customFontIsAvailable(
        named name: String,
        size: CGFloat
    ) -> Bool {
        #if canImport(UIKit)
            UIFont(name: name, size: size) != nil
        #elseif canImport(AppKit)
            NSFont(name: name, size: size) != nil
        #else
            true
        #endif
    }

    #if canImport(UIKit)
        public static func uiFont(
            for role: TypographyRole,
            compatibleWith traitCollection: UITraitCollection? = nil
        ) -> UIFont {
            TypographyProvider.live.uiFont(
                for: role,
                compatibleWith: traitCollection
            )
        }
    #endif
}

#if canImport(UIKit)
    struct TypographyProvider: Sendable {
        typealias FontLoader = @Sendable (String, CGFloat) -> UIFont?

        private let fontNamed: FontLoader

        static var live: TypographyProvider {
            TypographyProvider { name, size in
                UIFont(name: name, size: size)
            }
        }

        init(_ fontNamed: @escaping FontLoader) {
            self.fontNamed = fontNamed
        }

        func uiFont(
            for role: TypographyRole,
            compatibleWith traitCollection: UITraitCollection? = nil
        ) -> UIFont {
            let specification = role.specification
            let baseFont: UIFont = if let newsreaderName = specification.newsreaderName {
                fontNamed(newsreaderName, specification.pointSize)
                    ?? serifFallback(for: specification)
            } else {
                UIFont.systemFont(
                    ofSize: specification.pointSize,
                    weight: specification.weight.uiKit
                )
            }

            return UIFontMetrics(forTextStyle: specification.textStyle.uiKit)
                .scaledFont(for: baseFont, compatibleWith: traitCollection)
        }

        private func serifFallback(
            for specification: TypographyRole.Specification
        ) -> UIFont {
            let systemDescriptor = UIFont.systemFont(
                ofSize: specification.pointSize,
                weight: specification.weight.uiKit
            ).fontDescriptor
            var serifDescriptor = systemDescriptor.withDesign(.serif) ?? systemDescriptor

            if specification.isItalic {
                serifDescriptor = serifDescriptor.withSymbolicTraits(.traitItalic) ?? serifDescriptor
            }

            return UIFont(
                descriptor: serifDescriptor,
                size: specification.pointSize
            )
        }
    }
#endif

extension TypographyRole {
    struct Specification: Sendable {
        let newsreaderName: String?
        let pointSize: CGFloat
        let textStyle: TypographyTextStyle
        let weight: TypographyWeight
        let isItalic: Bool
    }

    var specification: Specification {
        switch self {
        case .display:
            Specification(
                newsreaderName: "Newsreader72pt-SemiBold",
                pointSize: 34,
                textStyle: .largeTitle,
                weight: .semibold,
                isItalic: false
            )
        case .sheetTitle:
            Specification(
                newsreaderName: "Newsreader16pt-SemiBold",
                pointSize: 26,
                textStyle: .title1,
                weight: .semibold,
                isItalic: false
            )
        case .placeName:
            Specification(
                newsreaderName: "Newsreader16pt-Bold",
                pointSize: 24,
                textStyle: .title2,
                weight: .bold,
                isItalic: false
            )
        case .listRowTitle:
            Specification(
                newsreaderName: "Newsreader16pt-SemiBold",
                pointSize: 17,
                textStyle: .headline,
                weight: .semibold,
                isItalic: false
            )
        case .heroTitle:
            Specification(
                newsreaderName: "Newsreader16pt-SemiBold",
                pointSize: 18,
                textStyle: .headline,
                weight: .semibold,
                isItalic: false
            )
        case .evocativeSubline:
            Specification(
                newsreaderName: "Newsreader16pt-Italic",
                pointSize: 15,
                textStyle: .subheadline,
                weight: .regular,
                isItalic: true
            )
        case .button:
            Specification(
                newsreaderName: nil,
                pointSize: 15,
                textStyle: .subheadline,
                weight: .semibold,
                isItalic: false
            )
        case .action:
            Specification(
                newsreaderName: nil,
                pointSize: 13,
                textStyle: .footnote,
                weight: .semibold,
                isItalic: false
            )
        case .label:
            Specification(
                newsreaderName: nil,
                pointSize: 11,
                textStyle: .caption2,
                weight: .semibold,
                isItalic: false
            )
        case .metadata:
            Specification(
                newsreaderName: nil,
                pointSize: 13,
                textStyle: .footnote,
                weight: .regular,
                isItalic: false
            )
        case .body:
            Specification(
                newsreaderName: nil,
                pointSize: 17,
                textStyle: .body,
                weight: .regular,
                isItalic: false
            )
        case .data:
            Specification(
                newsreaderName: nil,
                pointSize: 13,
                textStyle: .footnote,
                weight: .regular,
                isItalic: false
            )
        }
    }
}

enum TypographyTextStyle: Sendable {
    case largeTitle
    case title1
    case title2
    case headline
    case body
    case subheadline
    case footnote
    case caption2

    var swiftUI: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .headline: .headline
        case .body: .body
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption2: .caption2
        }
    }

    #if canImport(UIKit)
        var uiKit: UIFont.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .title1: .title1
            case .title2: .title2
            case .headline: .headline
            case .body: .body
            case .subheadline: .subheadline
            case .footnote: .footnote
            case .caption2: .caption2
            }
        }
    #endif
}

enum TypographyWeight: Sendable {
    case regular
    case semibold
    case bold

    var swiftUI: Font.Weight {
        switch self {
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    #if canImport(UIKit)
        var uiKit: UIFont.Weight {
            switch self {
            case .regular: .regular
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    #endif
}
