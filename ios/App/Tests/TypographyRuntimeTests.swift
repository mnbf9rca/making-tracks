@testable import DesignSystem
import Foundation
@testable import MakingTracks
import SwiftUI
import UIKit
import XCTest

final class TypographyRuntimeTests: XCTestCase {
    private let contracts: [TypographyContract] = [
        .init(
            role: .display,
            fontName: "Newsreader72pt-SemiBold",
            pointSize: 34,
            textStyle: .largeTitle,
            weight: .semibold
        ),
        .init(
            role: .sheetTitle,
            fontName: "Newsreader16pt-SemiBold",
            pointSize: 26,
            textStyle: .title1,
            weight: .semibold
        ),
        .init(
            role: .placeName,
            fontName: "Newsreader16pt-Bold",
            pointSize: 24,
            textStyle: .title2,
            weight: .bold
        ),
        .init(
            role: .listRowTitle,
            fontName: "Newsreader16pt-SemiBold",
            pointSize: 17,
            textStyle: .headline,
            weight: .semibold
        ),
        .init(
            role: .heroTitle,
            fontName: "Newsreader16pt-SemiBold",
            pointSize: 18,
            textStyle: .headline,
            weight: .semibold
        ),
        .init(
            role: .evocativeSubline,
            fontName: "Newsreader16pt-Italic",
            pointSize: 15,
            textStyle: .subheadline,
            weight: .regular
        ),
        .init(
            role: .button,
            pointSize: 15,
            textStyle: .subheadline,
            weight: .semibold
        ),
        .init(
            role: .label,
            pointSize: 11,
            textStyle: .caption2,
            weight: .semibold
        ),
        .init(
            role: .metadata,
            pointSize: 13,
            textStyle: .footnote,
            weight: .regular
        ),
        .init(
            role: .body,
            pointSize: 17,
            textStyle: .body,
            weight: .regular
        ),
        .init(
            role: .data,
            pointSize: 13,
            textStyle: .footnote,
            weight: .regular
        ),
    ]

    func testEveryRoleUsesItsRatifiedVoiceWeightAndMatchedTextStyle() {
        let categories: [UIContentSizeCategory] = [
            .large,
            .accessibilityExtraExtraExtraLarge,
        ]

        XCTAssertEqual(Set(contracts.map(\.role)), Set(TypographyRole.allCases))

        for contract in contracts {
            let baseFont = contract.baseFont

            for category in categories {
                let traits = UITraitCollection(preferredContentSizeCategory: category)
                let expected = UIFontMetrics(forTextStyle: contract.textStyle)
                    .scaledFont(for: baseFont, compatibleWith: traits)
                let actual = Typography.uiFont(
                    for: contract.role,
                    compatibleWith: traits
                )

                XCTAssertEqual(
                    actual.fontName,
                    expected.fontName,
                    "\(contract.role) must retain its ratified story/SF voice and weight"
                )
                XCTAssertEqual(
                    actual.pointSize,
                    expected.pointSize,
                    accuracy: 0.001,
                    "\(contract.role) must scale through \(contract.textStyle.rawValue)"
                )
            }
        }
    }

    @MainActor
    func testSwiftUIFontHonorsSubtreeDynamicTypeSizeForEveryRole() {
        for role in TypographyRole.allCases {
            let compactSize = measuredTextSize(for: role, at: .small)
            let accessibilitySize = measuredTextSize(for: role, at: .accessibility5)

            XCTAssertGreaterThan(
                accessibilitySize.height,
                compactSize.height,
                "\(role) must honor SwiftUI's subtree Dynamic Type environment"
            )
            XCTAssertGreaterThan(
                accessibilitySize.width,
                compactSize.width,
                "\(role) must honor SwiftUI's subtree Dynamic Type environment"
            )
        }
    }

    func testMissingNewsreaderCutsFallBackToTheRuntimeSerifDesignAndPreserveItalic() throws {
        let provider = TypographyProvider { _, _ in nil }

        let placeNameFallback = provider.uiFont(for: .placeName)
        let serifDescriptor = try XCTUnwrap(
            UIFont.systemFont(ofSize: 24, weight: .bold)
                .fontDescriptor
                .withDesign(.serif)
        )
        let expectedBase = UIFont(
            descriptor: serifDescriptor,
            size: 24
        )
        let expected = UIFontMetrics(forTextStyle: .title2).scaledFont(for: expectedBase)

        XCTAssertEqual(placeNameFallback.familyName, expected.familyName)
        XCTAssertNotEqual(placeNameFallback.familyName, UIFont.systemFont(ofSize: 24).familyName)

        let heroTitleFallback = provider.uiFont(for: .heroTitle)
        let heroSerifDescriptor = try XCTUnwrap(
            UIFont.systemFont(ofSize: 18, weight: .semibold)
                .fontDescriptor
                .withDesign(.serif)
        )
        let expectedHeroBase = UIFont(
            descriptor: heroSerifDescriptor,
            size: 18
        )
        let expectedHero = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: expectedHeroBase)

        XCTAssertEqual(heroTitleFallback.familyName, expectedHero.familyName)
        XCTAssertNotEqual(
            heroTitleFallback.familyName,
            UIFont.systemFont(ofSize: 18).familyName
        )

        let sublineFallback = provider.uiFont(for: .evocativeSubline)

        XCTAssertEqual(sublineFallback.familyName, expected.familyName)
        XCTAssertTrue(sublineFallback.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    func testEveryDeclaredFontIsBundledAndRegistered() {
        let fileNames = [
            "Newsreader72pt-SemiBold.ttf",
            "Newsreader16pt-SemiBold.ttf",
            "Newsreader16pt-Bold.ttf",
            "Newsreader16pt-Italic.ttf",
        ]

        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String], fileNames)

        for fileName in fileNames {
            let resourceName = String(fileName.dropLast(4))
            XCTAssertNotNil(
                Bundle.main.url(forResource: resourceName, withExtension: "ttf"),
                "\(fileName) must be copied into the app bundle"
            )
        }
    }

    func testProductionCreditsLoaderDecodesTheExactNewsreaderOFLNotice() throws {
        let manifest = try XCTUnwrap(OSSCreditsManifest.load())
        let newsreader = try XCTUnwrap(
            manifest.credits.first { $0.name == "Newsreader" }
        )
        let noticeURL = try XCTUnwrap(
            Bundle.main.url(forResource: "OFL", withExtension: "txt")
        )
        let shippedNotice = try String(contentsOf: noticeURL, encoding: .utf8)

        XCTAssertEqual(
            newsreader.acknowledgement,
            "Newsreader (productiontype/Newsreader commit "
                + "cfcb4f7af0e52c25e8df2a2431814c8e5fe2e155; static TTF instances) "
                + "is licensed under OFL-1.1."
        )
        XCTAssertEqual(newsreader.category, "ios_app")
        XCTAssertEqual(newsreader.noticeText, shippedNotice)
        XCTAssertEqual(
            newsreader.versionOrPin,
            "productiontype/Newsreader commit "
                + "cfcb4f7af0e52c25e8df2a2431814c8e5fe2e155; static TTF instances"
        )
        XCTAssertEqual(
            newsreader.licenseURL?.absoluteString,
            "https://github.com/productiontype/Newsreader/blob/"
                + "cfcb4f7af0e52c25e8df2a2431814c8e5fe2e155/OFL.txt"
        )
    }

    @MainActor
    private func measuredTextSize(
        for role: TypographyRole,
        at dynamicTypeSize: DynamicTypeSize
    ) -> CGSize {
        let view = Text("Newsreader")
            .font(Typography.font(for: role))
            .dynamicTypeSize(dynamicTypeSize)
            .fixedSize()
        let host = UIHostingController(rootView: view)

        return host.sizeThatFits(
            in: CGSize(width: 1000, height: 1000)
        )
    }
}

private struct TypographyContract {
    let role: TypographyRole
    let fontName: String?
    let pointSize: CGFloat
    let textStyle: UIFont.TextStyle
    let weight: UIFont.Weight

    init(
        role: TypographyRole,
        fontName: String? = nil,
        pointSize: CGFloat,
        textStyle: UIFont.TextStyle,
        weight: UIFont.Weight
    ) {
        self.role = role
        self.fontName = fontName
        self.pointSize = pointSize
        self.textStyle = textStyle
        self.weight = weight
    }

    var baseFont: UIFont {
        if let fontName {
            return UIFont(name: fontName, size: pointSize)!
        }
        return UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
