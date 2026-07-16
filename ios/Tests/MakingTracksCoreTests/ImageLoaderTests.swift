import Foundation
import XCTest
@testable import MakingTracksCore

final class ImageLoaderTests: XCTestCase {
    override func tearDown() {
        RecordingImageURLProtocol.reset()
        super.tearDown()
    }

    func testInitialNonAllowlistedImageHostIsRefusedBeforeNetworkRequest() async throws {
        let loader = ImageLoader(configuration: recordingConfiguration())

        let data = await loader.fetch(URL(string: "https://evil.example/track.jpg")!)

        XCTAssertNil(data)
        XCTAssertEqual(RecordingImageURLProtocol.requestedURLs, [])
    }

    func testRedirectFromWikimediaToAttackerHostIsNotFollowed() async throws {
        RecordingImageURLProtocol.response = .redirect(to: "https://evil.example/track.jpg")
        let loader = ImageLoader(configuration: recordingConfiguration())

        let data = await loader.fetch(URL(string: "https://upload.wikimedia.org/file.jpg")!)

        XCTAssertNil(data)
        XCTAssertEqual(
            RecordingImageURLProtocol.requestedURLs.map(\.absoluteString),
            ["https://upload.wikimedia.org/file.jpg"]
        )
    }

    func testAllowlistedImageHostReturnsResponseData() async throws {
        RecordingImageURLProtocol.response = .ok(Data([1, 2, 3]))
        let loader = ImageLoader(configuration: recordingConfiguration())

        let data = await loader.fetch(URL(string: "https://commons.wikimedia.org/file.jpg")!)

        XCTAssertEqual(data, Data([1, 2, 3]))
    }
}

private func recordingConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingImageURLProtocol.self]
    return configuration
}

private final class RecordingImageURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case ok(Data)
        case redirect(to: String)
    }

    nonisolated(unsafe) static var requestedURLs: [URL] = []
    nonisolated(unsafe) static var response: Response = .ok(Data())

    static func reset() {
        requestedURLs = []
        response = .ok(Data())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestedURLs.append(request.url!)
        switch Self.response {
        case .ok(let data):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let location):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": location]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: location)!), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
