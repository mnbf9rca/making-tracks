#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import XCTest
@testable import DesignSystem

@MainActor
final class ControlStylesTests: XCTestCase {
    func testButtonStylesResolveTheThreeRatifiedSemanticPalettes() {
        let filled = MaterialFilledButtonStyle().appearance
        XCTAssertEqual(filled.foreground, color(0xFB, 0xFA, 0xF2))
        XCTAssertEqual(filled.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(filled.backgroundOpacity, 1)

        let tonal = MaterialTonalButtonStyle().appearance
        XCTAssertEqual(tonal.foreground, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(tonal.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(tonal.backgroundOpacity, 0.12)

        let quiet = MaterialQuietButtonStyle().appearance
        XCTAssertEqual(quiet.foreground, color(0x6B, 0x67, 0x5F))
        XCTAssertNil(quiet.background)
        XCTAssertEqual(quiet.backgroundOpacity, 0)
    }

    func testChipStatesMapActiveToFilledAndAvailableToTonal() {
        let active = MaterialChipState.active.appearance
        XCTAssertEqual(active.foreground, color(0xFB, 0xFA, 0xF2))
        XCTAssertEqual(active.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(active.backgroundOpacity, 1)

        let available = MaterialChipState.available.appearance
        XCTAssertEqual(available.foreground, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(available.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(available.backgroundOpacity, 0.12)
    }

    func testDisabledButtonsAndChipsExposeSpokenState() {
        let buttonValues: [(Bool) -> String?] = [
            MaterialFilledButtonStyle().accessibilityValue,
            MaterialTonalButtonStyle().accessibilityValue,
            MaterialQuietButtonStyle().accessibilityValue,
        ]
        for value in buttonValues {
            XCTAssertNil(value(true))
            XCTAssertEqual(value(false), "Unavailable")
        }

        XCTAssertEqual(
            MaterialChipState.active.accessibilityValue(isEnabled: true),
            "Selected"
        )
        XCTAssertEqual(
            MaterialChipState.available.accessibilityValue(isEnabled: true),
            "Not selected"
        )
        XCTAssertEqual(
            MaterialChipState.active.accessibilityValue(isEnabled: false),
            "Unavailable"
        )
        XCTAssertEqual(
            MaterialChipState.available.accessibilityValue(isEnabled: false),
            "Unavailable"
        )
    }

#if canImport(AppKit)
    func testMaterialChipRendersActiveFilledAndAvailableTonal() throws {
        let active = try renderChip(state: .active)
        let available = try renderChip(state: .available)

        let activeAccentPixels = solidAccentPixelCount(in: active)
        let availableAccentPixels = solidAccentPixelCount(in: available)

        XCTAssertGreaterThan(activeAccentPixels, availableAccentPixels + 500)
    }

    func testMaterialChipNeighborGapDoesNotChangeRenderedPixels() throws {
        let freeSpace = try render(
            MaterialChip("Trail", state: .active, action: {})
        )
        let tiled = try render(
            MaterialChip(
                "Trail",
                state: .active,
                neighborGaps: .all(8),
                action: {}
            )
        )

        XCTAssertEqual(freeSpace.width, tiled.width)
        XCTAssertEqual(freeSpace.height, tiled.height)
        XCTAssertEqual(
            try pixelData(in: freeSpace),
            try pixelData(in: tiled)
        )
    }

    func testMaterialChipTitleUsesRatifiedCaptionSizeAndSemiboldWeight() throws {
        let shortTitle = "Map"
        let longTitle = "Map places"

        XCTAssertEqual(
            MaterialChip.titleFont,
            Font.caption.weight(.semibold)
        )

        let styledWidthDelta = try renderedWidth(
            MaterialChip(shortTitle, state: .active, action: {})
        ) - renderedWidth(
            MaterialChip(longTitle, state: .active, action: {})
        )
        let expectedWidthDelta = try renderedWidth(
            Text(shortTitle)
                .font(.caption.weight(.semibold))
        ) - renderedWidth(
            Text(longTitle)
                .font(.caption.weight(.semibold))
        )

        XCTAssertEqual(styledWidthDelta, expectedWidthDelta, accuracy: 1)
    }

    func testMaterialChipUsesRatifiedVisualHeightAndHorizontalPadding() throws {
        let title = "Map"
        let chip = MaterialChip(title, state: .active, action: {})
        let styledTitle = Text(title)
            .font(MaterialChip.titleFont)
            .fixedSize(horizontal: false, vertical: true)

        XCTAssertEqual(try renderedHeight(chip), 22)
        XCTAssertEqual(
            try renderedWidth(chip) - renderedWidth(styledTitle),
            18,
            accuracy: 1
        )
        XCTAssertEqual(
            try renderedHeight(
                Button("Save", action: {})
                    .buttonStyle(MaterialFilledButtonStyle())
            ),
            44
        )
    }

    func testMaterialChipFreeSpaceHitTargetExpandsOnlyDimensionsBelowMinimum() {
        XCTAssertEqual(MaterialChipGeometry.minimumHitTarget, 44)
        XCTAssertEqual(
            MaterialChipGeometry.hitOutset(
                for: MaterialChipGeometry.visualHeight
            ),
            11
        )
        XCTAssertEqual(
            MaterialChipGeometry.hitOutset(for: 44),
            0
        )
        XCTAssertEqual(
            MaterialChipGeometry.hitOutset(for: 80),
            0
        )
    }

    func testMaterialChipTiledHitTargetClipsOutsetToHalfNeighborGap() {
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(
                for: MaterialChipGeometry.visualHeight,
                neighborGap: 8
            ),
            4
        )
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(
                for: MaterialChipGeometry.visualHeight,
                neighborGap: 44
            ),
            11
        )
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(
                for: MaterialChipGeometry.visualHeight,
                neighborGap: 0
            ),
            0
        )
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(
                for: MaterialChipGeometry.visualHeight,
                neighborGap: nil
            ),
            11
        )
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(
                for: MaterialChipGeometry.visualHeight,
                neighborGap: -8
            ),
            0
        )
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(
                for: MaterialChipGeometry.visualHeight,
                neighborGap: .nan
            ),
            11
        )
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(
                for: MaterialChipGeometry.visualHeight,
                neighborGap: .infinity
            ),
            11
        )
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(
                for: 60,
                neighborGap: nil
            ),
            0,
            "A free edge does not expand an axis already wider than 44pt"
        )
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(
                for: 60,
                neighborGap: 8
            ),
            0,
            "A neighbor gap never creates expansion an axis does not need"
        )
    }

    func testMaterialChipNeighborGapsNormalizeUnsafeLayoutValues() {
        let gaps = MaterialChipNeighborGaps(
            top: -8,
            leading: .nan,
            bottom: .infinity,
            trailing: 8
        )

        XCTAssertEqual(gaps.top, 0)
        XCTAssertNil(gaps.leading)
        XCTAssertNil(gaps.bottom)
        XCTAssertEqual(gaps.trailing, 8)
    }

    func testMaterialChipTiledHitTargetsClipOnlyFacingSides() {
        let gap: CGFloat = 8
        let chipWidth = MaterialChipGeometry.visualHeight
        let leftRect = CGRect(
            x: 0,
            y: 0,
            width: chipWidth,
            height: MaterialChipGeometry.visualHeight
        )
        let rightRect = CGRect(
            x: leftRect.maxX + gap,
            y: 0,
            width: chipWidth,
            height: MaterialChipGeometry.visualHeight
        )
        let leftTarget = MaterialChipHitTargetShape(
            neighborGaps: MaterialChipNeighborGaps(trailing: gap)
        ).path(in: leftRect)
        let rightTarget = MaterialChipHitTargetShape(
            neighborGaps: MaterialChipNeighborGaps(leading: gap)
        ).path(in: rightRect)
        let centerY = leftRect.midY
        let samples = [
            (
                point: CGPoint(x: leftRect.maxX + 1, y: centerY),
                leftOwnsPoint: true
            ),
            (
                point: CGPoint(x: rightRect.minX - 1, y: centerY),
                leftOwnsPoint: false
            ),
            (
                point: CGPoint(
                    x: leftRect.maxX + 1,
                    y: leftRect.minY - 3
                ),
                leftOwnsPoint: true
            ),
            (
                point: CGPoint(
                    x: rightRect.minX - 1,
                    y: rightRect.maxY + 3
                ),
                leftOwnsPoint: false
            ),
        ]

        for sample in samples {
            let leftContains = leftTarget.contains(sample.point)
            let rightContains = rightTarget.contains(sample.point)

            XCTAssertNotEqual(
                leftContains,
                rightContains,
                "Every sampled point must map to exactly one chip"
            )
            XCTAssertEqual(leftContains, sample.leftOwnsPoint)
        }

        XCTAssertTrue(
            leftTarget.contains(
                CGPoint(x: leftRect.minX - 10, y: leftRect.midY)
            ),
            "The free run edge keeps its full 11pt outset"
        )
        XCTAssertTrue(
            leftTarget.contains(
                CGPoint(x: leftRect.midX, y: leftRect.minY - 10)
            ),
            "The free row edge keeps its full 11pt outset"
        )
    }

    func testMaterialChipTiledHitTargetsUseIndependentAxisGaps() {
        let rect = CGRect(
            x: 20,
            y: 20,
            width: MaterialChipGeometry.visualHeight,
            height: MaterialChipGeometry.visualHeight
        )
        let path = MaterialChipHitTargetShape(
            neighborGaps: MaterialChipNeighborGaps(
                top: 6,
                leading: 8,
                bottom: 10,
                trailing: 12
            )
        ).path(in: rect)

        XCTAssertEqual(path.boundingRect.minX, rect.minX - 4)
        XCTAssertEqual(path.boundingRect.maxX, rect.maxX + 6)
        XCTAssertEqual(path.boundingRect.minY, rect.minY - 3)
        XCTAssertEqual(path.boundingRect.maxY, rect.maxY + 5)
    }

    func testMaterialChipTiledHitTargetsMirrorLeadingForRightToLeft() {
        let rect = CGRect(
            x: 20,
            y: 20,
            width: MaterialChipGeometry.visualHeight,
            height: MaterialChipGeometry.visualHeight
        )
        let path = MaterialChipHitTargetShape(
            neighborGaps: MaterialChipNeighborGaps(
                leading: 8,
                trailing: 12
            )
        ).path(in: rect)

        XCTAssertEqual(path.boundingRect.minX, rect.minX - 4)
        XCTAssertEqual(path.boundingRect.maxX, rect.maxX + 6)
        XCTAssertEqual(path.boundingRect.width, rect.width + 10)
        XCTAssertEqual(
            MaterialChipHitTargetShape(
                neighborGaps: .all(8)
            ).layoutDirectionBehavior,
            .mirrors(in: .rightToLeft),
            "SwiftUI must mirror logical leading and trailing exactly once"
        )
    }

    func testMaterialChipIconUsesAccessoryRoleAtAccessibilityScale() throws {
        let title = "Map"

        let textOnlyWidth = try renderedWidth(
            MaterialChip(title, state: .active, action: {})
                .dynamicTypeSize(.accessibility5)
        )
        let iconAndTextWidth = try renderedWidth(
            MaterialChip(
                title,
                systemImage: "map",
                state: .active,
                action: {}
            )
            .dynamicTypeSize(.accessibility5)
        )
        let expectedIconWidth = try renderedWidth(
            Image(systemName: "map")
                .iconRole(.accessory)
                .dynamicTypeSize(.accessibility5)
        )

        XCTAssertEqual(
            iconAndTextWidth - textOnlyWidth,
            expectedIconWidth + 4,
            accuracy: 1
        )
    }
#endif

    func testMaterialFilledButtonPlainTextUsesTypographyButtonRole() throws {
        let shortTitle = "Save"
        let longTitle = "Save place"

        let styledWidthDelta = try renderedWidth(
            Button(shortTitle, action: {})
                .buttonStyle(MaterialFilledButtonStyle())
        ) - renderedWidth(
            Button(longTitle, action: {})
                .buttonStyle(MaterialFilledButtonStyle())
        )
        let expectedWidthDelta = try renderedWidth(
            Text(shortTitle).font(Typography.font(for: .button))
        ) - renderedWidth(
            Text(longTitle).font(Typography.font(for: .button))
        )

        XCTAssertEqual(styledWidthDelta, expectedWidthDelta, accuracy: 1)
    }

    func testMaterialFilledButtonLabelTitleUsesTypographyButtonRole() throws {
        let shortTitle = "Save"
        let longTitle = "Save place"

        let styledWidthDelta = try renderedWidth(
            Button(action: {}) {
                Label(shortTitle, systemImage: "bookmark")
            }
            .buttonStyle(MaterialFilledButtonStyle())
        ) - renderedWidth(
            Button(action: {}) {
                Label(longTitle, systemImage: "bookmark")
            }
            .buttonStyle(MaterialFilledButtonStyle())
        )
        let expectedWidthDelta = try renderedWidth(
            Text(shortTitle).font(Typography.font(for: .button))
        ) - renderedWidth(
            Text(longTitle).font(Typography.font(for: .button))
        )

        XCTAssertEqual(styledWidthDelta, expectedWidthDelta, accuracy: 1)
    }

    func testMaterialControlsGrowVerticallyForMultilineLabels() throws {
        let shortChip = try renderedHeight(
            MaterialChip("Saved", state: .active, action: {})
                .frame(width: 108)
        )
        let longChip = try renderedHeight(
            MaterialChip(
                "Saved for a long weekend adventure in the mountains",
                state: .active,
                action: {}
            )
            .frame(width: 108)
        )

        XCTAssertGreaterThan(longChip, shortChip + 10)

        let shortButton = try renderedHeight(
            Button("Save", action: {})
                .buttonStyle(MaterialFilledButtonStyle())
                .frame(width: 108)
        )
        let longButton = try renderedHeight(
            Button(
                "Save for a long weekend adventure in the mountains",
                action: {}
            )
                .buttonStyle(MaterialFilledButtonStyle())
                .frame(width: 108)
        )

        XCTAssertGreaterThan(longButton, shortButton + 10)
    }

    private func renderChip(state: MaterialChipState) throws -> CGImage {
        try render(
            MaterialChip("Trail", state: state, action: {})
                .padding(8)
                .background(Color.white)
        )
    }

    private func render<Content: View>(_ content: Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func renderedHeight<Content: View>(_ content: Content) throws -> Int {
        try render(content).height
    }

    private func renderedWidth<Content: View>(_ content: Content) throws -> Int {
        try render(content).width
    }

    func testMaterialChipWiresTiledHitShapeIntoBothVisualStates() throws {
        let gaps = MaterialChipNeighborGaps(
            top: 6,
            leading: 8,
            bottom: 10,
            trailing: 12
        )

        for state in [MaterialChipState.active, .available] {
            let chip = MaterialChip(
                "Chip",
                state: state,
                neighborGaps: gaps,
                action: {}
            )
            let body = chip.body
            let shape = try XCTUnwrap(
                firstDescendant(
                    of: MaterialChipHitTargetShape.self,
                    in: body
                )
            )
            let contentShapeKinds = try XCTUnwrap(
                firstDescendant(
                    of: ContentShapeKinds.self,
                    in: body
                )
            )

            XCTAssertEqual(shape.neighborGaps, gaps)
            XCTAssertEqual(contentShapeKinds, .interaction)
        }
    }

    private func firstDescendant<Descendant>(
        of type: Descendant.Type,
        in value: Any
    ) -> Descendant? {
        if let value = value as? Descendant {
            return value
        }
        for child in Mirror(reflecting: value).children {
            if let descendant = firstDescendant(of: type, in: child.value) {
                return descendant
            }
        }
        return nil
    }

#if canImport(AppKit)
    private func pixelData(in image: CGImage) throws -> Data {
        let bytesPerRow = image.width * 4
        var pixels = Data(
            count: bytesPerRow * image.height
        )
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: image.width,
                    height: image.height
                )
            )
        }
        return pixels
    }

    private func solidAccentPixelCount(in image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)

        return (0..<bitmap.pixelsHigh).reduce(into: 0) { count, y in
            for x in 0..<bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB)
                else {
                    continue
                }
                if color.greenComponent > color.redComponent + 0.2,
                   color.blueComponent > color.redComponent + 0.2,
                   color.greenComponent > color.blueComponent + 0.03,
                   color.alphaComponent > 0.98 {
                    count += 1
                }
            }
        }
    }
#endif

    private func color(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        opacity: Double = 1
    ) -> MaterialColor {
        MaterialColor(red: red, green: green, blue: blue, opacity: opacity)
    }
}
