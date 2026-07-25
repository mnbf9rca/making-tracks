import XCTest
@testable import DesignSystem

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
