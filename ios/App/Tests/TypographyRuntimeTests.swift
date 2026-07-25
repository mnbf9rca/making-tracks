@testable import DesignSystem
import Foundation
import UIKit
import XCTest

final class TypographyRuntimeTests: XCTestCase {
    private let storyFontNames: [TypographyRole: String] = [
        .display: "Newsreader72pt-SemiBold",
        .sheetTitle: "Newsreader16pt-SemiBold",
        .placeName: "Newsreader16pt-Bold",
        .listRowTitle: "Newsreader16pt-SemiBold",
        .evocativeSubline: "Newsreader16pt-Italic",
    ]

    func testStoryRolesResolveTheBundledStaticNewsreaderCuts() {
        for (role, fontName) in storyFontNames {
            XCTAssertEqual(
                Typography.uiFont(for: role).fontName,
                fontName,
                "\(role) must resolve the intended static Newsreader instance"
            )
        }
    }

    func testEveryTypographyRoleScalesThroughItsMatchedTextStyle() {
        let small = UITraitCollection(preferredContentSizeCategory: .extraSmall)
        let accessibility = UITraitCollection(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )

        for role in TypographyRole.allCases {
            let smallFont = Typography.uiFont(for: role, compatibleWith: small)
            let accessibilityFont = Typography.uiFont(for: role, compatibleWith: accessibility)

            XCTAssertGreaterThan(
                accessibilityFont.pointSize,
                smallFont.pointSize,
                "\(role) must grow with Dynamic Type"
            )
        }
    }

    func testMissingNewsreaderCutFallsBackToTheRuntimeSerifDesign() throws {
        let provider = TypographyProvider { _, _ in nil }

        let fallback = provider.uiFont(for: .placeName)
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

        XCTAssertEqual(fallback.familyName, expected.familyName)
        XCTAssertNotEqual(fallback.familyName, UIFont.systemFont(ofSize: 24).familyName)
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

    func testNewsreaderOFLNoticeIsVisibleThroughTheCreditsManifest() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "OSSCredits", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(CreditsManifest.self, from: data)
        let newsreader = try XCTUnwrap(
            manifest.credits.first { $0.name == "Newsreader" }
        )

        XCTAssertEqual(newsreader.licenseSPDX, "OFL-1.1")
        XCTAssertTrue(newsreader.noticeText.contains("Copyright 2020 The Newsreader Project Authors"))
        XCTAssertTrue(newsreader.noticeText.contains("SIL OPEN FONT LICENSE Version 1.1"))
    }
}

private struct CreditsManifest: Decodable {
    let credits: [Credit]
}

private struct Credit: Decodable {
    let name: String
    let licenseSPDX: String
    let noticeText: String

    enum CodingKeys: String, CodingKey {
        case name
        case licenseSPDX = "license_spdx"
        case noticeText = "notice_text"
    }
}
