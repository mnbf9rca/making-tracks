import SwiftUI
import XCTest
@testable import DesignSystem

#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class MaterialToastTests: XCTestCase {
    func testToastExpressesEveryRequiredContentShape() {
        XCTAssertEqual(
            MaterialToast(message: "Location is off").contentMode,
            .messageOnly
        )
        XCTAssertEqual(
            MaterialToast(
                message: "Download 42%",
                primaryAction: MaterialToastAction("Open") {}
            ).contentMode,
            .messageAndAction
        )
        XCTAssertEqual(
            MaterialToast(
                message: "You're near a place",
                primaryAction: MaterialToastAction("Seen it") {},
                dismissAction: {}
            ).contentMode,
            .messageActionAndDismiss
        )
    }

    func testToastUsesSnowForegroundActionAndHairlineTokens() {
        let appearance = MaterialToast(message: "Location is off").appearance(
            reduceTransparency: false
        )

        XCTAssertEqual(appearance.foreground, color(0x2B, 0x28, 0x23))
        XCTAssertEqual(appearance.action, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(appearance.stroke, color(0x2B, 0x28, 0x23, opacity: 0.14))
    }

    func testHorizontalCandidateMeasuresMessageAtIntrinsicWidthBeforeFallingBack() {
        let configuration = MaterialToast(
            message: "A deliberately long message that must not compress beside its actions",
            primaryAction: MaterialToastAction("Open") {}
        ).renderConfiguration(reduceTransparency: false)

        XCTAssertEqual(configuration.horizontalMessageWidth, .intrinsic)
        XCTAssertEqual(configuration.fallbackMessageWidth, .flexible)
    }

    func testRenderedPrimaryActionUsesTheResolvedAppearanceToken() {
        let toast = MaterialToast(
            message: "Download 42%",
            primaryAction: MaterialToastAction("Open") {}
        )
        let configuration = toast.renderConfiguration(reduceTransparency: false)

        XCTAssertEqual(configuration.action, toast.appearance(reduceTransparency: false).action)
        XCTAssertEqual(configuration.action, color(0x0A, 0x6B, 0x5C))
    }

    func testRenderedControlsRetainAccessibilityIdentifiersAndDismissTarget() {
        let toast = MaterialToast(
            message: "You're near a place",
            primaryAction: MaterialToastAction(
                "Seen it",
                accessibilityIdentifier: "map.nearby-prompt.seen"
            ) {},
            dismissAction: {},
            dismissAccessibilityIdentifier: "map.nearby-prompt.dismiss"
        )
        let configuration = toast.renderConfiguration(reduceTransparency: false)

        XCTAssertEqual(
            configuration.primaryActionAccessibilityIdentifier,
            "map.nearby-prompt.seen"
        )
        XCTAssertEqual(
            configuration.dismissAccessibilityIdentifier,
            "map.nearby-prompt.dismiss"
        )
        XCTAssertGreaterThanOrEqual(configuration.dismissMinimumTarget.width, 44)
        XCTAssertGreaterThanOrEqual(configuration.dismissMinimumTarget.height, 44)
    }

#if canImport(AppKit)
    func testRenderedDismissControlIsAtLeastFortyFourPointsInBothDimensions() {
        let control = MaterialToastDismissButton(
            action: {},
            accessibilityLabel: "Dismiss",
            accessibilityIdentifier: "map.nearby-prompt.dismiss",
            minimumTarget: CGSize(width: 44, height: 44)
        )
        let hostingController = NSHostingController(rootView: control)

        let renderedSize = hostingController.view.fittingSize

        XCTAssertGreaterThanOrEqual(renderedSize.width, 44)
        XCTAssertGreaterThanOrEqual(renderedSize.height, 44)
    }
#endif

    func testCallerCanInjectLeadingAndArbitraryStyledActionContent() {
        let toast = MaterialToast(
            message: "Location is off",
            primaryActionAccessibilityIdentifier: "map.location-settings",
            leadingContent: {
                Image(systemName: "location.slash")
            },
            actionContent: {
                Button("Settings") {}
                    .buttonStyle(.bordered)
            }
        )
        let configuration = toast.renderConfiguration(reduceTransparency: false)

        XCTAssertEqual(toast.contentMode, .messageAndAction)
        XCTAssertTrue(configuration.hasLeadingContent)
        XCTAssertTrue(configuration.usesCustomActionContent)
        XCTAssertEqual(
            configuration.primaryActionAccessibilityIdentifier,
            "map.location-settings"
        )
    }

    func testWholeSurfaceActionIsExpressibleAndPerformsOnce() {
        var invocations = 0
        let toast = MaterialToast(
            message: "Download 42%",
            surfaceAction: {
                invocations += 1
            },
            surfaceAccessibilityIdentifier: "map.download-progress",
            leadingContent: {
                Image(systemName: "arrow.down.circle")
            }
        )
        let configuration = toast.renderConfiguration(reduceTransparency: false)

        XCTAssertTrue(configuration.hasSurfaceAction)
        XCTAssertEqual(
            configuration.surfaceAccessibilityIdentifier,
            "map.download-progress"
        )

        toast.performSurfaceAction()

        XCTAssertEqual(invocations, 1)
    }

    func testSnowRenderingPinsLightColorSchemeForDeterministicContrast() {
        let configuration = MaterialToast(
            message: "Location is off"
        ).renderConfiguration(reduceTransparency: false)

        XCTAssertEqual(configuration.colorScheme, .light)
    }

    func testToastUsesOneRegularMaterialRecipeUnlessTransparencyIsReduced() {
        let toast = MaterialToast(message: "Location is off")

        XCTAssertEqual(toast.appearance(reduceTransparency: false).backdrop, .regularMaterial)
        XCTAssertEqual(
            toast.appearance(reduceTransparency: true).backdrop,
            .solid(color(0xFB, 0xFA, 0xF2))
        )
    }

    func testActionPerformsItsRealClosureOnce() {
        var invocations = 0
        let action = MaterialToastAction("Open") {
            invocations += 1
        }

        action.perform()

        XCTAssertEqual(invocations, 1)
    }

    func testDismissAccessibilityLabelDefaultsToDismissAndCanBeSpecific() {
        XCTAssertEqual(
            MaterialToast(message: "Location is off", dismissAction: {}).dismissAccessibilityLabel,
            "Dismiss"
        )
        XCTAssertEqual(
            MaterialToast(
                message: "You're near a place",
                dismissAction: {},
                dismissAccessibilityLabel: "Dismiss nearby place prompt"
            ).dismissAccessibilityLabel,
            "Dismiss nearby place prompt"
        )
    }

    private func color(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        opacity: Double = 1
    ) -> MaterialColor {
        MaterialColor(red: red, green: green, blue: blue, opacity: opacity)
    }
}
