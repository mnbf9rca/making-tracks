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
        XCTAssertEqual(
            MaterialToast(
                message: "Location is off",
                dismissAction: {}
            ).contentMode,
            .messageAndDismiss
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
        guard case let .controls(controls) = configuration.interaction else {
            return XCTFail("Control toast resolved as a whole-surface action")
        }

        XCTAssertEqual(
            controls.primaryActionAccessibilityIdentifier,
            "map.nearby-prompt.seen"
        )
        XCTAssertEqual(
            controls.dismissAccessibilityIdentifier,
            "map.nearby-prompt.dismiss"
        )
        XCTAssertGreaterThanOrEqual(controls.minimumInteractiveTarget.width, 44)
        XCTAssertGreaterThanOrEqual(controls.minimumInteractiveTarget.height, 44)
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

    func testRenderedBuiltInPrimaryActionIsAtLeastFortyFourPointsInBothDimensions() {
        let control = MaterialToastPrimaryActionButton(
            action: MaterialToastAction(
                "Open",
                accessibilityIdentifier: "map.download.open"
            ) {},
            foreground: color(0x0A, 0x6B, 0x5C),
            minimumTarget: CGSize(width: 44, height: 44)
        )
        let hostingController = NSHostingController(rootView: control)

        let renderedSize = hostingController.view.fittingSize

        XCTAssertGreaterThanOrEqual(renderedSize.width, 44)
        XCTAssertGreaterThanOrEqual(renderedSize.height, 44)
    }

    func testRenderedTinyCustomActionIsAtLeastFortyFourPointsInBothDimensions() {
        let control = MaterialToastCustomActionWrapper(
            accessibilityIdentifier: "map.location-settings",
            minimumTarget: CGSize(width: 44, height: 44)
        ) {
            Button(action: {}) {
                Color.clear
                    .frame(width: 1, height: 1)
            }
            .buttonStyle(.plain)
        }
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
        guard case let .controls(controls) = configuration.interaction else {
            return XCTFail("Custom-action toast resolved as a whole-surface action")
        }

        XCTAssertEqual(toast.contentMode, .messageAndAction)
        XCTAssertTrue(controls.hasLeadingContent)
        XCTAssertTrue(controls.usesCustomActionContent)
        XCTAssertEqual(
            controls.primaryActionAccessibilityIdentifier,
            "map.location-settings"
        )
    }

    func testSurfaceDescriptorIsClosedToInnerControlsAndPerformsOnce() {
        var invocations = 0
        let surfaceAction = MaterialToastSurfaceAction(
            accessibilityLabel: "Offline maps download progress",
            accessibilityHint: "Opens Offline maps",
            accessibilityIdentifier: "map.download-progress"
        ) {
            invocations += 1
        }
        let toast = MaterialToast(
            message: "Download 42%",
            surfaceAction: surfaceAction,
            leadingSystemImage: "arrow.down.circle",
            progressState: .percentage(42)
        )
        let configuration = toast.renderConfiguration(reduceTransparency: false)
        guard case let .surface(surface) = configuration.interaction else {
            return XCTFail("Whole-surface toast resolved as inner controls")
        }

        XCTAssertEqual(toast.contentMode, .messageOnly)
        XCTAssertEqual(surface.accessibilityLabel, "Offline maps download progress")
        XCTAssertEqual(surface.accessibilityHint, "Opens Offline maps")
        XCTAssertEqual(surface.accessibilityIdentifier, "map.download-progress")
        XCTAssertEqual(surface.accessibilityValue, "42%")
        XCTAssertEqual(surface.leadingSystemImage, "arrow.down.circle")
        XCTAssertEqual(surface.progressState, .percentage(42))

        surfaceAction.perform()

        XCTAssertEqual(invocations, 1)
    }

    func testSurfaceConfigurationSpeaksCountSuffixWithDescriptorMetadata() {
        let toast = MaterialToast(
            message: "List progress",
            surfaceAction: MaterialToastSurfaceAction(
                accessibilityLabel: "List progress",
                accessibilityHint: "Opens the list",
                accessibilityIdentifier: "map.list-progress"
            ) {},
            progressState: .count(
                completed: 3,
                total: 8,
                suffix: "seen"
            )
        )
        let configuration = toast.renderConfiguration(reduceTransparency: false)
        guard case let .surface(surface) = configuration.interaction else {
            return XCTFail("Whole-surface toast resolved as inner controls")
        }

        XCTAssertEqual(surface.accessibilityLabel, "List progress")
        XCTAssertEqual(surface.accessibilityHint, "Opens the list")
        XCTAssertEqual(surface.accessibilityIdentifier, "map.list-progress")
        XCTAssertEqual(surface.accessibilityValue, "3 of 8 seen")
    }

    func testSurfaceConfigurationOmitsAccessibilityValueWithoutProgress() {
        let toast = MaterialToast(
            message: "Offline maps",
            surfaceAction: MaterialToastSurfaceAction(
                accessibilityLabel: "Offline maps",
                accessibilityHint: "Opens Offline maps",
                accessibilityIdentifier: "map.offline"
            ) {}
        )
        let configuration = toast.renderConfiguration(reduceTransparency: false)
        guard case let .surface(surface) = configuration.interaction else {
            return XCTFail("Whole-surface toast resolved as inner controls")
        }

        XCTAssertNil(surface.accessibilityValue)
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
