#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import XCTest
@testable import DesignSystem

@MainActor
final class ControlStylesTests: XCTestCase {
    func testMaterialControlInteractionFeedbackPreservesEnabledOpacity() {
        XCTAssertEqual(
            MaterialControlInteractionFeedback.semanticControlOpacity(
                isEnabled: true,
                tokens: MaterialTheme.snow.tokens
            ),
            1
        )
        XCTAssertEqual(
            MaterialControlInteractionFeedback.semanticControlOpacity(
                isEnabled: false,
                tokens: MaterialTheme.snow.tokens
            ),
            0.46
        )
    }

    func testMaterialControlInteractionFeedbackUsesScaleForPresses() {
        XCTAssertEqual(
            MaterialControlInteractionFeedback.semanticControlScale(
                isPressed: false,
                tokens: MaterialTheme.snow.tokens
            ),
            1
        )
        XCTAssertEqual(
            MaterialControlInteractionFeedback.semanticControlScale(
                isPressed: true,
                tokens: MaterialTheme.snow.tokens
            ),
            0.98
        )
    }

    func testMaterialControlInteractionFeedbackReadsTheProvidedSheetRows() {
        let sheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 0.87
        )

        XCTAssertEqual(
            MaterialControlInteractionFeedback.semanticControlOpacity(
                isEnabled: false,
                tokens: sheet
            ),
            0.23
        )
        XCTAssertEqual(
            MaterialControlInteractionFeedback.semanticControlScale(
                isPressed: true,
                tokens: sheet
            ),
            0.87
        )
    }

    func testButtonStylesResolveTheThreeRatifiedSemanticPalettes() {
        let filled = MaterialFilledButtonStyle().appearance
        XCTAssertEqual(filled.foreground, color(0xFB, 0xFA, 0xF2))
        XCTAssertEqual(filled.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(filled.backgroundOpacity, 1)

        let tonal = MaterialTonalButtonStyle().appearance
        XCTAssertEqual(tonal.foreground, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(tonal.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(
            tonal.backgroundOpacity,
            MaterialTheme.snow.tokens.tonalContainerCompositeOpacity
        )

        let quiet = MaterialQuietButtonStyle().appearance
        XCTAssertEqual(quiet.foreground, color(0x6B, 0x67, 0x5F))
        XCTAssertNil(quiet.background)
        XCTAssertEqual(quiet.backgroundOpacity, 0)
    }

    func testButtonStylesResolveTheirRatifiedPressFeedback() {
        let filled = MaterialFilledButtonStyle().pressFeedback
        let tonal = MaterialTonalButtonStyle().pressFeedback
        let quiet = MaterialQuietButtonStyle().pressFeedback
        let quietText = MaterialQuietButtonStyle.textOnly().pressFeedback

        XCTAssertEqual(filled, .scale)
        XCTAssertEqual(tonal, .scale)
        XCTAssertEqual(quiet, .symbolWeightPulse)
        XCTAssertEqual(quietText, .textInset(points: 1))

        for feedback in [filled, tonal] {
            XCTAssertEqual(feedback.symbolWeight(isPressed: false), .standard)
            XCTAssertEqual(feedback.symbolWeight(isPressed: true), .standard)
        }
        XCTAssertEqual(quiet.symbolWeight(isPressed: false), .standard)
        XCTAssertEqual(quiet.symbolWeight(isPressed: true), .emphasized)
        XCTAssertEqual(quietText.symbolWeight(isPressed: false), .standard)
        XCTAssertEqual(quietText.symbolWeight(isPressed: true), .standard)
        XCTAssertEqual(
            quietText.verticalOffset(
                isPressed: true,
                isEnabled: true,
                scaledTextInsetPoints: 3
            ),
            3
        )
        XCTAssertEqual(
            quietText.verticalOffset(
                isPressed: true,
                isEnabled: false,
                scaledTextInsetPoints: 3
            ),
            0
        )
    }

    func testQuietTextInsetUsesItsPairedButtonTypographyAnchor() {
        assertTypographyTextStyle(
            MaterialControlPressFeedback.textInsetTypographyAnchor,
            equals: TypographyRole.button.specification.textStyle
        )
    }

    func testStateToggleStyleResolvesOpaqueSemanticPalette() {
        let style = MaterialStateToggleButtonStyle(
            foreground: .accent,
            background: .accentContainer
        )

        XCTAssertEqual(style.appearance.foreground, MaterialTheme.snow.tokens.accent)
        XCTAssertEqual(style.appearance.background, MaterialTheme.snow.tokens.accentContainer)
        XCTAssertEqual(style.appearance.backgroundOpacity, 1)
        XCTAssertEqual(style.pressFeedback, .scale)
    }

    func testChipStatesMapActiveToFilledAndAvailableToTonal() {
        let active = MaterialChipState.active.appearance
        XCTAssertEqual(active.foreground, color(0xFB, 0xFA, 0xF2))
        XCTAssertEqual(active.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(active.backgroundOpacity, 1)

        let available = MaterialChipState.available.appearance
        XCTAssertEqual(available.foreground, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(available.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(
            available.backgroundOpacity,
            MaterialTheme.snow.tokens.tonalContainerCompositeOpacity
        )
    }

    func testTonalAppearanceReadsCompositeOpacityFromProvidedSheet() {
        let sheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 0.87,
            tonalContainerCompositeOpacity: 0.27
        )

        XCTAssertEqual(
            MaterialControlAppearance.tonal(tokens: sheet).backgroundOpacity,
            0.27
        )
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
    func testMaterialChipStyleBodyReadsProvidedInteractionRows() throws {
        let sheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 0.87
        )
        let restingBounds = try snowAccentBounds(
            in: renderChipStyleBody(isPressed: false, tokens: sheet)
        )
        let pressedBounds = try snowAccentBounds(
            in: renderChipStyleBody(isPressed: true, tokens: sheet)
        )

        assertGeometry(
            pressed: pressedBounds,
            resting: restingBounds,
            scale: 0.87
        )
        try assertCenterAccentAlpha(
            in: renderChipStyleBody(
                isPressed: false,
                tokens: sheet,
                isEnabled: false,
                overTransparency: true
            ),
            equals: 0.23
        )
    }

    func testMaterialButtonStyleBodyReadsProvidedInteractionRows() throws {
        let sheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 0.87
        )
        let restingBounds = try snowAccentBounds(
            in: renderButtonStyleBody(isPressed: false, tokens: sheet)
        )
        let pressedBounds = try snowAccentBounds(
            in: renderButtonStyleBody(isPressed: true, tokens: sheet)
        )

        assertGeometry(
            pressed: pressedBounds,
            resting: restingBounds,
            scale: 0.87
        )
        try assertCenterAccentAlpha(
            in: renderButtonStyleBody(
                isPressed: false,
                tokens: sheet,
                isEnabled: false,
                overTransparency: true
            ),
            equals: 0.23
        )
    }

    func testDisabledStateTogglePreservesOpaqueSemanticFill() throws {
        let image = try render(
            Button(action: {}) {
                Color.clear.frame(width: 400, height: 400)
            }
            .buttonStyle(
                MaterialStateToggleButtonStyle(
                    foreground: .accentContrast,
                    background: .accent
                )
            )
            .disabled(true)
            .padding(12)
            .background(Color.clear)
        )

        try assertCenterAccentAlpha(in: image, equals: 1)
    }

    func testPressedMaterialChipBodyPreservesOpaqueSemanticPixels() throws {
        let image = try renderChipStyleBody(isPressed: true)

        try assertCenterPixelIsSnowAccent(in: image)
    }

    func testPressedMaterialButtonBodyPreservesOpaqueSemanticPixels() throws {
        let image = try renderButtonStyleBody(isPressed: true)

        try assertCenterPixelIsSnowAccent(in: image)
    }

    func testPressedMaterialChipBodyRendersAtNinetyEightPercentGeometry() throws {
        let restingBounds = try snowAccentBounds(
            in: renderChipStyleBody(isPressed: false)
        )
        let pressedBounds = try snowAccentBounds(
            in: renderChipStyleBody(isPressed: true)
        )

        assertNinetyEightPercentGeometry(
            pressed: pressedBounds,
            resting: restingBounds
        )
    }

    func testPressedMaterialButtonBodyRendersAtNinetyEightPercentGeometry() throws {
        let restingBounds = try snowAccentBounds(
            in: renderButtonStyleBody(isPressed: false)
        )
        let pressedBounds = try snowAccentBounds(
            in: renderButtonStyleBody(isPressed: true)
        )

        assertNinetyEightPercentGeometry(
            pressed: pressedBounds,
            resting: restingBounds
        )
    }

    func testQuietIconRoleBodyRetainsPressScaleAndPulsesSymbolWeight() throws {
        let sheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 0.87
        )
        let feedback = MaterialQuietButtonStyle().pressFeedback

        XCTAssertEqual(feedback.scale(isPressed: false, tokens: sheet), 1)
        XCTAssertEqual(feedback.scale(isPressed: true, tokens: sheet), 0.87)

        let unscaledSheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 1
        )
        let resting = try renderQuietButtonStyleBody(
            isPressed: false,
            tokens: unscaledSheet
        ) {
            Image(systemName: "gearshape.fill")
                .iconRole(.inline)
        }
        let pressed = try renderQuietButtonStyleBody(
            isPressed: true,
            tokens: unscaledSheet
        ) {
            Image(systemName: "gearshape.fill")
                .iconRole(.inline)
        }

        try assertQuietSymbolWeightPulse(
            resting: resting,
            pressed: pressed
        )
    }

    func testQuietEmptyTitleLabelBodyPulsesSymbolWeight() throws {
        let unscaledSheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 1
        )
        let resting = try renderQuietButtonStyleBody(
            isPressed: false,
            tokens: unscaledSheet
        ) {
            Label("", systemImage: "gearshape.fill")
        }
        let pressed = try renderQuietButtonStyleBody(
            isPressed: true,
            tokens: unscaledSheet
        ) {
            Label("", systemImage: "gearshape.fill")
        }

        try assertQuietSymbolWeightPulse(
            resting: resting,
            pressed: pressed
        )
    }

    func testQuietVisibleLabelKeepsTitleStableWhileItsIconPulses() throws {
        let sheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 1
        )
        let resting = try renderQuietButtonStyleBody(
            isPressed: false,
            tokens: sheet
        ) {
            Label("Settings", systemImage: "gearshape.fill")
        }
        let pressed = try renderQuietButtonStyleBody(
            isPressed: true,
            tokens: sheet
        ) {
            Label("Settings", systemImage: "gearshape.fill")
        }

        let restingTitleRegion = try trailingTitleRegion(in: resting)
        let pressedTitleRegion = try trailingTitleRegion(in: pressed)
        let restingTitleBounds = try nonTransparentBounds(in: restingTitleRegion)
        XCTAssertGreaterThan(restingTitleBounds.width, 15)
        XCTAssertGreaterThan(restingTitleBounds.height, 5)
        assertPixelsAreVisuallyIdentical(
            try pixelData(in: restingTitleRegion),
            try pixelData(in: pressedTitleRegion)
        )

        let restingIconRegion = try leadingIconRegion(in: resting)
        let pressedIconRegion = try leadingIconRegion(in: pressed)
        XCTAssertGreaterThan(
            mutedGlyphCoverage(in: pressedIconRegion),
            mutedGlyphCoverage(in: restingIconRegion) + 500
        )
    }

    func testQuietTextOnlyBodyAddsRuledInsetToPressScale() throws {
        let feedback = MaterialQuietButtonStyle.textOnly().pressFeedback
        let unscaledSheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 1
        )
        let unscaledResting = try renderQuietButtonStyleBody(
            isPressed: false,
            tokens: unscaledSheet,
            pressFeedback: feedback
        ) {
            Text("Settings")
        }
        let unscaledPressed = try renderQuietButtonStyleBody(
            isPressed: true,
            tokens: unscaledSheet,
            pressFeedback: feedback
        ) {
            Text("Settings")
        }
        let unscaledRestingBounds = try nonTransparentBounds(in: unscaledResting)
        let unscaledPressedBounds = try nonTransparentBounds(in: unscaledPressed)
        let defaultDisplacement =
            unscaledPressedBounds.minY - unscaledRestingBounds.minY
        XCTAssertEqual(unscaledPressedBounds.minX, unscaledRestingBounds.minX)
        XCTAssertEqual(defaultDisplacement, 1)
        XCTAssertEqual(unscaledPressedBounds.size, unscaledRestingBounds.size)

        let disabledResting = try renderQuietButtonStyleBody(
            isPressed: false,
            isEnabled: false,
            tokens: unscaledSheet,
            pressFeedback: feedback
        ) {
            Text("Settings")
        }
        let disabledPressed = try renderQuietButtonStyleBody(
            isPressed: true,
            isEnabled: false,
            tokens: unscaledSheet,
            pressFeedback: feedback
        ) {
            Text("Settings")
        }
        assertPixelsAreVisuallyIdentical(
            try pixelData(in: disabledResting),
            try pixelData(in: disabledPressed)
        )

        let scaledSheet = makeInteractionSheet(
            disabledAlpha: 0.23,
            pressScale: 0.87
        )
        let scaledResting = try renderQuietButtonStyleBody(
            isPressed: false,
            tokens: scaledSheet,
            pressFeedback: feedback
        ) {
            Text("Settings")
                .font(.system(size: 60))
        }
        let scaledPressed = try renderQuietButtonStyleBody(
            isPressed: true,
            tokens: scaledSheet,
            pressFeedback: feedback
        ) {
            Text("Settings")
                .font(.system(size: 60))
        }
        let scaledRestingBounds = try nonTransparentBounds(in: scaledResting)
        let scaledPressedBounds = try nonTransparentBounds(in: scaledPressed)
        assertGeometry(
            pressed: scaledPressedBounds,
            resting: scaledRestingBounds,
            scale: 0.87
        )
    }

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
        assertPixelsAreVisuallyIdentical(
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

    func testMaterialChipExpandedSizeOwnsFrozenAccessibilityGeometry() throws {
        XCTAssertEqual(MaterialChipSize.expanded.minimumHeight, 38)
        XCTAssertEqual(MaterialChipSize.expanded.horizontalPadding, 14)
        XCTAssertEqual(MaterialChipSize.expanded.verticalPadding, 5)
        XCTAssertEqual(MaterialChipSize.expanded.labelSpacing, 6)

        let title = "Map"
        let chip = MaterialChip(
            title,
            state: .active,
            size: .expanded,
            action: {}
        )
        .dynamicTypeSize(.accessibility5)
        let styledTitle = Text(title)
            .font(MaterialChip.titleFont)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(.accessibility5)

        XCTAssertGreaterThanOrEqual(try renderedHeight(chip), 38)
        XCTAssertEqual(
            try renderedWidth(chip) - renderedWidth(styledTitle),
            28,
            accuracy: 1
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

    func testMaterialChipWiresAccessoryRoleAtPointOfUse() throws {
        let chip = MaterialChip(
            "Map",
            systemImage: "map",
            state: .active,
            action: {}
        )

        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: chip.body
                )
            ),
            .accessory
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

    private func makeInteractionSheet(
        disabledAlpha: Double,
        pressScale: CGFloat,
        tonalContainerCompositeOpacity: Double = 0.12
    ) -> MaterialTokenSheet {
        let snow = MaterialTheme.snow.tokens
        return MaterialTokenSheet(
            ground: snow.ground,
            water: snow.water,
            park: snow.park,
            road: snow.road,
            roadMinor: snow.roadMinor,
            surface: snow.surface,
            surfaceRaised: snow.surfaceRaised,
            ink: snow.ink,
            muted: snow.muted,
            accent: snow.accent,
            accentContainer: snow.accentContainer,
            accentDeepContainer: snow.accentDeepContainer,
            accentContrast: snow.accentContrast,
            love: snow.love,
            loveContainer: snow.loveContainer,
            warning: snow.warning,
            warningContainer: snow.warningContainer,
            eyebrow: snow.eyebrow,
            hairline: snow.hairline,
            scrim: snow.scrim,
            shadow: snow.shadow,
            background: snow.background,
            labels: snow.labels,
            labelHalo: snow.labelHalo,
            boundaries: snow.boundaries,
            trail: snow.trail,
            tonalContainerCompositeOpacity: tonalContainerCompositeOpacity,
            disabledAlpha: disabledAlpha,
            pressScale: pressScale
        )
    }

#if canImport(AppKit)
    private func renderChipStyleBody(
        isPressed: Bool,
        tokens: MaterialTokenSheet = MaterialTheme.snow.tokens,
        isEnabled: Bool = true,
        overTransparency: Bool = false
    ) throws -> CGImage {
        try render(
            MaterialChipStyleBody(
                label: Color.clear.frame(width: 400, height: 400),
                isPressed: isPressed,
                appearance: .filled(tokens: tokens),
                tokens: tokens,
                size: .compact
            )
            .padding(12)
            .environment(\.isEnabled, isEnabled)
            .background(
                overTransparency
                    ? Color.clear
                    : MaterialTheme.snow.tokens.surface.swiftUIColor
            )
        )
    }

    private func renderButtonStyleBody(
        isPressed: Bool,
        tokens: MaterialTokenSheet = MaterialTheme.snow.tokens,
        isEnabled: Bool = true,
        overTransparency: Bool = false
    ) throws -> CGImage {
        try render(
            MaterialButtonStyleBody(
                label: Color.clear.frame(width: 400, height: 400),
                isPressed: isPressed,
                appearance: .filled(tokens: tokens),
                tokens: tokens,
                pressFeedback: .scale,
                accessibilityValue: { _ in nil }
            )
            .padding(12)
            .environment(\.isEnabled, isEnabled)
            .background(
                overTransparency
                    ? Color.clear
                    : MaterialTheme.snow.tokens.surface.swiftUIColor
            )
        )
    }

    private func renderQuietButtonStyleBody<Label: View>(
        isPressed: Bool,
        isEnabled: Bool = true,
        tokens: MaterialTokenSheet,
        pressFeedback: MaterialControlPressFeedback =
            MaterialQuietButtonStyle().pressFeedback,
        @ViewBuilder label: () -> Label
    ) throws -> CGImage {
        try render(
            MaterialButtonStyleBody(
                label: label(),
                isPressed: isPressed,
                appearance: .quiet(tokens: tokens),
                tokens: tokens,
                pressFeedback: pressFeedback,
                accessibilityValue: { _ in nil }
            )
            .disabled(!isEnabled)
            .frame(width: 180, height: 96)
            .background(Color.clear)
        )
    }
#endif

    private func render<Content: View>(_ content: Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func assertTypographyTextStyle(
        _ actual: TypographyTextStyle,
        equals expected: TypographyTextStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let matches = switch (actual, expected) {
        case (.largeTitle, .largeTitle),
            (.title1, .title1),
            (.title2, .title2),
            (.headline, .headline),
            (.body, .body),
            (.subheadline, .subheadline),
            (.footnote, .footnote),
            (.caption2, .caption2):
            true
        default:
            false
        }
        XCTAssertTrue(
            matches,
            "Expected \(expected), got \(actual)",
            file: file,
            line: line
        )
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
    private func assertCenterPixelIsSnowAccent(
        in image: CGImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let expected = try literalSnowAccentPixel()
        let center = try XCTUnwrap(
            bitmap.colorAt(
                x: bitmap.pixelsWide / 2,
                y: bitmap.pixelsHigh / 2
            )?.usingColorSpace(.sRGB),
            file: file,
            line: line
        )

        XCTAssertEqual(
            center.redComponent,
            expected.redComponent,
            accuracy: 0.01,
            file: file,
            line: line
        )
        XCTAssertEqual(
            center.greenComponent,
            expected.greenComponent,
            accuracy: 0.01,
            file: file,
            line: line
        )
        XCTAssertEqual(
            center.blueComponent,
            expected.blueComponent,
            accuracy: 0.01,
            file: file,
            line: line
        )
        XCTAssertEqual(
            center.alphaComponent,
            expected.alphaComponent,
            accuracy: 0.001,
            file: file,
            line: line
        )
    }

    private func assertCenterAccentAlpha(
        in image: CGImage,
        equals expected: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let center = try XCTUnwrap(
            bitmap.colorAt(
                x: bitmap.pixelsWide / 2,
                y: bitmap.pixelsHigh / 2
            )?.usingColorSpace(.sRGB),
            file: file,
            line: line
        )

        XCTAssertEqual(
            center.alphaComponent,
            expected,
            accuracy: 0.01,
            file: file,
            line: line
        )
    }

    private func snowAccentBounds(in image: CGImage) throws -> CGRect {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let expected = try literalSnowAccentPixel()
        var minX = bitmap.pixelsWide
        var minY = bitmap.pixelsHigh
        var maxX = -1
        var maxY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB),
                    abs(color.redComponent - expected.redComponent) < 0.01,
                    abs(color.greenComponent - expected.greenComponent) < 0.01,
                    abs(color.blueComponent - expected.blueComponent) < 0.01,
                    abs(color.alphaComponent - expected.alphaComponent) < 0.001
                else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        _ = try XCTUnwrap(maxX > minX ? maxX : nil)
        _ = try XCTUnwrap(maxY > minY ? maxY : nil)
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private func literalSnowAccentPixel() throws -> NSColor {
        let image = try render(
            Color(
                .sRGB,
                red: 10.0 / 255.0,
                green: 107.0 / 255.0,
                blue: 92.0 / 255.0,
                opacity: 1
            )
            .frame(width: 4, height: 4)
        )
        let bitmap = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(
            bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB)
        )
    }

    private func literalSnowMutedPixel() throws -> NSColor {
        let image = try render(
            Color(
                .sRGB,
                red: 107.0 / 255.0,
                green: 103.0 / 255.0,
                blue: 95.0 / 255.0,
                opacity: 1
            )
            .frame(width: 4, height: 4)
        )
        let bitmap = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(
            bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB)
        )
    }

    private func assertQuietSymbolWeightPulse(
        resting: CGImage,
        pressed: CGImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(resting.width, pressed.width, file: file, line: line)
        XCTAssertEqual(resting.height, pressed.height, file: file, line: line)

        let expected = try literalSnowMutedPixel()
        let restingBounds = try nonTransparentBounds(in: resting)
        let pressedBounds = try nonTransparentBounds(in: pressed)
        XCTAssertLessThan(restingBounds.width, 30, file: file, line: line)
        XCTAssertLessThan(restingBounds.height, 30, file: file, line: line)
        XCTAssertLessThan(pressedBounds.width, 30, file: file, line: line)
        XCTAssertLessThan(pressedBounds.height, 30, file: file, line: line)

        let restingCoverage = mutedGlyphCoverage(in: resting)
        let pressedCoverage = mutedGlyphCoverage(in: pressed)
        XCTAssertGreaterThan(
            pressedCoverage,
            restingCoverage + 500,
            file: file,
            line: line
        )

        let restingOpaquePixels = assertOpaquePixelsAreLiteralSnowMuted(
            in: resting,
            expected: expected,
            file: file,
            line: line
        )
        let pressedOpaquePixels = assertOpaquePixelsAreLiteralSnowMuted(
            in: pressed,
            expected: expected,
            file: file,
            line: line
        )
        XCTAssertGreaterThan(restingOpaquePixels, 20, file: file, line: line)
        XCTAssertGreaterThan(pressedOpaquePixels, 20, file: file, line: line)
    }

    private func mutedGlyphCoverage(in image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return (0..<bitmap.pixelsHigh).reduce(into: 0) { coverage, y in
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB) else {
                    continue
                }
                coverage += Int((color.alphaComponent * 255).rounded())
            }
        }
    }

    private func assertOpaquePixelsAreLiteralSnowMuted(
        in image: CGImage,
        expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var count = 0

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB),
                    color.alphaComponent > 0.99
                else {
                    continue
                }
                count += 1
                XCTAssertEqual(
                    color.redComponent,
                    expected.redComponent,
                    accuracy: 0.01,
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    color.greenComponent,
                    expected.greenComponent,
                    accuracy: 0.01,
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    color.blueComponent,
                    expected.blueComponent,
                    accuracy: 0.01,
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    color.alphaComponent,
                    expected.alphaComponent,
                    accuracy: 0.01,
                    file: file,
                    line: line
                )
            }
        }
        return count
    }

    private func nonTransparentBounds(in image: CGImage) throws -> CGRect {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var minX = bitmap.pixelsWide
        var minY = bitmap.pixelsHigh
        var maxX = -1
        var maxY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB),
                    color.alphaComponent > 0.01
                else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        _ = try XCTUnwrap(maxX > minX ? maxX : nil)
        _ = try XCTUnwrap(maxY > minY ? maxY : nil)
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private func leadingIconRegion(in image: CGImage) throws -> CGImage {
        try XCTUnwrap(
            image.cropping(
                to: CGRect(
                    x: 0,
                    y: 0,
                    width: image.width / 2,
                    height: image.height
                )
            )
        )
    }

    private func trailingTitleRegion(in image: CGImage) throws -> CGImage {
        try XCTUnwrap(
            image.cropping(
                to: CGRect(
                    x: image.width / 2,
                    y: 0,
                    width: image.width / 2,
                    height: image.height
                )
            )
        )
    }

    private func assertNinetyEightPercentGeometry(
        pressed: CGRect,
        resting: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            pressed.width / resting.width,
            0.98,
            accuracy: 0.01,
            file: file,
            line: line
        )
        XCTAssertEqual(
            pressed.height / resting.height,
            0.98,
            accuracy: 0.01,
            file: file,
            line: line
        )
    }

    private func assertGeometry(
        pressed: CGRect,
        resting: CGRect,
        scale: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            pressed.width / resting.width,
            scale,
            accuracy: 0.01,
            file: file,
            line: line
        )
        XCTAssertEqual(
            pressed.height / resting.height,
            scale,
            accuracy: 0.01,
            file: file,
            line: line
        )
    }

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

    private func assertPixelsAreVisuallyIdentical(
        _ lhs: Data,
        _ rhs: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        guard lhs.count == rhs.count else {
            return
        }

        for (offset, pair) in zip(lhs, rhs).enumerated() {
            XCTAssertLessThanOrEqual(
                abs(Int(pair.0) - Int(pair.1)),
                1,
                "8-bit channel differs at byte \(offset)",
                file: file,
                line: line
            )
        }
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
