import Foundation
import SwiftUI

public struct MaterialColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    init(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        opacity: Double = 1
    ) {
        self.red = Double(red) / 255
        self.green = Double(green) / 255
        self.blue = Double(blue) / 255
        self.opacity = opacity
    }

    public var swiftUIColor: Color {
        Color(
            .sRGB,
            red: red,
            green: green,
            blue: blue,
            opacity: opacity
        )
    }

    public var mapStyleString: String {
        let red = Int((red * 255).rounded())
        let green = Int((green * 255).rounded())
        let blue = Int((blue * 255).rounded())

        guard opacity != 1 else {
            return String(format: "#%02X%02X%02X", red, green, blue)
        }

        let opacity = String(
            format: "%.15g",
            locale: Locale(identifier: "en_US_POSIX"),
            self.opacity
        )
        return "rgba(\(red), \(green), \(blue), \(opacity))"
    }

    fileprivate func withOpacity(_ opacity: Double) -> MaterialColor {
        MaterialColor(
            normalizedRed: red,
            normalizedGreen: green,
            normalizedBlue: blue,
            opacity: opacity
        )
    }

    private init(
        normalizedRed red: Double,
        normalizedGreen green: Double,
        normalizedBlue blue: Double,
        opacity: Double
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

public enum SemanticColorToken: String, CaseIterable, Hashable, Sendable {
    case ground
    case water
    case park
    case road
    case roadMinor
    case surface
    case surfaceRaised
    case ink
    case muted
    case accent
    case accentContainer
    /// Saved ON Deep Companion, ratified `#08483E` by designer pick 2026-07-30.
    case accentDeepContainer
    case accentContrast
    case love
    case loveContainer
    case warning
    case warningContainer
    case eyebrow
    case hairline
    case scrim
    case shadow
    case background
    case labels
    case labelHalo
    case boundaries
    case trail
}

public struct PinTokenBlock: Hashable, Sendable {
    public static let constant = PinTokenBlock(
        pin: MaterialColor(red: 0xE4, green: 0x57, blue: 0x2E),
        hiddenPin: MaterialColor(red: 0x76, green: 0x7B, blue: 0x82),
        fadedOpacity: 0.35
    )

    public let pin: MaterialColor
    public let hiddenPin: MaterialColor
    private let fadedOpacity: Double

    public var pinFaded: MaterialColor {
        pin.withOpacity(fadedOpacity)
    }

    private init(pin: MaterialColor, hiddenPin: MaterialColor, fadedOpacity: Double) {
        self.pin = pin
        self.hiddenPin = hiddenPin
        self.fadedOpacity = fadedOpacity
    }
}

public struct MaterialTokenSheet: Hashable, Sendable {
    public let ground: MaterialColor
    public let water: MaterialColor
    public let park: MaterialColor
    public let road: MaterialColor
    public let roadMinor: MaterialColor
    public let surface: MaterialColor
    public let surfaceRaised: MaterialColor
    public let ink: MaterialColor
    public let muted: MaterialColor
    public let accent: MaterialColor
    public let accentContainer: MaterialColor
    /// Saved ON Deep Companion, ratified `#08483E` by designer pick 2026-07-30.
    public let accentDeepContainer: MaterialColor
    public let accentContrast: MaterialColor
    public let love: MaterialColor
    public let loveContainer: MaterialColor
    public let warning: MaterialColor
    public let warningContainer: MaterialColor
    public let eyebrow: MaterialColor
    public let hairline: MaterialColor
    public let scrim: MaterialColor
    public let shadow: MaterialColor
    public let background: MaterialColor
    public let labels: MaterialColor
    public let labelHalo: MaterialColor
    public let boundaries: MaterialColor
    public let trail: MaterialColor
    /// Alpha used to composite a semantic tonal-container color over `surface`.
    ///
    /// Contrast checks for neighboring opaque containers must compare against
    /// this resulting wash, not against the bare surface color.
    public let tonalContainerCompositeOpacity: Double
    public let disabledAlpha: Double
    public let pressScale: CGFloat

    public var pins: PinTokenBlock {
        .constant
    }

    public subscript(token: SemanticColorToken) -> MaterialColor {
        switch token {
        case .ground: ground
        case .water: water
        case .park: park
        case .road: road
        case .roadMinor: roadMinor
        case .surface: surface
        case .surfaceRaised: surfaceRaised
        case .ink: ink
        case .muted: muted
        case .accent: accent
        case .accentContainer: accentContainer
        case .accentDeepContainer: accentDeepContainer
        case .accentContrast: accentContrast
        case .love: love
        case .loveContainer: loveContainer
        case .warning: warning
        case .warningContainer: warningContainer
        case .eyebrow: eyebrow
        case .hairline: hairline
        case .scrim: scrim
        case .shadow: shadow
        case .background: background
        case .labels: labels
        case .labelHalo: labelHalo
        case .boundaries: boundaries
        case .trail: trail
        }
    }

    fileprivate static let snow = MaterialTokenSheet(
        ground: MaterialColor(red: 0xF4, green: 0xF1, blue: 0xEA),
        water: MaterialColor(red: 0xC9, green: 0xDB, blue: 0xE2),
        park: MaterialColor(red: 0xDC, green: 0xE5, blue: 0xD4),
        road: MaterialColor(red: 0xC9, green: 0xBF, blue: 0xA8),
        roadMinor: MaterialColor(red: 0xDD, green: 0xD5, blue: 0xC2),
        surface: MaterialColor(red: 0xFB, green: 0xFA, blue: 0xF2),
        surfaceRaised: MaterialColor(red: 0xFF, green: 0xFF, blue: 0xFF),
        ink: MaterialColor(red: 0x2B, green: 0x28, blue: 0x23),
        muted: MaterialColor(red: 0x6B, green: 0x67, blue: 0x5F),
        accent: MaterialColor(red: 0x0A, green: 0x6B, blue: 0x5C),
        accentContainer: MaterialColor(red: 0xD4, green: 0xED, blue: 0xE9),
        accentDeepContainer: MaterialColor(red: 0x08, green: 0x48, blue: 0x3E),
        accentContrast: MaterialColor(red: 0xFB, green: 0xFA, blue: 0xF2),
        love: MaterialColor(red: 0xC4, green: 0x31, blue: 0x2B),
        loveContainer: MaterialColor(red: 0xFC, green: 0xE3, blue: 0xE3),
        warning: MaterialColor(red: 0x75, green: 0x57, blue: 0x1F),
        warningContainer: MaterialColor(red: 0xF2, green: 0xE8, blue: 0xD1),
        eyebrow: MaterialColor(red: 0x8A, green: 0x5A, blue: 0x2B),
        hairline: MaterialColor(red: 0x2B, green: 0x28, blue: 0x23, opacity: 0.14),
        scrim: MaterialColor(red: 0x2B, green: 0x28, blue: 0x23, opacity: 0.35),
        shadow: MaterialColor(red: 0x2B, green: 0x28, blue: 0x23, opacity: 0.10),
        background: MaterialColor(red: 0xF4, green: 0xF1, blue: 0xEA),
        labels: MaterialColor(red: 0x6B, green: 0x67, blue: 0x5F),
        labelHalo: MaterialColor(red: 0xF4, green: 0xF1, blue: 0xEA),
        boundaries: MaterialColor(red: 0x2B, green: 0x28, blue: 0x23, opacity: 0.14),
        trail: MaterialColor(red: 0x2D, green: 0x8C, blue: 0x83),
        tonalContainerCompositeOpacity: 0.12,
        disabledAlpha: 0.46,
        pressScale: 0.98
    )

    init(
        ground: MaterialColor,
        water: MaterialColor,
        park: MaterialColor,
        road: MaterialColor,
        roadMinor: MaterialColor,
        surface: MaterialColor,
        surfaceRaised: MaterialColor,
        ink: MaterialColor,
        muted: MaterialColor,
        accent: MaterialColor,
        accentContainer: MaterialColor,
        accentDeepContainer: MaterialColor,
        accentContrast: MaterialColor,
        love: MaterialColor,
        loveContainer: MaterialColor,
        warning: MaterialColor,
        warningContainer: MaterialColor,
        eyebrow: MaterialColor,
        hairline: MaterialColor,
        scrim: MaterialColor,
        shadow: MaterialColor,
        background: MaterialColor,
        labels: MaterialColor,
        labelHalo: MaterialColor,
        boundaries: MaterialColor,
        trail: MaterialColor,
        tonalContainerCompositeOpacity: Double,
        disabledAlpha: Double,
        pressScale: CGFloat
    ) {
        self.ground = ground
        self.water = water
        self.park = park
        self.road = road
        self.roadMinor = roadMinor
        self.surface = surface
        self.surfaceRaised = surfaceRaised
        self.ink = ink
        self.muted = muted
        self.accent = accent
        self.accentContainer = accentContainer
        self.accentDeepContainer = accentDeepContainer
        self.accentContrast = accentContrast
        self.love = love
        self.loveContainer = loveContainer
        self.warning = warning
        self.warningContainer = warningContainer
        self.eyebrow = eyebrow
        self.hairline = hairline
        self.scrim = scrim
        self.shadow = shadow
        self.background = background
        self.labels = labels
        self.labelHalo = labelHalo
        self.boundaries = boundaries
        self.trail = trail
        self.tonalContainerCompositeOpacity = tonalContainerCompositeOpacity
        self.disabledAlpha = disabledAlpha
        self.pressScale = pressScale
    }
}

public enum MaterialTheme: String, CaseIterable, Hashable, Sendable {
    case snow

    public var tokens: MaterialTokenSheet {
        switch self {
        case .snow: .snow
        }
    }

    public var colorScheme: ColorScheme {
        switch self {
        case .snow: .light
        }
    }
}
