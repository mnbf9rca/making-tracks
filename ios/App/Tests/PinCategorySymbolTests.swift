import UIKit
import XCTest
@testable import MakingTracks

final class PinCategorySymbolTests: XCTestCase {
    func testEveryRequiredCategoryIconHasRegisteredSymbol() {
        XCTAssertEqual(
            Set(PinCategoryImageRegistry.categorySymbolNames.keys),
            PinCategoryImageRegistry.requiredIconNames
        )
    }

    func testEveryRegisteredCategorySymbolResolvesToUIImage() {
        for (iconName, symbolName) in PinCategoryImageRegistry.categorySymbolNames.sorted(by: { $0.key < $1.key }) {
            XCTAssertNotNil(
                UIImage(systemName: symbolName),
                "\(iconName) uses missing SF Symbol \(symbolName)"
            )
        }
    }
}
