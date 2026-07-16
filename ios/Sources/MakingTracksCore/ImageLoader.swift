import Foundation
import MakingTracksTiles

public final class ImageLoader: @unchecked Sendable {
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
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode)
            else { return nil }
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
