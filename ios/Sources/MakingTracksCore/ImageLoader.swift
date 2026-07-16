import Foundation
import MakingTracksTiles

public final class ImageLoader: @unchecked Sendable {
    public static let maxImageBytes = 2 * 1024 * 1024

    private let delegate: ImageRedirectDelegate
    private let session: URLSession

    public convenience init() {
        self.init(configuration: .ephemeral)
    }

    init(configuration: URLSessionConfiguration) {
        delegate = ImageRedirectDelegate()
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    public func fetch(_ url: URL) async -> Data? {
        guard PlaceContentGuards.isAllowedImageURL(url) else { return nil }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  http.expectedContentLength <= Self.maxImageBytes || http.expectedContentLength == -1
            else { return nil }

            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maxImageBytes {
                    return nil
                }
            }
            return data
        } catch {
            return nil
        }
    }
}

private final class ImageRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              PlaceContentGuards.isAllowedImageURL(url)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
