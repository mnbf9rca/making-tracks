import CryptoKit
import Foundation
import XCTest

final class WorldBasemapResourceTests: XCTestCase {
    func testBundledWorldBasemapMatchesPinnedSha() throws {
        let resourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../App/Resources/protomaps-20260714-z0-6.pmtiles")
            .standardizedFileURL
        let data = try Data(contentsOf: resourceURL)
        XCTAssertEqual(data.count, 44_720_722)
        XCTAssertEqual(hexDigest(of: data), "31dc1dd37b93ba6a05f64a21b967989ac40f6740bc845a06e9ab0fb83773c19c")
    }

    private func hexDigest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
