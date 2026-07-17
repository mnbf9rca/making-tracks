import CryptoKit
import Foundation
import XCTest
@testable import MakingTracks

final class WorldBasemapTests: XCTestCase {
    func testBundledWorldBasemapIsPresentInHostAppBundle() throws {
        let appBundle = try XCTUnwrap(hostAppBundle())
        let resourceURL = try XCTUnwrap(WorldBasemap.resourceURL(in: appBundle))
        let data = try Data(contentsOf: resourceURL)

        XCTAssertEqual(data.count, WorldBasemap.expectedBytes)
        XCTAssertEqual(hexDigest(of: data), WorldBasemap.expectedSHA256)
        XCTAssertEqual(WorldBasemap.pmtilesURL(in: appBundle), "pmtiles://\(resourceURL.absoluteString)")
    }

    func testMissingWorldBasemapReturnsNil() throws {
        let bundle = try makeTemporaryBundle(resource: nil)

        XCTAssertNil(WorldBasemap.resourceURL(in: bundle))
        XCTAssertNil(WorldBasemap.pmtilesURL(in: bundle))
    }

    func testCorruptWorldBasemapReturnsNil() throws {
        let bundle = try makeTemporaryBundle(resource: Data([0x00]))

        XCTAssertNil(WorldBasemap.resourceURL(in: bundle))
        XCTAssertNil(WorldBasemap.pmtilesURL(in: bundle))
    }

    private func hostAppBundle() -> Bundle? {
        let candidateURLs = [
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("MakingTracks.app"),
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("MakingTracks.app"),
        ]
        for url in candidateURLs {
            guard let bundle = Bundle(path: url.path),
                  bundle.url(forResource: WorldBasemap.resourceName, withExtension: "pmtiles") != nil
            else { continue }
            return bundle
        }
        return nil
    }

    private func makeTemporaryBundle(resource: Data?) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("world-basemap-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let infoPlist = root.appendingPathComponent("Info.plist")
        let info: [String: Any] = [
            "CFBundleIdentifier": "app.making-tracks.WorldBasemapTests",
            "CFBundlePackageType": "BNDL",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoPlist)

        if let resource {
            try resource.write(to: root.appendingPathComponent("\(WorldBasemap.resourceName).pmtiles"))
        }

        return try XCTUnwrap(Bundle(path: root.path))
    }

    private func hexDigest(of data: Data) -> String {
        data.sha256HexString
    }
}

private extension Data {
    var sha256HexString: String {
        return SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
