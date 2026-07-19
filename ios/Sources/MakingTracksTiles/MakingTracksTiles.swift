import CryptoKit
import Foundation
import MakingTracksData
import zlib

public enum TileLoadState: String, Codable, Sendable, Equatable {
    case ok
    case stale
    case updateAvailable
    case updateRequired
    case offline
    case manifestInvalid
    case unavailable
}

public enum SchemaCompatibility: Sendable, Equatable {
    case ok
    case tooNew
    case tooOld
}

public enum VersionGate {
    public static let readerVersion = 2
    public static let readerSchemaVersion = 1
    public static let regionIndexReaderSchemaVersion = 2
    public static let minSupportedSchemaVersion = 1

    public static func schema(readerMax: Int, dataVersion: Int, minSupported: Int) -> SchemaCompatibility {
        if dataVersion > readerMax { return .tooNew }
        if dataVersion < minSupported { return .tooOld }
        return .ok
    }

    public static func reader(
        readerVersion: Int = Self.readerVersion,
        minReaderVersion: Int,
        hasReadableCache: Bool
    ) -> TileLoadState {
        minReaderVersion > readerVersion
            ? (hasReadableCache ? .updateAvailable : .updateRequired)
            : .ok
    }
}

public struct BBox: Sendable, Equatable {
    public let minLon: Double
    public let minLat: Double
    public let maxLon: Double
    public let maxLat: Double

    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }
}

private let regionIDPattern = "^[a-z][a-z0-9_-]{0,63}$"

public struct TileCoordinate: Codable, Sendable, Hashable {
    public let z: Int
    public let x: Int
    public let y: Int

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }
}

public struct Attribution: Codable, Sendable, Equatable {
    public let source: String
    public let license: String
    public let text: String

    public init(source: String, license: String, text: String) {
        self.source = source
        self.license = license
        self.text = text
    }
}

public protocol TileFetching: Sendable {
    func fetch(_ url: URL) async throws -> Data
}

public protocol BoundedTileFetching: TileFetching {
    func fetch(_ url: URL, maxBytes: Int) async throws -> Data
}

public protocol OfflineRegionFetching: TileFetching {
    func download(_ url: URL) async throws -> URL
}

public protocol ConnectivityWaitingOfflineRegionFetching: OfflineRegionFetching {
    func fetch(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?
    ) async throws -> Data
    func download(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?
    ) async throws -> URL
}

public protocol ProgressReportingOfflineRegionFetching: ConnectivityWaitingOfflineRegionFetching {
    func download(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?,
        progress: (@Sendable (_ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)?
    ) async throws -> URL
}

extension ConnectivityWaitingOfflineRegionFetching {
    func fetch(_ url: URL, connectivityWaiting: (@Sendable () -> Void)?) async throws -> Data {
        try await fetch(
            url,
            connectivityWaiting: connectivityWaiting,
            connectivityAvailable: nil
        )
    }

    func download(_ url: URL, connectivityWaiting: (@Sendable () -> Void)?) async throws -> URL {
        try await download(
            url,
            connectivityWaiting: connectivityWaiting,
            connectivityAvailable: nil
        )
    }
}

public enum TileError: Error, Equatable {
    case invalidURL
    case untrustedHost
    case invalidRedirect
    case invalidCurrent
    case invalidManifest
    case invalidRegionIndex
    case invalidImageIndex
    case invalidTile
    case invalidOfflinePack
    case invalidBackgroundFetch
    case insufficientStorage
    case responseTooLarge
    case checksumMismatch
    case byteCountMismatch
    case compressedTooLarge
    case inflatedTooLarge
    case invalidGzip
    case httpStatus(Int)
    case downloadPaused
    case downloadCancelled
    case downloadAlreadyInProgress
}

public final class HTTPTileFetcher: ProgressReportingOfflineRegionFetching, BoundedTileFetching, @unchecked Sendable {
    public static let trustedHost = "tiles.making-tracks.app"
    // Tunable UI freshness cap: offline catalog availability must not block local state while connectivity is absent.
    private static let availabilityProbeTimeoutSeconds: TimeInterval = 8
    private let delegate: RedirectDelegate
    private let session: URLSession
    let configurationIdentifier: String?

    public convenience init() {
        self.init(configuration: .ephemeral)
    }

    public static func offlineForeground(allowsCellularDownloads: Bool = false) -> HTTPTileFetcher {
        HTTPTileFetcher(configuration: OfflineDownloadSession.foregroundConfiguration(allowsCellularDownloads: allowsCellularDownloads))
    }

    public static func offlineAvailabilityProbe(allowsCellularDownloads: Bool = false) -> HTTPTileFetcher {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = availabilityProbeTimeoutSeconds
        configuration.timeoutIntervalForResource = availabilityProbeTimeoutSeconds
        configuration.allowsExpensiveNetworkAccess = allowsCellularDownloads
        configuration.allowsConstrainedNetworkAccess = allowsCellularDownloads
        OfflineDownloadSession.harden(configuration)
        return HTTPTileFetcher(configuration: configuration)
    }

    public static func offlineBackground(identifier: String, allowsCellularDownloads: Bool = false) -> HTTPTileFetcher {
        HTTPTileFetcher(configuration: OfflineDownloadSession.backgroundConfiguration(
            identifier: identifier,
            allowsCellularDownloads: allowsCellularDownloads
        ))
    }

    init(configuration: URLSessionConfiguration) {
        configurationIdentifier = configuration.identifier
        if let identifier = configuration.identifier {
            let box = OfflineBackgroundSessionRegistry.shared.session(
                identifier: identifier,
                configuration: configuration
            )
            delegate = box.delegate
            session = box.session
        } else {
            delegate = RedirectDelegate()
            session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }
    }

    deinit {
        guard configurationIdentifier == nil else { return }
        session.invalidateAndCancel()
        delegate.cancelAll(with: URLError(.cancelled))
    }

    public func fetch(_ url: URL) async throws -> Data {
        try await fetch(url, connectivityWaiting: nil)
    }

    public func fetch(_ url: URL, maxBytes: Int) async throws -> Data {
        try await fetch(url, maxBytes: maxBytes, connectivityWaiting: nil, connectivityAvailable: nil)
    }

    public func fetch(_ url: URL, connectivityWaiting: (@Sendable () -> Void)?) async throws -> Data {
        try await fetch(url, connectivityWaiting: connectivityWaiting, connectivityAvailable: nil)
    }

    public func fetch(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?
    ) async throws -> Data {
        try await fetch(url, maxBytes: nil, connectivityWaiting: connectivityWaiting, connectivityAvailable: connectivityAvailable)
    }

    private func fetch(
        _ url: URL,
        maxBytes: Int?,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?
    ) async throws -> Data {
        try Self.validateOrigin(url)
        guard configurationIdentifier == nil else {
            MakingTracksLog.resolution.error("fetch rejected kind=\(MakingTracksLog.objectKind(url), privacy: .public)")
            throw TileError.invalidBackgroundFetch
        }
        MakingTracksLog.resolution.debug("fetch started host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public)")
        let request = URLRequest(url: url)
        let (data, response) = try await delegate.fetch(
            request,
            on: session,
            maxBytes: maxBytes,
            connectivityWaiting: connectivityWaiting,
            connectivityAvailable: connectivityAvailable
        )
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            MakingTracksLog.resolution.error("fetch failed host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public) status=\(status, privacy: .public)")
            throw TileError.httpStatus(status)
        }
        MakingTracksLog.resolution.debug("fetch finished host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public) bytes=\(data.count, privacy: .public)")
        return data
    }

    public func download(_ url: URL) async throws -> URL {
        try await download(url, connectivityWaiting: nil)
    }

    public func download(_ url: URL, connectivityWaiting: (@Sendable () -> Void)?) async throws -> URL {
        try await download(url, connectivityWaiting: connectivityWaiting, connectivityAvailable: nil)
    }

    public func download(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?
    ) async throws -> URL {
        try await download(
            url,
            connectivityWaiting: connectivityWaiting,
            connectivityAvailable: connectivityAvailable,
            progress: nil
        )
    }

    public func download(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)?,
        connectivityAvailable: (@Sendable () -> Void)?,
        progress: (@Sendable (_ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)?
    ) async throws -> URL {
        try Self.validateOrigin(url)
        let kind = configurationIdentifier == nil ? "foreground" : "background"
        let identifier = configurationIdentifier ?? "foreground"
        let discretionary = session.configuration.isDiscretionary
        MakingTracksLog.downloads.debug("download started session=\(kind, privacy: .public) discretionary=\(discretionary, privacy: .public) identifier=\(identifier, privacy: .private(mask: .hash)) host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public)")
        let request = URLRequest(url: url)
        let fileURL = try await delegate.download(
            request,
            on: session,
            connectivityWaiting: connectivityWaiting,
            connectivityAvailable: connectivityAvailable,
            progress: progress
        )
        MakingTracksLog.downloads.debug("download finished session=\(kind, privacy: .public) discretionary=\(discretionary, privacy: .public) identifier=\(identifier, privacy: .private(mask: .hash)) host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public)")
        return fileURL
    }

#if DEBUG
    public func sharesSession(with other: HTTPTileFetcher) -> Bool {
        session === other.session
    }

    public var allowsCellularDownloadsForTesting: Bool {
        session.configuration.allowsExpensiveNetworkAccess
            && session.configuration.allowsConstrainedNetworkAccess
    }

    public func downloadTaskForTesting(_ url: URL) -> URLSessionDownloadTask {
        session.downloadTask(with: URLRequest(url: url))
    }

    func finishBackgroundEventsForTesting() {
        delegate.urlSessionDidFinishEvents(forBackgroundURLSession: session)
    }
#endif

    public static func validateOrigin(_ url: URL) throws {
        guard url.scheme == "https",
              url.host == trustedHost,
              url.port == nil || url.port == 443
        else {
            MakingTracksLog.resolution.error("origin check failed host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public)")
            throw TileError.untrustedHost
        }
        MakingTracksLog.resolution.debug("origin check passed host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public)")
    }

    public static func validateRedirect(from: URL, to: URL) throws {
        try validateOrigin(from)
        do {
            try validateOrigin(to)
            MakingTracksLog.resolution.debug("redirect check passed host=\(MakingTracksLog.host(to), privacy: .public) kind=\(MakingTracksLog.objectKind(to), privacy: .public)")
        } catch {
            MakingTracksLog.resolution.error("redirect check failed host=\(MakingTracksLog.host(to), privacy: .public) kind=\(MakingTracksLog.objectKind(to), privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            throw error
        }
    }

    static func validateDownloadedFile(_ fileURL: URL, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            try? FileManager.default.removeItem(at: fileURL)
            throw TileError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let finalURL = response.url else {
            try? FileManager.default.removeItem(at: fileURL)
            throw TileError.untrustedHost
        }
        do {
            try validateOrigin(finalURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            MakingTracksLog.downloads.error("download validation failed host=\(MakingTracksLog.host(finalURL), privacy: .public) kind=\(MakingTracksLog.objectKind(finalURL), privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            throw error
        }
    }
}

final class RedirectDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct DataState {
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
        let maxBytes: Int?
        let connectivityWaiting: (@Sendable () -> Void)?
        let connectivityAvailable: (@Sendable () -> Void)?
        var data: Data
        var response: URLResponse?
        var didReportConnectivityAvailable: Bool
    }

    private struct DownloadState {
        let continuation: CheckedContinuation<URL, Error>
        let connectivityWaiting: (@Sendable () -> Void)?
        let connectivityAvailable: (@Sendable () -> Void)?
        let progress: (@Sendable (_ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)?
        var stagedURL: URL?
        var response: URLResponse?
        var stagingError: Error?
        var didReportConnectivityAvailable: Bool
    }

    private final class CancellationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var cancelled = false

        func setAndResume(_ task: URLSessionTask, shouldCancel: Bool) {
            let shouldCancel = lock.withLock {
                self.task = task
                let shouldCancel = cancelled || shouldCancel
                task.resume()
                return shouldCancel
            }
            if shouldCancel {
                cancel()
            }
        }

        func setAdopted(_ task: URLSessionTask, shouldCancel: Bool) {
            let shouldCancel = lock.withLock {
                self.task = task
                return cancelled || shouldCancel
            }
            if shouldCancel {
                cancel()
            }
        }

        func cancel() {
            let task = lock.withLock {
                cancelled = true
                return self.task
            }
            task?.cancel()
        }
    }

    private let lock = NSLock()
    private var dataTasks: [Int: DataState] = [:]
    private var downloads: [Int: DownloadState] = [:]
    private var adoptedBackgroundTasks: [Int: URL] = [:]
    private var deliveredBackgroundTasks: Set<Int> = []
    private var invalidationContinuations: [CheckedContinuation<Void, Never>] = []
    private var isInvalidated = false

    func fetch(
        _ request: URLRequest,
        on session: URLSession,
        maxBytes: Int? = nil,
        connectivityWaiting: (@Sendable () -> Void)? = nil,
        connectivityAvailable: (@Sendable () -> Void)? = nil
    ) async throws -> (Data, URLResponse) {
        let cancellation = CancellationBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                lock.withLock {
                    dataTasks[task.taskIdentifier] = DataState(
                        continuation: continuation,
                        maxBytes: maxBytes,
                        connectivityWaiting: connectivityWaiting,
                        connectivityAvailable: connectivityAvailable,
                        data: Data(),
                        response: nil,
                        didReportConnectivityAvailable: false
                    )
                }
                cancellation.setAndResume(task, shouldCancel: Task.isCancelled)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func download(
        _ request: URLRequest,
        on session: URLSession,
        connectivityWaiting: (@Sendable () -> Void)? = nil,
        connectivityAvailable: (@Sendable () -> Void)? = nil,
        progress: (@Sendable (_ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)? = nil
    ) async throws -> URL {
        if let identifier = session.configuration.identifier,
           let url = request.url,
           let completedURL = OfflineBackgroundCompletedDownloadStore.shared.consume(identifier: identifier, url: url) {
            return completedURL
        }
        if let task = await existingDownloadTask(for: request, on: session) {
            return try await attach(
                to: task,
                request: request,
                on: session,
                connectivityWaiting: connectivityWaiting,
                connectivityAvailable: connectivityAvailable,
                progress: progress
            )
        }
        let cancellation = CancellationBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request)
                let sessionKind = session.configuration.identifier == nil ? "foreground" : "background"
                let sessionID = session.configuration.identifier ?? "foreground"
                let host = request.url.map(MakingTracksLog.host) ?? "unknown"
                let objectKind = request.url.map(MakingTracksLog.objectKind) ?? "unknown"
                MakingTracksLog.downloads.debug("task created session=\(sessionKind, privacy: .public) discretionary=\(session.configuration.isDiscretionary, privacy: .public) identifier=\(sessionID, privacy: .private(mask: .hash)) task=\(task.taskIdentifier, privacy: .public) host=\(host, privacy: .public) kind=\(objectKind, privacy: .public)")
                lock.withLock {
                    downloads[task.taskIdentifier] = DownloadState(
                        continuation: continuation,
                        connectivityWaiting: connectivityWaiting,
                        connectivityAvailable: connectivityAvailable,
                        progress: progress,
                        stagedURL: nil,
                        response: nil,
                        stagingError: nil,
                        didReportConnectivityAvailable: false
                    )
                }
                cancellation.setAndResume(task, shouldCancel: Task.isCancelled)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func adoptExistingTasks(on session: URLSession) {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            let adopted = tasks.compactMap { task -> (Int, URL)? in
                guard task is URLSessionDownloadTask,
                      let url = Self.requestURL(for: task),
                      (try? HTTPTileFetcher.validateOrigin(url)) != nil
                else { return nil }
                return (task.taskIdentifier, url)
            }
            guard !adopted.isEmpty else { return }
            self.lock.withLock {
                for (identifier, url) in adopted {
                    self.markAdoptedIfUndelivered(taskIdentifier: identifier, url: url)
                }
            }
        }
    }

    private func existingDownloadTask(for request: URLRequest, on session: URLSession) async -> URLSessionDownloadTask? {
        guard let requestURL = request.url else { return nil }
        return await withCheckedContinuation { continuation in
            session.getAllTasks { [weak self] tasks in
                let downloadTask = tasks.compactMap { $0 as? URLSessionDownloadTask }
                    .first {
                        Self.requestURL(for: $0) == requestURL && self?.isUntracked(taskIdentifier: $0.taskIdentifier) == true
                    }
                if let downloadTask {
                    self?.lock.withLock {
                        self?.markAdoptedIfUndelivered(taskIdentifier: downloadTask.taskIdentifier, url: requestURL)
                    }
                }
                continuation.resume(returning: downloadTask)
            }
        }
    }

    private func isUntracked(taskIdentifier: Int) -> Bool {
        lock.withLock {
            downloads[taskIdentifier] == nil
        }
    }

    private func markAdoptedIfUndelivered(taskIdentifier: Int, url: URL) {
        guard !deliveredBackgroundTasks.contains(taskIdentifier) else { return }
        adoptedBackgroundTasks[taskIdentifier] = url
    }

    func markAdoptedForTesting(taskIdentifier: Int, url: URL) {
        lock.withLock {
            markAdoptedIfUndelivered(taskIdentifier: taskIdentifier, url: url)
        }
    }

    func attach(
        to task: URLSessionDownloadTask,
        request: URLRequest,
        on session: URLSession,
        connectivityWaiting: (@Sendable () -> Void)? = nil,
        connectivityAvailable: (@Sendable () -> Void)? = nil,
        progress: (@Sendable (_ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)? = nil
    ) async throws -> URL {
        let cancellation = CancellationBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    downloads[task.taskIdentifier] = DownloadState(
                        continuation: continuation,
                        connectivityWaiting: connectivityWaiting,
                        connectivityAvailable: connectivityAvailable,
                        progress: progress,
                        stagedURL: nil,
                        response: nil,
                        stagingError: nil,
                        didReportConnectivityAvailable: false
                    )
                }
                if task.state == .completed {
                    let completedURL = session.configuration.identifier
                        .flatMap { identifier in request.url.flatMap { OfflineBackgroundCompletedDownloadStore.shared.consume(identifier: identifier, url: $0) } }
                    if let completedURL {
                        let state = lock.withLock {
                            adoptedBackgroundTasks.removeValue(forKey: task.taskIdentifier)
                            deliveredBackgroundTasks.remove(task.taskIdentifier)
                            return downloads.removeValue(forKey: task.taskIdentifier)
                        }
                        state?.continuation.resume(returning: completedURL)
                    } else {
                        let state = lock.withLock {
                            guard adoptedBackgroundTasks[task.taskIdentifier] == nil else {
                                return nil as DownloadState?
                            }
                            deliveredBackgroundTasks.remove(task.taskIdentifier)
                            return downloads.removeValue(forKey: task.taskIdentifier)
                        }
                        state?.continuation.resume(throwing: TileError.invalidBackgroundFetch)
                    }
                    cancellation.setAdopted(task, shouldCancel: Task.isCancelled)
                    return
                }
                cancellation.setAdopted(task, shouldCancel: Task.isCancelled)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        let handler = lock.withLock {
            dataTasks[task.taskIdentifier]?.connectivityWaiting
                ?? downloads[task.taskIdentifier]?.connectivityWaiting
        }
        guard let handler else { return }
        let sessionKind = session.configuration.identifier == nil ? "foreground" : "background"
        let sessionID = session.configuration.identifier ?? "foreground"
        MakingTracksLog.downloads.info("task waiting connectivity session=\(sessionKind, privacy: .public) identifier=\(sessionID, privacy: .private(mask: .hash)) task=\(task.taskIdentifier, privacy: .public)")
        handler()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let from = response.url, let to = request.url else {
            completionHandler(nil)
            return
        }
        do {
            try HTTPTileFetcher.validateRedirect(from: from, to: to)
            MakingTracksLog.resolution.debug("redirect allowed status=\(response.statusCode, privacy: .public) host=\(MakingTracksLog.host(to), privacy: .public) kind=\(MakingTracksLog.objectKind(to), privacy: .public)")
            completionHandler(request)
        } catch {
            MakingTracksLog.resolution.error("redirect blocked status=\(response.statusCode, privacy: .public) host=\(MakingTracksLog.host(to), privacy: .public) kind=\(MakingTracksLog.objectKind(to), privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let result = lock.withLock {
            guard var state = dataTasks[dataTask.taskIdentifier] else {
                return (
                    disposition: URLSession.ResponseDisposition.cancel,
                    continuation: nil as CheckedContinuation<(Data, URLResponse), Error>?
                )
            }
            if let maxBytes = state.maxBytes,
               response.expectedContentLength > Int64(maxBytes) {
                _ = dataTasks.removeValue(forKey: dataTask.taskIdentifier)
                return (
                    disposition: URLSession.ResponseDisposition.cancel,
                    continuation: state.continuation
                )
            }
            state.response = response
            dataTasks[dataTask.taskIdentifier] = state
            return (
                disposition: URLSession.ResponseDisposition.allow,
                continuation: nil as CheckedContinuation<(Data, URLResponse), Error>?
            )
        }
        if let continuation = result.continuation {
            MakingTracksLog.resolution.error("fetch failed kind=\(dataTask.currentRequest?.url.map(MakingTracksLog.objectKind) ?? "unknown", privacy: .public) reason=\(MakingTracksLog.errorLabel(TileError.responseTooLarge), privacy: .public)")
            continuation.resume(throwing: TileError.responseTooLarge)
        }
        completionHandler(result.disposition)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !data.isEmpty else { return }
        let result = lock.withLock {
            guard var state = dataTasks[dataTask.taskIdentifier] else {
                return (
                    handler: nil as (@Sendable () -> Void)?,
                    continuation: nil as CheckedContinuation<(Data, URLResponse), Error>?
                )
            }
            let handler = state.didReportConnectivityAvailable ? nil : state.connectivityAvailable
            state.didReportConnectivityAvailable = true
            if let maxBytes = state.maxBytes,
               data.count > maxBytes - state.data.count {
                _ = dataTasks.removeValue(forKey: dataTask.taskIdentifier)
                return (handler: handler, continuation: state.continuation)
            }
            state.data.append(data)
            dataTasks[dataTask.taskIdentifier] = state
            return (
                handler: handler,
                continuation: nil as CheckedContinuation<(Data, URLResponse), Error>?
            )
        }
        if let continuation = result.continuation {
            dataTask.cancel()
            result.handler?()
            MakingTracksLog.resolution.error("fetch failed kind=\(dataTask.currentRequest?.url.map(MakingTracksLog.objectKind) ?? "unknown", privacy: .public) reason=\(MakingTracksLog.errorLabel(TileError.responseTooLarge), privacy: .public)")
            continuation.resume(throwing: TileError.responseTooLarge)
            return
        }
        result.handler?()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard bytesWritten > 0 else { return }
        let callbacks = lock.withLock { () -> ((@Sendable () -> Void)?, (@Sendable (_ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)?)? in
            guard var state = downloads[downloadTask.taskIdentifier] else { return nil }
            let handler = state.didReportConnectivityAvailable ? nil : state.connectivityAvailable
            state.didReportConnectivityAvailable = true
            downloads[downloadTask.taskIdentifier] = state
            return (handler, state.progress)
        }
        callbacks?.0?()
        callbacks?.1?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let (isTracked, adoptionURL) = lock.withLock {
            if downloads[downloadTask.taskIdentifier] != nil {
                return (true, nil as URL?)
            }
            if let url = adoptedBackgroundTasks[downloadTask.taskIdentifier] {
                return (false, url)
            }
            return (false, Self.requestURL(for: downloadTask))
        }
        guard !isTracked else {
            stageTrackedDownload(downloadTask: downloadTask, location: location)
            return
        }
        if let adoptionURL, let identifier = session.configuration.identifier {
            do {
                try OfflineBackgroundCompletedDownloadStore.shared.stage(
                    identifier: identifier,
                    url: adoptionURL,
                    fileURL: location,
                    response: downloadTask.response
                )
                MakingTracksLog.downloads.debug("task adopted task=\(downloadTask.taskIdentifier, privacy: .public)")
            } catch {
                MakingTracksLog.downloads.error("task adoption dropped task=\(downloadTask.taskIdentifier, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            }
            _ = lock.withLock {
                adoptedBackgroundTasks.removeValue(forKey: downloadTask.taskIdentifier)
            }
            return
        }

        stageTrackedDownload(downloadTask: downloadTask, location: location)
    }

    private func stageTrackedDownload(downloadTask: URLSessionDownloadTask, location: URL) {
        let result: Result<URL, Error>
        do {
            let staged = try BackgroundDownloadFileStager.stage(location)
            MakingTracksLog.downloads.debug("task staged task=\(downloadTask.taskIdentifier, privacy: .public)")
            result = .success(staged)
        } catch {
            MakingTracksLog.downloads.error("task stage failed task=\(downloadTask.taskIdentifier, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            result = .failure(error)
        }

        lock.withLock {
            guard var state = downloads[downloadTask.taskIdentifier] else {
                if case let .success(url) = result {
                    try? FileManager.default.removeItem(at: url)
                }
                return
            }
            switch result {
            case let .success(url):
                state.stagedURL = url
                state.response = downloadTask.response
            case let .failure(error):
                state.stagingError = error
            }
            downloads[downloadTask.taskIdentifier] = state
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let state = lock.withLock({ dataTasks.removeValue(forKey: task.taskIdentifier) }) {
            if let error {
                MakingTracksLog.resolution.error("fetch failed kind=\(task.currentRequest?.url.map(MakingTracksLog.objectKind) ?? "unknown", privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
                state.continuation.resume(throwing: error)
                return
            }
            guard let response = state.response ?? task.response else {
                MakingTracksLog.resolution.error("fetch failed kind=\(task.currentRequest?.url.map(MakingTracksLog.objectKind) ?? "unknown", privacy: .public) status=-1")
                state.continuation.resume(throwing: TileError.httpStatus(-1))
                return
            }
            state.continuation.resume(returning: (state.data, response))
            return
        }

        guard let state = lock.withLock({ downloads.removeValue(forKey: task.taskIdentifier) }) else {
            if task is URLSessionDownloadTask {
                lock.withLock {
                    _ = deliveredBackgroundTasks.insert(task.taskIdentifier)
                    _ = adoptedBackgroundTasks.removeValue(forKey: task.taskIdentifier)
                }
            }
            if error != nil,
               let identifier = session.configuration.identifier,
               let url = lock.withLock({ adoptedBackgroundTasks.removeValue(forKey: task.taskIdentifier) }) ?? Self.requestURL(for: task) {
                OfflineBackgroundCompletedDownloadStore.shared.remove(identifier: identifier, url: url)
            }
            return
        }
        lock.withLock {
            adoptedBackgroundTasks.removeValue(forKey: task.taskIdentifier)
            deliveredBackgroundTasks.remove(task.taskIdentifier)
        }
        do {
            let fileURL = try BackgroundDownloadCompletion.validate(
                stagedURL: state.stagedURL,
                response: state.response ?? task.response,
                taskError: error,
                stagingError: state.stagingError
            )
            MakingTracksLog.downloads.debug("task completed task=\(task.taskIdentifier, privacy: .public)")
            state.continuation.resume(returning: fileURL)
        } catch {
            MakingTracksLog.downloads.error("task failed task=\(task.taskIdentifier, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            state.continuation.resume(throwing: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let sessionID = session.configuration.identifier ?? "foreground"
        MakingTracksLog.downloads.info("session events finished identifier=\(sessionID, privacy: .private(mask: .hash))")
        OfflineDownloadSession.finishEvents(for: session.configuration.identifier)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        OfflineDownloadSession.finishEvents(for: session.configuration.identifier)
        let continuations = lock.withLock {
            isInvalidated = true
            let continuations = invalidationContinuations
            invalidationContinuations.removeAll()
            return continuations
        }
        for continuation in continuations {
            continuation.resume()
        }
    }

    func cancelAll(with error: Error) {
        let states = lock.withLock {
            let states = (data: Array(dataTasks.values), downloads: Array(downloads.values))
            dataTasks.removeAll()
            downloads.removeAll()
            return states
        }
        for state in states.data {
            state.continuation.resume(throwing: error)
        }
        for state in states.downloads {
            if let stagedURL = state.stagedURL {
                try? FileManager.default.removeItem(at: stagedURL)
            }
            state.continuation.resume(throwing: error)
        }
        MakingTracksLog.downloads.info("session downloads cancelled count=\(states.downloads.count, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
    }

    func hasTrackedTasks() -> Bool {
        lock.withLock {
            !dataTasks.isEmpty || !downloads.isEmpty || !adoptedBackgroundTasks.isEmpty
        }
    }

    func hasTrackedOrAdoptableTasks(on session: URLSession) async -> Bool {
        if hasTrackedTasks() {
            return true
        }
        return await withCheckedContinuation { continuation in
            session.getAllTasks { [weak self] tasks in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                let adoptableDownloads = tasks.compactMap { task -> (Int, URL)? in
                    guard task is URLSessionDownloadTask,
                          let url = Self.requestURL(for: task),
                          (try? HTTPTileFetcher.validateOrigin(url)) != nil
                    else { return nil }
                    return (task.taskIdentifier, url)
                }
                let hasTrackedTasks = self.lock.withLock {
                    for (taskIdentifier, url) in adoptableDownloads where self.downloads[taskIdentifier] == nil {
                        self.markAdoptedIfUndelivered(taskIdentifier: taskIdentifier, url: url)
                    }
                    return !self.dataTasks.isEmpty || !self.downloads.isEmpty || !self.adoptedBackgroundTasks.isEmpty
                }
                continuation.resume(returning: hasTrackedTasks)
            }
        }
    }

    func invalidateAndWait(_ session: URLSession) async {
        await withCheckedContinuation { continuation in
            let alreadyInvalidated = lock.withLock {
                if isInvalidated {
                    return true
                }
                invalidationContinuations.append(continuation)
                return false
            }
            if alreadyInvalidated {
                continuation.resume()
            } else {
                session.invalidateAndCancel()
            }
        }
    }

    private static func requestURL(for task: URLSessionTask) -> URL? {
        task.originalRequest?.url ?? task.currentRequest?.url ?? task.response?.url
    }
}

enum BackgroundDownloadFileStager {
    static func stage(_ location: URL) throws -> URL {
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MakingTracksBackgroundDownload-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: location, to: stagedURL)
        return stagedURL
    }
}

private struct BackgroundCompletedDownloadIndex: Codable {
    var schemaVersion = 1
    var entries: [BackgroundCompletedDownloadRecord] = []
}

private struct BackgroundCompletedDownloadRecord: Codable, Equatable {
    let identifier: String
    let requestURLString: String
    let stagedFileName: String
}

private final class OfflineBackgroundCompletedDownloadStore: @unchecked Sendable {
    static let shared = OfflineBackgroundCompletedDownloadStore()
    static let maxIndexBytes = 1024 * 1024
    static let maxStoredDownloadBytes = 4 * 1024 * 1024 * 1024

    private let fm = FileManager.default
    private let lock = NSLock()

    func stage(identifier: String, url: URL, fileURL: URL, response: URLResponse?) throws {
        try HTTPTileFetcher.validateOrigin(url)
        try validateIdentifier(identifier)
        _ = try BackgroundDownloadCompletion.validate(
            stagedURL: fileURL,
            response: response,
            taskError: nil,
            stagingError: nil
        )
        let directory = try storeDirectory()
        let stagedFileName = "\(UUID().uuidString).download"
        let stagedURL = directory.appendingPathComponent(stagedFileName)
        do {
            if fm.fileExists(atPath: stagedURL.path) {
                try fm.removeItem(at: stagedURL)
            }
            try fm.moveItem(at: fileURL, to: stagedURL)
            try excludeFromBackup(stagedURL)
            try setBackgroundFileProtection(stagedURL)
            try lock.withLock {
                var index = try readIndexLocked()
                removeRecordLocked(identifier: identifier, url: url, from: &index)
                index.entries.append(BackgroundCompletedDownloadRecord(
                    identifier: identifier,
                    requestURLString: url.absoluteString,
                    stagedFileName: stagedFileName
                ))
                try pruneLocked(index: &index, maxBytes: Self.maxStoredDownloadBytes)
                guard index.entries.contains(where: { $0.stagedFileName == stagedFileName }) else {
                    throw TileError.insufficientStorage
                }
                guard index.entries.count <= 1024 else { throw TileError.invalidOfflinePack }
                try writeIndexLocked(index)
            }
        } catch {
            if fm.fileExists(atPath: stagedURL.path) {
                try? fm.removeItem(at: stagedURL)
            }
            throw error
        }
    }

    func consume(identifier: String, url: URL) -> URL? {
        guard (try? HTTPTileFetcher.validateOrigin(url)) != nil,
              (try? validateIdentifier(identifier)) != nil
        else { return nil }
        return lock.withLock {
            do {
                var index = try readIndexLocked()
                try sweepOrphansLocked(index: &index)
                guard let entryIndex = index.entries.firstIndex(where: {
                    $0.identifier == identifier && $0.requestURLString == url.absoluteString
                }) else { return nil }
                let entry = index.entries.remove(at: entryIndex)
                let fileURL = try storeDirectory().appendingPathComponent(entry.stagedFileName)
                try writeIndexLocked(index)
                guard fm.fileExists(atPath: fileURL.path) else { return nil }
                return fileURL
            } catch {
                return nil
            }
        }
    }

    func restoreConsumed(identifier: String, url: URL, fileURL: URL) {
        guard (try? HTTPTileFetcher.validateOrigin(url)) != nil,
              (try? validateIdentifier(identifier)) != nil
        else { return }
        lock.withLock {
            do {
                let directory = try storeDirectory()
                guard fileURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
                      fm.fileExists(atPath: fileURL.path)
                else { return }
                let record = BackgroundCompletedDownloadRecord(
                    identifier: identifier,
                    requestURLString: url.absoluteString,
                    stagedFileName: fileURL.lastPathComponent
                )
                guard isValidRecord(record) else { return }
                var index = try readIndexLocked()
                removeRecordLocked(identifier: identifier, url: url, from: &index)
                index.entries.append(record)
                guard index.entries.count <= 1024 else { throw TileError.invalidOfflinePack }
                try writeIndexLocked(index)
            } catch {
                return
            }
        }
    }

    func performMaintenance(maxBytes: Int = OfflineBackgroundCompletedDownloadStore.maxStoredDownloadBytes) throws {
        try lock.withLock {
            var index = try readIndexLocked()
            try pruneLocked(index: &index, maxBytes: maxBytes)
            try writeIndexLocked(index)
        }
    }

    func remove(identifier: String, url: URL) {
        guard (try? validateIdentifier(identifier)) != nil else { return }
        lock.withLock {
            do {
                var index = try readIndexLocked()
                removeRecordLocked(identifier: identifier, url: url, from: &index)
                try writeIndexLocked(index)
            } catch {
                return
            }
        }
    }

    func removeAll(identifier: String) {
        guard (try? validateIdentifier(identifier)) != nil else { return }
        lock.withLock {
            do {
                var index = try readIndexLocked()
                for entry in index.entries where entry.identifier == identifier {
                    try? fm.removeItem(at: try storeDirectory().appendingPathComponent(entry.stagedFileName))
                }
                index.entries.removeAll { $0.identifier == identifier }
                try writeIndexLocked(index)
            } catch {
                return
            }
        }
    }

    func removeAll(region: String) {
        removeAll(identifier: OfflineDownloadSession.backgroundIdentifier(region: region))
    }

    private func removeRecordLocked(identifier: String, url: URL, from index: inout BackgroundCompletedDownloadIndex) {
        let removed = index.entries.filter { $0.identifier == identifier && $0.requestURLString == url.absoluteString }
        let directory = try? storeDirectory()
        for entry in removed {
            if let directory {
                try? fm.removeItem(at: directory.appendingPathComponent(entry.stagedFileName))
            }
        }
        index.entries.removeAll { $0.identifier == identifier && $0.requestURLString == url.absoluteString }
    }

    private func pruneLocked(index: inout BackgroundCompletedDownloadIndex, maxBytes: Int) throws {
        guard maxBytes >= 0 else { throw TileError.invalidOfflinePack }
        try sweepOrphansLocked(index: &index)
        while try storedBytesLocked(index.entries) > maxBytes, let first = index.entries.first {
            try? fm.removeItem(at: try storeDirectory().appendingPathComponent(first.stagedFileName))
            index.entries.removeFirst()
        }
    }

    private func sweepOrphansLocked(index: inout BackgroundCompletedDownloadIndex) throws {
        let directory = try storeDirectory()
        index.entries.removeAll { entry in
            !fm.fileExists(atPath: directory.appendingPathComponent(entry.stagedFileName).path)
        }
        let referenced = Set(index.entries.map(\.stagedFileName))
        guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for child in children where child.lastPathComponent.hasSuffix(".download") && !referenced.contains(child.lastPathComponent) {
            let values = try child.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                try? fm.removeItem(at: child)
            }
        }
    }

    private func storedBytesLocked(_ entries: [BackgroundCompletedDownloadRecord]) throws -> Int {
        let directory = try storeDirectory()
        return try entries.reduce(0) { total, entry in
            let url = directory.appendingPathComponent(entry.stagedFileName)
            let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            let (sum, overflow) = total.addingReportingOverflow(size)
            guard !overflow else { throw TileError.invalidOfflinePack }
            return sum
        }
    }

    private func readIndexLocked() throws -> BackgroundCompletedDownloadIndex {
        let url = try indexURL()
        guard fm.fileExists(atPath: url.path) else { return BackgroundCompletedDownloadIndex() }
        do {
            let index = try JSONDecoder().decode(
                BackgroundCompletedDownloadIndex.self,
                from: try boundedData(contentsOf: url, maxBytes: Self.maxIndexBytes)
            )
            guard index.schemaVersion == 1,
                  index.entries.count <= 1024,
                  index.entries.allSatisfy({ isValidRecord($0) })
            else { throw TileError.invalidOfflinePack }
            return index
        } catch {
            try? resetStoreLocked()
            return BackgroundCompletedDownloadIndex()
        }
    }

    private func writeIndexLocked(_ index: BackgroundCompletedDownloadIndex) throws {
        let url = try indexURL()
        try JSONEncoder().encode(index).write(to: url, options: .atomic)
        try excludeFromBackup(url)
        try setBackgroundFileProtection(url)
    }

    private func indexURL() throws -> URL {
        try storeDirectory().appendingPathComponent("completed-downloads-v1.json")
    }

    private func storeDirectory() throws -> URL {
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("MakingTracks/BackgroundDownloads", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        try setBackgroundFileProtection(directory)
        return directory
    }

    private func validateIdentifier(_ identifier: String) throws {
        guard (1...128).contains(identifier.utf8.count),
              identifier.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
        else { throw TileError.invalidOfflinePack }
    }

    private func isValidRecord(_ record: BackgroundCompletedDownloadRecord) -> Bool {
        guard (try? validateIdentifier(record.identifier)) != nil,
              record.stagedFileName.range(of: #"^[A-Fa-f0-9-]{36}\.download$"#, options: .regularExpression) != nil,
              let url = URL(string: record.requestURLString),
              (try? HTTPTileFetcher.validateOrigin(url)) != nil
        else { return false }
        return true
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func setBackgroundFileProtection(_ url: URL) throws {
        try (url as NSURL).setResourceValue(URLFileProtection.none, forKey: .fileProtectionKey)
    }

    private func resetStoreLocked() throws {
        let directory = try storeDirectory()
        guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for child in children where child.lastPathComponent.hasSuffix(".download") || child.lastPathComponent == "completed-downloads-v1.json" {
            try? fm.removeItem(at: child)
        }
    }

    private func boundedData(contentsOf url: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw TileError.invalidOfflinePack }
        return data
    }

    func replaceIndexForTesting(_ data: Data) throws {
        try lock.withLock {
            let url = try indexURL()
            try data.write(to: url, options: .atomic)
        }
    }

    func createDownloadFileForTesting(named name: String, data: Data) throws {
        try lock.withLock {
            let url = try storeDirectory().appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
        }
    }

    func hasDownloadFileForTesting(named name: String) -> Bool {
        lock.withLock {
            guard let url = try? storeDirectory().appendingPathComponent(name) else { return false }
            return fm.fileExists(atPath: url.path)
        }
    }
}

enum BackgroundDownloadCompletion {
    static func validate(
        stagedURL: URL?,
        response: URLResponse?,
        taskError: Error?,
        stagingError: Error?
    ) throws -> URL {
        if let error = taskError {
            remove(stagedURL)
            throw error
        }
        if let error = stagingError {
            remove(stagedURL)
            throw error
        }
        guard let stagedURL else {
            throw TileError.httpStatus(-1)
        }
        guard let response else {
            remove(stagedURL)
            throw TileError.httpStatus(-1)
        }
        do {
            try HTTPTileFetcher.validateDownloadedFile(stagedURL, response: response)
            return stagedURL
        } catch {
            remove(stagedURL)
            throw error
        }
    }

    private static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

public struct Manifest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let minReaderVersion: Int
    public let region: String
    public let publishVersion: String
    public let generatedAt: String?
    public let tileZ: Int
    public let tiles: [ManifestTile]
    public let counts: Counts
    public let basemap: Basemap
    public let provenance: [Provenance]
    public let attribution: [Attribution]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case minReaderVersion = "min_reader_version"
        case region
        case publishVersion = "publish_version"
        case generatedAt = "generated_at"
        case tileZ = "tile_z"
        case tiles
        case counts
        case basemap
        case provenance
        case attribution
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        minReaderVersion = try container.decode(Int.self, forKey: .minReaderVersion)
        region = try container.decode(String.self, forKey: .region)
        publishVersion = try container.decode(String.self, forKey: .publishVersion)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        tileZ = try container.decode(Int.self, forKey: .tileZ)
        tiles = try container.decode([ManifestTile].self, forKey: .tiles)
        counts = try container.decode(Counts.self, forKey: .counts)
        basemap = try container.decode(Basemap.self, forKey: .basemap)
        provenance = try container.decode([Provenance].self, forKey: .provenance)
        attribution = try container.decodeIfPresent([Attribution].self, forKey: .attribution) ?? []
    }

    public static func decode(_ data: Data) throws -> Manifest {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TileError.invalidManifest
        }
        let allowed: Set<String> = [
            "schema_version", "min_reader_version", "region", "publish_version", "generated_at",
            "tile_z", "tiles", "counts", "basemap", "provenance", "attribution",
        ]
        guard Set(object.keys).isSubset(of: allowed) else { throw TileError.invalidManifest }
        try validateManifestObject(object)
        var manifest = try JSONDecoder().decode(Manifest.self, from: data)
        if manifest.attribution.isEmpty, object["attribution"] == nil {
            manifest = Manifest(
                schemaVersion: manifest.schemaVersion,
                minReaderVersion: manifest.minReaderVersion,
                region: manifest.region,
                publishVersion: manifest.publishVersion,
                generatedAt: manifest.generatedAt,
                tileZ: manifest.tileZ,
                tiles: manifest.tiles,
                counts: manifest.counts,
                basemap: manifest.basemap,
                provenance: manifest.provenance,
                attribution: []
            )
        }
        try manifest.validate()
        return manifest
    }

    private static func validateManifestObject(_ object: [String: Any]) throws {
        if let generatedAt = object["generated_at"] as? String {
            guard generatedAt.count <= 32,
                  generatedAt.matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")
            else { throw TileError.invalidManifest }
        }
        guard let tiles = object["tiles"] as? [[String: Any]],
              let counts = object["counts"] as? [String: Any],
              Set(counts.keys) == ["total", "by_tier"],
              let total = counts["total"] as? Int,
              total >= 0,
              let byTier = counts["by_tier"] as? [Int],
              byTier.count == 4,
              byTier.allSatisfy({ $0 >= 0 }),
              let basemap = object["basemap"] as? [String: Any],
              Set(basemap.keys) == ["filename", "maxzoom", "sha256", "bytes", "bbox"],
              let bbox = basemap["bbox"] as? [Double],
              bbox.count == 4,
              bbox.allSatisfy({ (-180.0...180.0).contains($0) }),
              let provenance = object["provenance"] as? [[String: Any]]
        else { throw TileError.invalidManifest }
        let attribution = (object["attribution"] as? [[String: Any]]) ?? []
        let tileKeys: Set<String> = ["x", "y", "sha256", "bytes"]
        let provenanceKeys: Set<String> = ["task_id", "model", "prompt_version"]
        let attributionKeys: Set<String> = ["source", "license", "text"]
        guard tiles.allSatisfy({ Set($0.keys) == tileKeys }),
              provenance.allSatisfy({ Set($0.keys) == provenanceKeys }),
              attribution.count <= 32,
              attribution.allSatisfy({ Set($0.keys) == attributionKeys })
        else { throw TileError.invalidManifest }
    }

    private init(
        schemaVersion: Int,
        minReaderVersion: Int,
        region: String,
        publishVersion: String,
        generatedAt: String?,
        tileZ: Int,
        tiles: [ManifestTile],
        counts: Counts,
        basemap: Basemap,
        provenance: [Provenance],
        attribution: [Attribution]
    ) {
        self.schemaVersion = schemaVersion
        self.minReaderVersion = minReaderVersion
        self.region = region
        self.publishVersion = publishVersion
        self.generatedAt = generatedAt
        self.tileZ = tileZ
        self.tiles = tiles
        self.counts = counts
        self.basemap = basemap
        self.provenance = provenance
        self.attribution = attribution
    }

    private func validate() throws {
        guard VersionGate.schema(
            readerMax: VersionGate.readerSchemaVersion,
            dataVersion: schemaVersion,
            minSupported: VersionGate.minSupportedSchemaVersion
        ) == .ok else { throw TileError.invalidManifest }
        guard minReaderVersion >= 1,
              region.matches(regionIDPattern),
              publishVersion.matches("^[0-9]{8}T[0-9]{6}Z$"),
              tileZ == 10,
              !tiles.isEmpty || counts.total == 0,
              tiles.count <= 1_048_576,
              counts.byTier.count == 4,
              !provenance.isEmpty,
              provenance.count <= 32
        else { throw TileError.invalidManifest }
        if !attribution.isEmpty && minReaderVersion < 2 {
            throw TileError.invalidManifest
        }
        for tile in tiles {
            try tile.validate()
        }
        try basemap.validate()
        for item in provenance {
            try item.validate()
        }
        for item in attribution {
            try item.validate()
        }
    }
}

public struct ManifestTile: Codable, Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let sha256: String
    public let bytes: Int

    func validate() throws {
        guard (0...1023).contains(x),
              (0...1023).contains(y),
              sha256.matches("^[0-9a-f]{64}$"),
              (1...TileCodec.maxCompressedBytes).contains(bytes)
        else { throw TileError.invalidManifest }
    }
}

public struct Counts: Codable, Sendable, Equatable {
    public let total: Int
    public let byTier: [Int]

    enum CodingKeys: String, CodingKey {
        case total
        case byTier = "by_tier"
    }
}

public struct Basemap: Codable, Sendable, Equatable {
    public let filename: String
    public let maxzoom: Int
    public let sha256: String
    public let bytes: Int
    public let bbox: [Double]

    func validate() throws {
        guard filename.matches("^[a-z0-9][a-z0-9._-]{0,123}\\.pmtiles$"),
              maxzoom == 14,
              sha256.matches("^[0-9a-f]{64}$"),
              (1...3_221_225_472).contains(bytes),
              bbox.count == 4
        else { throw TileError.invalidManifest }
    }
}

public struct Provenance: Codable, Sendable, Equatable {
    public let taskID: String
    public let model: String
    public let promptVersion: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case model
        case promptVersion = "prompt_version"
    }

    func validate() throws {
        guard ["score", "curiosity", "blurb", "category", "reconcile"].contains(taskID),
              (1...128).contains(model.scalarCount),
              (1...64).contains(promptVersion.scalarCount)
        else { throw TileError.invalidManifest }
    }
}

extension Attribution {
    func validate() throws {
        guard (1...32).contains(source.scalarCount),
              (1...32).contains(license.scalarCount),
              (1...512).contains(text.scalarCount),
              source.isSafeText,
              license.isSafeText,
              text.isSafeText
        else { throw TileError.invalidManifest }
    }
}

public struct PinnedPublish: Codable, Sendable, Equatable {
    public let region: String
    public let publishVersion: String
    public let manifest: Manifest

    public init(region: String, publishVersion: String, manifest: Manifest) {
        self.region = region
        self.publishVersion = publishVersion
        self.manifest = manifest
    }

    public var attribution: [Attribution] { manifest.attribution }

    public var basemapURL: URL? {
        URL(string: "https://\(HTTPTileFetcher.trustedHost)/\(region)/\(publishVersion)/\(manifest.basemap.filename)")
    }

    public var basemapIntegrity: (sha256: String, bytes: Int)? {
        (manifest.basemap.sha256, manifest.basemap.bytes)
    }
}

public struct ManifestPinResult: Sendable, Equatable {
    public let publish: PinnedPublish?
    public let state: TileLoadState
}

public final class ManifestClient: @unchecked Sendable {
    private let region: String
    private let fetcher: TileFetching
    private let cache: TileCache

    public init(region: String, fetcher: TileFetching, cache: TileCache) {
        self.region = region
        self.fetcher = fetcher
        self.cache = cache
    }

    public static func currentPublishVersion(region: String, fetcher: TileFetching) async throws -> String {
        guard region.matches(regionIDPattern) else {
            throw TileError.invalidOfflinePack
        }
        return try decodeCurrent(await fetcher.fetch(try trustedURL("\(region)/current.json")))
    }

    public func refresh() async -> ManifestPinResult {
        do {
            guard region.matches(regionIDPattern) else {
                return ManifestPinResult(publish: nil, state: .unavailable)
            }
            let currentURL = try trustedURL("\(region)/current.json")
            let currentData: Data
            do {
                currentData = try await fetcher.fetch(currentURL)
            } catch {
                return fallback(for: error)
            }
            let publishVersion = try Self.decodeCurrent(currentData)
            let manifestURL = try trustedURL("\(region)/\(publishVersion)/manifest.json")
            let manifestData: Data
            do {
                manifestData = try await fetcher.fetch(manifestURL)
            } catch {
                return fallback(for: error)
            }
            let manifest = try Manifest.decode(manifestData)
            guard manifest.region == region, manifest.publishVersion == publishVersion else {
                throw TileError.invalidManifest
            }
            let cached = try? cache.lastVerifiedPublish(region: region)
            let readerState = VersionGate.reader(
                minReaderVersion: manifest.minReaderVersion,
                hasReadableCache: cached != nil
            )
            if readerState == .updateAvailable {
                return ManifestPinResult(publish: cached, state: .updateAvailable)
            }
            if readerState == .updateRequired {
                return ManifestPinResult(publish: nil, state: .updateRequired)
            }
            let pin = PinnedPublish(region: region, publishVersion: publishVersion, manifest: manifest)
            try cache.recordVerifiedPublish(region: region, publish: pin)
            return ManifestPinResult(publish: pin, state: .ok)
        } catch {
            if let cached = try? cache.lastVerifiedPublish(region: region) {
                return ManifestPinResult(publish: cached, state: .manifestInvalid)
            }
            return ManifestPinResult(publish: nil, state: .unavailable)
        }
    }

    private func fallback(for error: Error) -> ManifestPinResult {
        if let cached = try? cache.lastVerifiedPublish(region: region) {
            return ManifestPinResult(publish: cached, state: .stale)
        }
        return ManifestPinResult(publish: nil, state: .unavailable)
    }

    static func decodeCurrent(_ data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schema_version", "publish_version"],
              let schemaVersion = object["schema_version"] as? Int,
              schemaVersion == 1,
              let publishVersion = object["publish_version"] as? String,
              publishVersion.matches("^[0-9]{8}T[0-9]{6}Z$")
        else { throw TileError.invalidCurrent }
        return publishVersion
    }
}

public enum TileCodec {
    public static let maxCompressedBytes = 1 * 1024 * 1024
    public static let maxUncompressedBytes = 8 * 1024 * 1024

    public static func decode(gzipped data: Data, expectedSHA256: String, expectedBytes: Int) throws -> Data {
        guard data.count == expectedBytes else { throw TileError.byteCountMismatch }
        guard data.count <= maxCompressedBytes else { throw TileError.compressedTooLarge }
        guard sha256(data) == expectedSHA256 else { throw TileError.checksumMismatch }
        return try gunzip(data)
    }

    private static func gunzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw TileError.invalidGzip }
        defer { inflateEnd(&stream) }

        var output = Data()
        var reachedEnd = false
        try data.withUnsafeBytes { inputBuffer in
            guard let inputBase = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw TileError.invalidGzip
            }
            var offset = 0
            while offset < data.count {
                if reachedEnd { throw TileError.invalidGzip }
                let chunkSize = min(65_536, data.count - offset)
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBase.advanced(by: offset))
                stream.avail_in = uInt(chunkSize)

                repeat {
                    var buffer = [UInt8](repeating: 0, count: 65_536)
                    let produced: Int = try buffer.withUnsafeMutableBufferPointer { outBuffer in
                        guard let outBase = outBuffer.baseAddress else { throw TileError.invalidGzip }
                        stream.next_out = outBase
                        stream.avail_out = uInt(outBuffer.count)
                        let status = inflate(&stream, Z_NO_FLUSH)
                        guard status == Z_OK || status == Z_STREAM_END else {
                            throw TileError.invalidGzip
                        }
                        if status == Z_STREAM_END {
                            reachedEnd = true
                            if stream.avail_in != 0 || offset + chunkSize != data.count {
                                throw TileError.invalidGzip
                            }
                        }
                        return outBuffer.count - Int(stream.avail_out)
                    }
                    if produced > 0 {
                        output.append(buffer, count: produced)
                        if output.count > maxUncompressedBytes {
                            throw TileError.inflatedTooLarge
                        }
                    }
                } while stream.avail_out == 0

                offset += chunkSize
            }
        }
        guard reachedEnd else { throw TileError.invalidGzip }
        return output
    }
}

public struct DecodedPlace: Sendable, Equatable {
    public let mapPlace: MapPlace
    public let placeRef: PlaceRef
    public let imageURL: URL?
    public let sourceRefs: [String]
}

public struct DecodedTile: Sendable, Equatable {
    public let places: [DecodedPlace]
    public let missingAttributionSources: Set<String>
}

public struct PlaceImageAttribution: Sendable, Equatable {
    public let creator: String?
    public let licenseCode: String
    public let licenseName: String
    public let licenseURL: URL
    public let sourceURL: URL
    public let modified: Bool

    public init(
        creator: String?,
        licenseCode: String,
        licenseName: String,
        licenseURL: URL,
        sourceURL: URL,
        modified: Bool
    ) {
        self.creator = creator
        self.licenseCode = licenseCode
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.sourceURL = sourceURL
        self.modified = modified
    }

    public var displayText: String {
        var parts: [String] = []
        if let creator {
            parts.append(creator)
        }
        parts.append(licenseName)
        if modified {
            parts.append("modified")
        }
        parts.append(licenseURL.absoluteString)
        return parts.joined(separator: " / ")
    }
}

public struct PlaceImage: Sendable, Equatable {
    public let placeID: String
    public let thumbSHA256: String
    public let bytes: Int
    public let width: Int
    public let height: Int
    public let attribution: PlaceImageAttribution

    public init(
        placeID: String,
        thumbSHA256: String,
        bytes: Int,
        width: Int,
        height: Int,
        attribution: PlaceImageAttribution
    ) {
        self.placeID = placeID
        self.thumbSHA256 = thumbSHA256
        self.bytes = bytes
        self.width = width
        self.height = height
        self.attribution = attribution
    }

    public var thumbURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = HTTPTileFetcher.trustedHost
        components.path = "/thumbs/\(thumbSHA256.prefix(2))/\(thumbSHA256).webp"
        return components.url ?? URL(string: "https://\(HTTPTileFetcher.trustedHost)/thumbs/invalid/invalid.webp")!
    }
}

private enum ImagePayloadLimits {
    // Tunable cap for the optional per-tile image index. The schema allows 4k rows, so keep headroom
    // for attribution strings while bounding JSON buffering before parse.
    static let maxImageIndexBytes = 8 * 1024 * 1024
    static let maxThumbnailBytes = 2 * 1024 * 1024
}

public enum ImageIndexDecoder {
    // Tunable safety caps: generated thumbnails are small, but metadata must still bound decode work.
    private static let maxPlaces = 4_000
    private static let maxDecodedPixels = 16_000_000
    private static let maxTextScalars = 200
    private static let maxURLScalars = 2_048

    public static func decode(_ data: Data, expected: TileCoordinate) throws -> [PlaceImage] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schema_version", "min_reader_version", "z", "x", "y", "places"],
              object["schema_version"] as? Int == 1,
              let minReaderVersion = object["min_reader_version"] as? Int,
              minReaderVersion <= VersionGate.readerVersion,
              object["z"] as? Int == expected.z,
              object["x"] as? Int == expected.x,
              object["y"] as? Int == expected.y,
              let places = object["places"] as? [[String: Any]],
              places.count <= maxPlaces
        else { throw TileError.invalidImageIndex }

        var decoded: [PlaceImage] = []
        var seen: Set<String> = []
        for place in places {
            guard let image = decodeImage(place), !seen.contains(image.placeID) else { continue }
            seen.insert(image.placeID)
            decoded.append(image)
        }
        return decoded
    }

    private static func decodeImage(_ object: [String: Any]) -> PlaceImage? {
        guard Set(object.keys) == ["place_id", "thumb_sha256", "bytes", "width", "height", "attribution"],
              let placeID = object["place_id"] as? String,
              placeID.matches("^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$"),
              let thumbSHA256 = object["thumb_sha256"] as? String,
              thumbSHA256.matches("^[0-9a-f]{64}$"),
              let bytes = object["bytes"] as? Int,
              (1...ImagePayloadLimits.maxThumbnailBytes).contains(bytes),
              let width = object["width"] as? Int,
              let height = object["height"] as? Int,
              width > 0,
              height > 0,
              width <= maxDecodedPixels / height,
              let attributionObject = object["attribution"] as? [String: Any],
              let attribution = decodeAttribution(attributionObject)
        else { return nil }
        return PlaceImage(
            placeID: placeID,
            thumbSHA256: thumbSHA256,
            bytes: bytes,
            width: width,
            height: height,
            attribution: attribution
        )
    }

    private static func decodeAttribution(_ object: [String: Any]) -> PlaceImageAttribution? {
        guard Set(object.keys) == ["creator", "license_code", "license_name", "license_url", "source_url", "modified"],
              let licenseCode = object["license_code"] as? String,
              safeText(licenseCode),
              isAllowedLicenseCode(licenseCode),
              let licenseName = object["license_name"] as? String,
              safeText(licenseName),
              let licenseURL = allowedURL(object["license_url"], hosts: ["creativecommons.org", "www.creativecommons.org"]),
              isExpectedLicenseURL(licenseURL, for: licenseCode),
              let sourceURL = allowedURL(object["source_url"], hosts: ["commons.wikimedia.org"]),
              object["modified"] as? Bool == true
        else { return nil }

        let creator: String?
        if object["creator"] is NSNull {
            creator = nil
        } else if let decodedCreator = object["creator"] as? String, safeText(decodedCreator) {
            creator = decodedCreator
        } else {
            return nil
        }

        guard !requiresCreator(licenseCode) || creator != nil else { return nil }
        return PlaceImageAttribution(
            creator: creator,
            licenseCode: licenseCode,
            licenseName: licenseName,
            licenseURL: licenseURL,
            sourceURL: sourceURL,
            modified: true
        )
    }

    private static func safeText(_ value: String) -> Bool {
        (1...maxTextScalars).contains(value.scalarCount) && PlaceContentGuards.isSafeText(value)
    }

    private static func allowedURL(_ value: Any?, hosts: Set<String>) -> URL? {
        guard let text = value as? String,
              (1...maxURLScalars).contains(text.scalarCount),
              PlaceContentGuards.isSafeURLString(text),
              let url = URL(string: text),
              url.scheme == "https",
              hosts.contains(url.host ?? "")
        else { return nil }
        return url
    }

    private static func isAllowedLicenseCode(_ code: String) -> Bool {
        let upper = code.uppercased()
        if ["PD", "PUBLIC DOMAIN", "PUBLIC-DOMAIN", "PDM-1.0", "CC0-1.0"].contains(upper) {
            return true
        }
        guard !upper.contains("NC"), !upper.contains("ND") else { return false }
        return upper.matches("^CC-BY(-SA)?-(1\\.0|2\\.0|2\\.1|2\\.5|3\\.0|4\\.0)(-[A-Z]{2,8})?$")
    }

    private static func isExpectedLicenseURL(_ url: URL, for code: String) -> Bool {
        guard url.query == nil, url.fragment == nil else { return false }
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let upper = code.uppercased()
        switch upper {
        case "PD", "PUBLIC DOMAIN", "PUBLIC-DOMAIN", "PDM-1.0":
            return path == "publicdomain/mark/1.0"
        case "CC0-1.0":
            return path == "publicdomain/zero/1.0"
        default:
            break
        }

        let prefix: String
        let family: String
        if upper.hasPrefix("CC-BY-SA-") {
            prefix = "CC-BY-SA-"
            family = "by-sa"
        } else if upper.hasPrefix("CC-BY-") {
            prefix = "CC-BY-"
            family = "by"
        } else {
            return false
        }

        let suffix = String(upper.dropFirst(prefix.count)).lowercased()
        let parts = suffix.split(separator: "-", maxSplits: 1).map(String.init)
        guard let version = parts.first else { return false }
        var expectedPath = "licenses/\(family)/\(version)"
        if parts.count == 2 {
            expectedPath += "/\(parts[1])"
        }
        return path == expectedPath
    }

    private static func requiresCreator(_ code: String) -> Bool {
        code.uppercased().hasPrefix("CC-BY")
    }
}

public final class ThumbnailCache: @unchecked Sendable {
    /// Tunable budget for card thumbnails; offline packs own their own thumbnail storage later.
    public static let maxBytes = 64 * 1024 * 1024
    /// Tunable ledger bound: enough for many recent thumbs while keeping thumb-access.json compact.
    static let maxAccessEntries = 4_096

    private let directory: URL
    private let maxBytes: Int
    private let maxAccessEntries: Int
    private let fm = FileManager.default
    private let lock = NSLock()
    private var accessCounter: Int
    private var accessEntries: [String: Int]

    public convenience init(directory: URL, maxBytes: Int = ThumbnailCache.maxBytes) throws {
        try self.init(directory: directory, maxBytes: maxBytes, maxAccessEntries: Self.maxAccessEntries)
    }

    init(directory: URL, maxBytes: Int = ThumbnailCache.maxBytes, maxAccessEntries: Int) throws {
        self.directory = directory
        self.maxBytes = maxBytes
        self.maxAccessEntries = maxAccessEntries
        let initialAccessURL = directory.appendingPathComponent("thumb-access.json")
        if let stored = try? JSONDecoder().decode(TileAccess.self, from: Data(contentsOf: initialAccessURL)) {
            accessCounter = stored.next
            accessEntries = stored.entries
        } else {
            accessCounter = 1
            accessEntries = [:]
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func storeThumbnail(sha256: String, data: Data) throws {
        guard sha256.matches("^[0-9a-f]{64}$") else { throw TileError.checksumMismatch }
        let url = thumbnailURL(sha256: sha256)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try touch(url)
        try trimIfNeeded()
    }

    public func thumbnail(sha256: String) -> Data? {
        guard sha256.matches("^[0-9a-f]{64}$") else { return nil }
        let url = thumbnailURL(sha256: sha256)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? touch(url)
        return data
    }

    private func thumbnailURL(sha256: String) -> URL {
        directory
            .appendingPathComponent(String(sha256.prefix(2)))
            .appendingPathComponent("\(sha256).webp")
    }

    private func trimIfNeeded() throws {
        let access = accessSnapshot()
        let files = try thumbnailFiles()
        var total = files.reduce(0) { $0 + $1.bytes }
        for file in files.sorted(by: { access[cacheKey($0.url), default: 0] < access[cacheKey($1.url), default: 0] }) where total > maxBytes {
            do {
                try fm.removeItem(at: file.url)
            } catch {
                continue
            }
            total -= file.bytes
        }
        try compactAccessLedger(keeping: Set(thumbnailFiles().map { cacheKey($0.url) }))
    }

    private func thumbnailFiles() throws -> [(url: URL, bytes: Int)] {
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return []
        }
        var files: [(URL, Int)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true, url.pathExtension == "webp" {
                let bytes = values.fileSize ?? ((try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0)
                files.append((url, bytes))
            }
        }
        return files
    }

    private func touch(_ url: URL) throws {
        lock.lock()
        accessEntries[cacheKey(url)] = accessCounter
        accessCounter += 1
        compactAccessEntriesLocked()
        let snapshot = TileAccess(next: accessCounter, entries: accessEntries)
        lock.unlock()
        try JSONEncoder().encode(snapshot).write(to: accessURL, options: .atomic)
    }

    private func compactAccessLedger(keeping keptKeys: Set<String>) throws {
        lock.lock()
        accessEntries = accessEntries.filter { keptKeys.contains($0.key) }
        compactAccessEntriesLocked()
        let snapshot = TileAccess(next: accessCounter, entries: accessEntries)
        lock.unlock()
        try JSONEncoder().encode(snapshot).write(to: accessURL, options: .atomic)
    }

    private func compactAccessEntriesLocked() {
        guard accessEntries.count > maxAccessEntries else { return }
        let keep = Set(accessEntries.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.prefix(maxAccessEntries).map(\.key))
        accessEntries = accessEntries.filter { keep.contains($0.key) }
    }

    private var accessURL: URL {
        directory.appendingPathComponent("thumb-access.json")
    }

    private func accessSnapshot() -> [String: Int] {
        lock.lock()
        let snapshot = accessEntries
        lock.unlock()
        return snapshot
    }

    private func cacheKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}

private func fetchBounded(_ fetcher: TileFetching, url: URL, maxBytes: Int) async throws -> Data {
    if let boundedFetcher = fetcher as? BoundedTileFetching {
        return try await boundedFetcher.fetch(url, maxBytes: maxBytes)
    }
    let data = try await fetcher.fetch(url)
    guard data.count <= maxBytes else { throw TileError.responseTooLarge }
    return data
}

public final class ThumbnailLoader: @unchecked Sendable {
    private let fetcher: any TileFetching
    private let cache: ThumbnailCache

    public init(fetcher: any TileFetching, cache: ThumbnailCache) {
        self.fetcher = fetcher
        self.cache = cache
    }

    public func data(for image: PlaceImage) async throws -> Data {
        guard image.thumbSHA256.matches("^[0-9a-f]{64}$"),
              (1...ImagePayloadLimits.maxThumbnailBytes).contains(image.bytes)
        else { throw TileError.invalidImageIndex }

        if let cached = cache.thumbnail(sha256: image.thumbSHA256),
           cached.count == image.bytes,
           sha256(cached) == image.thumbSHA256 {
            return cached
        }

        let data = try await fetchBounded(fetcher, url: image.thumbURL, maxBytes: image.bytes)
        guard data.count == image.bytes else { throw TileError.byteCountMismatch }
        guard sha256(data) == image.thumbSHA256 else { throw TileError.checksumMismatch }
        try cache.storeThumbnail(sha256: image.thumbSHA256, data: data)
        return data
    }
}

public enum PlaceContentGuards {
    public static let allowedPlaceKeys: Set<String> = [
        "place_id", "name", "lat", "lon", "category", "tier", "score", "source_refs",
        "alt_names", "blurb", "image_url", "wikipedia_title",
    ]
    public static let sourceRefPattern = "^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._/-]*$"

    public static func isSafeText(_ text: String) -> Bool {
        text.isSafeText
    }

    public static func isSafeURLString(_ text: String) -> Bool {
        text.isSafeURLString
    }

    public static func isValidSourceRef(_ ref: String) -> Bool {
        ref.scalarCount <= 128 && ref.matches(sourceRefPattern)
    }
}

public enum PlaceDecoder {
    private static let attributionRequiredSources: Set<String> = ["osm", "historic_england", "open_plaques"]

    public static func decode(
        tileData: Data,
        expected: TileCoordinate,
        attributionSources: Set<String>
    ) throws -> DecodedTile {
        guard let object = try JSONSerialization.jsonObject(with: tileData) as? [String: Any],
              Set(object.keys) == ["schema_version", "z", "x", "y", "places"],
              object["schema_version"] as? Int == 1,
              object["z"] as? Int == expected.z,
              object["x"] as? Int == expected.x,
              object["y"] as? Int == expected.y,
              let places = object["places"] as? [[String: Any]],
              places.count <= 4_000
        else { throw TileError.invalidTile }

        var decoded: [DecodedPlace] = []
        var missing: Set<String> = []
        for place in places {
            guard let item = decodePlace(place) else { continue }
            decoded.append(item)
            for source in item.sourceRefs.compactMap(refPrefix) where attributionRequiredSources.contains(source) {
                if !attributionSources.contains(source) {
                    missing.insert(source)
                }
            }
        }
        return DecodedTile(places: decoded, missingAttributionSources: missing)
    }

    private static func decodePlace(_ place: [String: Any]) -> DecodedPlace? {
        guard Set(place.keys).isSubset(of: PlaceContentGuards.allowedPlaceKeys),
              let placeID = place["place_id"] as? String,
              placeID.matches("^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$"),
              let name = place["name"] as? String,
              PlaceContentGuards.isSafeText(name),
              (1...200).contains(name.scalarCount),
              let lat = place["lat"] as? Double,
              lat.isFinite,
              (-90.0...90.0).contains(lat),
              let lon = place["lon"] as? Double,
              lon.isFinite,
              (-180.0...180.0).contains(lon),
              let category = place["category"] as? String,
              PlaceContentGuards.isSafeText(category),
              (1...64).contains(category.scalarCount),
              let tier = place["tier"] as? Int,
              (1...4).contains(tier),
              let score = place["score"] as? Double,
              score.isFinite,
              (0.0...1.0).contains(score),
              let sourceRefs = place["source_refs"] as? [String],
              (1...64).contains(sourceRefs.count),
              Set(sourceRefs).count == sourceRefs.count,
              sourceRefs.allSatisfy(PlaceContentGuards.isValidSourceRef)
        else { return nil }

        if let altNames = place["alt_names"] as? [String] {
            guard altNames.count <= 8,
                  altNames.allSatisfy({ (1...200).contains($0.scalarCount) && PlaceContentGuards.isSafeText($0) })
            else { return nil }
        }
        guard optionalText(place["blurb"], max: 600),
              optionalText(place["wikipedia_title"], max: 300)
        else { return nil }

        var sanitizedPlace = place
        if place.keys.contains("image_url") {
            sanitizedPlace["image_url"] = NSNull()
        }

        let rawJSON = (try? stableJSONString(sanitizedPlace)) ?? "{}"
        guard let placeRef = try? PlaceRef(
            placeID: placeID,
            name: name,
            lat: lat,
            lon: lon,
            category: category,
            tier: tier,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: rawJSON
        ) else { return nil }

        return DecodedPlace(
            mapPlace: MapPlace(id: placeID, lat: lat, lon: lon, tier: tier, category: category),
            placeRef: placeRef,
            imageURL: nil,
            sourceRefs: sourceRefs
        )
    }

    private static func optionalText(_ value: Any?, max: Int) -> Bool {
        if value == nil || value is NSNull { return true }
        guard let text = value as? String else { return false }
        return text.scalarCount <= max && PlaceContentGuards.isSafeText(text)
    }

    private static func refPrefix(_ ref: String) -> String? {
        ref.split(separator: ":", maxSplits: 1).first.map(String.init)
    }
}

public enum TileCoverage {
    public static func lonLatToZ10(lat: Double, lon: Double) -> TileCoordinate {
        let n = Double(1 << 10)
        let latRad = lat * .pi / 180.0
        let x = Int((lon + 180.0) / 360.0 * n)
        let y = Int((1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n)
        return TileCoordinate(z: 10, x: clampTile(x), y: clampTile(y))
    }

    public static func tiles(for bbox: BBox, prefetchRadius: Int = PrefetchRing.radius) -> [TileCoordinate] {
        let corners = [
            lonLatToZ10(lat: bbox.minLat, lon: bbox.minLon),
            lonLatToZ10(lat: bbox.minLat, lon: bbox.maxLon),
            lonLatToZ10(lat: bbox.maxLat, lon: bbox.minLon),
            lonLatToZ10(lat: bbox.maxLat, lon: bbox.maxLon),
        ]
        let minX = clampTile((corners.map(\.x).min() ?? 0) - prefetchRadius)
        let maxX = clampTile((corners.map(\.x).max() ?? 0) + prefetchRadius)
        let minY = clampTile((corners.map(\.y).min() ?? 0) - prefetchRadius)
        let maxY = clampTile((corners.map(\.y).max() ?? 0) + prefetchRadius)
        var out: [TileCoordinate] = []
        for x in minX...maxX {
            for y in minY...maxY {
                out.append(TileCoordinate(z: 10, x: x, y: y))
            }
        }
        return out
    }

    private static func clampTile(_ value: Int) -> Int {
        min(1023, max(0, value))
    }
}

public enum PrefetchRing {
    /// Tunable after fast-pan measurement; B3 ships the privacy/cache-friendly 1-tile ring.
    public static let radius = 1
}

public struct RegionIndex: Sendable, Equatable {
    public static let maxBytes = 512 * 1024
    public static let maxRegionCount = 10_000

    public let schemaVersion: Int
    public let minReaderVersion: Int
    public let generatedAt: String?
    public let regions: [Entry]

    public struct Entry: Sendable, Equatable {
        public let id: String
        public let displayName: String
        public let parent: String?
        public let bbox: BBox
        public let publishVersion: String?
        public let basemapBytes: Int
        public let tileCount: Int
        public let bytesWithoutThumbnails: Int
        public let bytesWithThumbnails: Int
    }

    public static func decode(_ data: Data) throws -> RegionIndex {
        guard data.count <= maxBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw TileError.invalidRegionIndex }
        let allowed: Set<String> = ["schema_version", "min_reader_version", "generated_at", "regions"]
        guard Set(object.keys).isSubset(of: allowed),
              let schemaVersion = object["schema_version"] as? Int,
              VersionGate.schema(readerMax: VersionGate.regionIndexReaderSchemaVersion, dataVersion: schemaVersion, minSupported: VersionGate.minSupportedSchemaVersion) == .ok,
              let minReaderVersion = object["min_reader_version"] as? Int,
              minReaderVersion >= 1,
              VersionGate.reader(minReaderVersion: minReaderVersion, hasReadableCache: false) == .ok,
              let entries = object["regions"] as? [[String: Any]],
              entries.count <= maxRegionCount
        else { throw TileError.invalidRegionIndex }
        if let generatedAt = object["generated_at"] as? String {
            guard generatedAt.count <= 32,
                  generatedAt.matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")
            else { throw TileError.invalidRegionIndex }
        } else if object.keys.contains("generated_at"), !(object["generated_at"] is NSNull) {
            throw TileError.invalidRegionIndex
        }
        let regions = try entries.map(decodeEntry)
        guard Set(regions.map(\.id)).count == regions.count else { throw TileError.invalidRegionIndex }
        let knownIDs = Set(regions.map(\.id))
        guard regions.allSatisfy({ $0.parent == nil || knownIDs.contains($0.parent!) }) else {
            throw TileError.invalidRegionIndex
        }
        return RegionIndex(
            schemaVersion: schemaVersion,
            minReaderVersion: minReaderVersion,
            generatedAt: object["generated_at"] as? String,
            regions: regions
        )
    }

    private static func decodeEntry(_ object: [String: Any]) throws -> Entry {
        let allowed: Set<String> = [
            "id", "display_name", "parent", "bbox", "publish_version",
            "basemap_bytes", "tile_count", "bytes_without_thumbnails", "bytes_with_thumbnails",
        ]
        guard Set(object.keys).isSubset(of: allowed),
              let id = object["id"] as? String,
              id.matches(regionIDPattern),
              let displayName = object["display_name"] as? String,
              (1...120).contains(displayName.scalarCount),
              displayName.isSafeText,
              let bboxValues = object["bbox"] as? [Double],
              bboxValues.count == 4,
              let basemapBytes = object["basemap_bytes"] as? Int,
              (0...3_221_225_472).contains(basemapBytes),
              let tileCount = object["tile_count"] as? Int,
              (0...1_048_576).contains(tileCount),
              let bytesWithoutThumbnails = object["bytes_without_thumbnails"] as? Int,
              (0...20_000_000_000).contains(bytesWithoutThumbnails),
              let bytesWithThumbnails = object["bytes_with_thumbnails"] as? Int,
              (bytesWithoutThumbnails...20_000_000_000).contains(bytesWithThumbnails)
        else { throw TileError.invalidRegionIndex }
        let parent: String?
        if let value = object["parent"] as? String {
            guard value.matches(regionIDPattern) else { throw TileError.invalidRegionIndex }
            parent = value
        } else if object.keys.contains("parent"), !(object["parent"] is NSNull) {
            throw TileError.invalidRegionIndex
        } else {
            parent = nil
        }
        let publishVersion: String?
        if let value = object["publish_version"] as? String {
            guard value.matches("^[0-9]{8}T[0-9]{6}Z$") else { throw TileError.invalidRegionIndex }
            publishVersion = value
        } else if object.keys.contains("publish_version"), !(object["publish_version"] is NSNull) {
            throw TileError.invalidRegionIndex
        } else {
            publishVersion = nil
        }
        let bbox = BBox(minLon: bboxValues[0], minLat: bboxValues[1], maxLon: bboxValues[2], maxLat: bboxValues[3])
        guard bbox.minLon >= -180,
              bbox.maxLon <= 180,
              bbox.minLat >= -90,
              bbox.maxLat <= 90,
              bbox.minLon <= bbox.maxLon,
              bbox.minLat <= bbox.maxLat
        else { throw TileError.invalidRegionIndex }
        return Entry(
            id: id,
            displayName: displayName,
            parent: parent,
            bbox: bbox,
            publishVersion: publishVersion,
            basemapBytes: basemapBytes,
            tileCount: tileCount,
            bytesWithoutThumbnails: bytesWithoutThumbnails,
            bytesWithThumbnails: bytesWithThumbnails
        )
    }
}

public struct OfflineTileFetch: Sendable, Equatable {
    public let coordinate: TileCoordinate
    public let sha256: String
    public let bytes: Int

    public init(coordinate: TileCoordinate, sha256: String, bytes: Int) {
        self.coordinate = coordinate
        self.sha256 = sha256
        self.bytes = bytes
    }
}

public struct InstalledPackBasemap: Sendable, Equatable {
    public let region: String
    public let publishVersion: String
    public let sha256: String
    public let bytes: Int
}

public struct InstalledPackTile: Sendable, Equatable {
    public let region: String
    public let publishVersion: String
    public let coordinate: TileCoordinate
    public let tile: ManifestTile
    public let attribution: [Attribution]
    public let attributionSources: [String]
    public let packTileCount: Int
    public let basemap: InstalledPackBasemap
}

public struct OfflinePackQuarantine: Sendable, Equatable {
    public let region: String
    public let publishVersion: String?
    public let coordinates: Set<TileCoordinate>

    public init(region: String, publishVersion: String?, coordinates: Set<TileCoordinate>) {
        self.region = region
        self.publishVersion = publishVersion
        self.coordinates = coordinates
    }
}

public struct OfflinePackResolution: Sendable, Equatable {
    public let tiles: [InstalledPackTile]
    public let quarantinedPacks: [OfflinePackQuarantine]

    public var blockedCoordinates: Set<TileCoordinate> {
        quarantinedPacks.reduce(into: Set<TileCoordinate>()) { blocked, quarantine in
            blocked.formUnion(quarantine.coordinates)
        }
    }
}

public struct OfflineRegionUpdatePlan: Sendable, Equatable {
    public let tilesToFetch: [OfflineTileFetch]
    public let reusedTileCount: Int
    public let basemapNeedsFetch: Bool
    public let bytesToFetch: Int
}

public struct InstalledOfflinePackStorage: Sendable, Equatable {
    public let region: String
    public let publishVersion: String
    public let tileCount: Int
    public let tileBytes: Int
    public let basemapBytes: Int
    public let referencedBytes: Int

    public init(
        region: String,
        publishVersion: String,
        tileCount: Int,
        tileBytes: Int,
        basemapBytes: Int,
        referencedBytes: Int
    ) {
        self.region = region
        self.publishVersion = publishVersion
        self.tileCount = tileCount
        self.tileBytes = tileBytes
        self.basemapBytes = basemapBytes
        self.referencedBytes = referencedBytes
    }
}

public struct OfflinePackStorageSummary: Sendable, Equatable {
    public let packs: [InstalledOfflinePackStorage]
    public let failedRegions: [String]
    public let totalBytes: Int

    public init(packs: [InstalledOfflinePackStorage], failedRegions: [String] = [], totalBytes: Int) {
        self.packs = packs
        self.failedRegions = failedRegions
        self.totalBytes = totalBytes
    }
}

private struct OfflinePackStorageObjectSnapshot: Sendable, Equatable {
    let sha256: String
    let bytes: Int
}

private struct OfflinePackStoragePackSnapshot: Sendable, Equatable {
    let region: String
    let publishVersion: String
    let tiles: [OfflinePackStorageObjectSnapshot]
    let basemap: OfflinePackStorageObjectSnapshot
}

private struct OfflinePackStorageSnapshot: Sendable, Equatable {
    let packs: [OfflinePackStoragePackSnapshot]
    let failedRegions: [String]
}

public enum StorageHeadroom {
    public static let defaultReserveBytes: Int64 = 512 * 1024 * 1024

    public static func hasHeadroom(requiredBytes: Int, availableBytes: Int64?, reserveBytes: Int64 = defaultReserveBytes) -> Bool {
        guard requiredBytes >= 0, let availableBytes else { return false }
        return availableBytes >= Int64(requiredBytes) + reserveBytes
    }

    public static func availableBytes(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))
            .flatMap(\.volumeAvailableCapacityForImportantUsage)
    }
}

public enum OfflineDownloadSession {
    /// Stable per-region background identifier. Do not include mutable policy
    /// such as cellular settings; completed-download adoption is keyed by it.
    public static func backgroundIdentifier(region: String) -> String {
        "app.making-tracks.offline.\(region)"
    }

    public static func foregroundConfiguration(allowsCellularDownloads: Bool = false) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = allowsCellularDownloads
        configuration.allowsConstrainedNetworkAccess = allowsCellularDownloads
        harden(configuration)
        MakingTracksLog.downloads.info("session configured session=foreground discretionary=\(configuration.isDiscretionary, privacy: .public) launchEvents=\(configuration.sessionSendsLaunchEvents, privacy: .public) allowsExpensive=\(configuration.allowsExpensiveNetworkAccess, privacy: .public) allowsConstrained=\(configuration.allowsConstrainedNetworkAccess, privacy: .public)")
        return configuration
    }

    public static func backgroundConfiguration(
        identifier: String,
        allowsCellularDownloads: Bool = false
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = allowsCellularDownloads
        configuration.allowsConstrainedNetworkAccess = allowsCellularDownloads
        harden(configuration)
        MakingTracksLog.downloads.info("session configured session=background discretionary=\(configuration.isDiscretionary, privacy: .public) launchEvents=\(configuration.sessionSendsLaunchEvents, privacy: .public) allowsExpensive=\(configuration.allowsExpensiveNetworkAccess, privacy: .public) allowsConstrained=\(configuration.allowsConstrainedNetworkAccess, privacy: .public) identifier=\(identifier, privacy: .private(mask: .hash))")
        return configuration
    }

    static func harden(_ configuration: URLSessionConfiguration) {
        configuration.httpAdditionalHeaders = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
    }

    public static func prepareBackgroundSessionForPolicyChange(
        identifier: String,
        allowsCellularDownloads: Bool
    ) async {
        await OfflineBackgroundSessionRegistry.shared.prepareForPolicyChange(
            identifier: identifier,
            allowsCellularDownloads: allowsCellularDownloads
        )
    }

    public static func withBackgroundSessionUse<T: Sendable>(
        identifier: String,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        OfflineBackgroundSessionRegistry.shared.beginUse(identifier: identifier)
        defer {
            OfflineBackgroundSessionRegistry.shared.endUse(identifier: identifier)
        }
        return try await operation()
    }

    public static func handleEvents(
        for identifier: String,
        allowsCellularDownloads: Bool = false,
        completionHandler: @escaping () -> Void
    ) {
        MakingTracksLog.downloads.info("session events received identifier=\(identifier, privacy: .private(mask: .hash))")
        OfflineDownloadSessionEventRegistry.shared.handleEvents(
            for: identifier,
            completionHandler: completionHandler
        )
        let box = OfflineBackgroundSessionRegistry.shared.session(
            identifier: identifier,
            configuration: backgroundConfiguration(
                identifier: identifier,
                allowsCellularDownloads: allowsCellularDownloads
            )
        )
        box.delegate.adoptExistingTasks(on: box.session)
    }

    static func finishEvents(for identifier: String?) {
        guard let identifier else { return }
        MakingTracksLog.downloads.info("session events completing identifier=\(identifier, privacy: .private(mask: .hash))")
        OfflineDownloadSessionEventRegistry.shared.finishEvents(for: identifier)
    }

    static func hasBackgroundSessionForTesting(identifier: String) -> Bool {
        OfflineBackgroundSessionRegistry.shared.hasSession(identifier: identifier)
    }

#if DEBUG
    public static func invalidateBackgroundSessionForTesting(identifier: String) {
        OfflineBackgroundSessionRegistry.shared.invalidate(identifier: identifier)
    }
#else
    static func invalidateBackgroundSessionForTesting(identifier: String) {
        OfflineBackgroundSessionRegistry.shared.invalidate(identifier: identifier)
    }
#endif

    static func consumeCompletedDownload(identifier: String, url: URL) -> URL? {
        OfflineBackgroundCompletedDownloadStore.shared.consume(identifier: identifier, url: url)
    }

    static func restoreConsumedCompletedDownload(identifier: String, url: URL, fileURL: URL) {
        OfflineBackgroundCompletedDownloadStore.shared.restoreConsumed(identifier: identifier, url: url, fileURL: fileURL)
    }

    static func stageCompletedDownloadForTesting(
        identifier: String,
        url: URL,
        fileURL: URL,
        response: URLResponse?
    ) throws {
        try OfflineBackgroundCompletedDownloadStore.shared.stage(
            identifier: identifier,
            url: url,
            fileURL: fileURL,
            response: response
        )
    }

    static func removeCompletedDownloadsForTesting(identifier: String) {
        OfflineBackgroundCompletedDownloadStore.shared.removeAll(identifier: identifier)
    }

    static func performCompletedDownloadMaintenanceForTesting(maxBytes: Int) throws {
        try OfflineBackgroundCompletedDownloadStore.shared.performMaintenance(maxBytes: maxBytes)
    }

    static var completedDownloadStoreMaxBytesForTesting: Int {
        OfflineBackgroundCompletedDownloadStore.maxStoredDownloadBytes
    }

    static func replaceCompletedDownloadsIndexForTesting(_ data: Data) throws {
        try OfflineBackgroundCompletedDownloadStore.shared.replaceIndexForTesting(data)
    }

    static func createCompletedDownloadFileForTesting(named name: String, data: Data) throws {
        try OfflineBackgroundCompletedDownloadStore.shared.createDownloadFileForTesting(named: name, data: data)
    }

    static func hasCompletedDownloadFileForTesting(named name: String) -> Bool {
        OfflineBackgroundCompletedDownloadStore.shared.hasDownloadFileForTesting(named: name)
    }
}

private struct OfflineBackgroundSessionBox {
    let session: URLSession
    let delegate: RedirectDelegate
    let allowsCellularDownloads: Bool
}

private final class OfflineBackgroundSessionRegistry: @unchecked Sendable {
    static let shared = OfflineBackgroundSessionRegistry()

    private let lock = NSLock()
    private var sessions: [String: OfflineBackgroundSessionBox] = [:]
    private var activeUses: [String: Int] = [:]

    func session(identifier: String, configuration: URLSessionConfiguration) -> OfflineBackgroundSessionBox {
        lock.withLock {
            if let existing = sessions[identifier] {
                MakingTracksLog.downloads.debug("session reused session=background discretionary=\(existing.session.configuration.isDiscretionary, privacy: .public) identifier=\(identifier, privacy: .private(mask: .hash))")
                return existing
            }
            let delegate = RedirectDelegate()
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            let box = OfflineBackgroundSessionBox(
                session: session,
                delegate: delegate,
                allowsCellularDownloads: configuration.allowsExpensiveNetworkAccess
            )
            sessions[identifier] = box
            MakingTracksLog.downloads.info("session created session=background discretionary=\(configuration.isDiscretionary, privacy: .public) identifier=\(identifier, privacy: .private(mask: .hash))")
            return box
        }
    }

    func prepareForPolicyChange(identifier: String, allowsCellularDownloads: Bool) async {
        let candidate = lock.withLock {
            guard let existing = sessions[identifier],
                  existing.allowsCellularDownloads != allowsCellularDownloads
            else { return nil as OfflineBackgroundSessionBox? }
            guard activeUses[identifier, default: 0] == 0 else {
                MakingTracksLog.downloads.info("session reused session=background reason=active-tasks-kept-policy identifier=\(identifier, privacy: .private(mask: .hash))")
                return nil
            }
            guard !OfflineDownloadSessionEventRegistry.shared.hasPendingEvents(for: identifier) else {
                MakingTracksLog.downloads.info("session reused session=background reason=pending-events-kept-policy identifier=\(identifier, privacy: .private(mask: .hash))")
                return nil
            }
            return existing
        }
        guard let candidate else { return }
        guard await !candidate.delegate.hasTrackedOrAdoptableTasks(on: candidate.session) else {
            MakingTracksLog.downloads.info("session reused session=background reason=active-tasks-kept-policy identifier=\(identifier, privacy: .private(mask: .hash))")
            return
        }
        let stale = lock.withLock {
            guard let existing = sessions[identifier],
                  existing.session === candidate.session,
                  existing.allowsCellularDownloads != allowsCellularDownloads,
                  activeUses[identifier, default: 0] == 0,
                  !OfflineDownloadSessionEventRegistry.shared.hasPendingEvents(for: identifier),
                  !existing.delegate.hasTrackedTasks()
            else { return nil as OfflineBackgroundSessionBox? }
            sessions.removeValue(forKey: identifier)
            return existing
        }
        guard let stale else { return }
        MakingTracksLog.downloads.info("session invalidating session=background reason=cellular-policy identifier=\(identifier, privacy: .private(mask: .hash))")
        await stale.delegate.invalidateAndWait(stale.session)
    }

    func beginUse(identifier: String) {
        lock.withLock {
            activeUses[identifier, default: 0] += 1
        }
    }

    func endUse(identifier: String) {
        lock.withLock {
            let remaining = activeUses[identifier, default: 0] - 1
            if remaining > 0 {
                activeUses[identifier] = remaining
            } else {
                activeUses.removeValue(forKey: identifier)
            }
        }
    }

    func hasSession(identifier: String) -> Bool {
        lock.withLock {
            sessions[identifier] != nil
        }
    }

    func invalidate(identifier: String) {
        let box = lock.withLock {
            activeUses.removeValue(forKey: identifier)
            return sessions.removeValue(forKey: identifier)
        }
        MakingTracksLog.downloads.info("session invalidated identifier=\(identifier, privacy: .private(mask: .hash))")
        box?.session.invalidateAndCancel()
        box?.delegate.cancelAll(with: URLError(.cancelled))
    }
}

private final class OfflineDownloadSessionEventRegistry: @unchecked Sendable {
    static let shared = OfflineDownloadSessionEventRegistry()

    private let lock = NSLock()
    private var completionHandlers: [String: () -> Void] = [:]

    func handleEvents(for identifier: String, completionHandler: @escaping () -> Void) {
        lock.withLock {
            completionHandlers[identifier] = completionHandler
        }
        MakingTracksLog.downloads.debug("session event handler stored identifier=\(identifier, privacy: .private(mask: .hash))")
    }

    func finishEvents(for identifier: String) {
        let completionHandler = lock.withLock {
            completionHandlers.removeValue(forKey: identifier)
        }
        guard let completionHandler else { return }
        MakingTracksLog.downloads.debug("session event handler firing identifier=\(identifier, privacy: .private(mask: .hash))")
        DispatchQueue.main.async {
            completionHandler()
        }
    }

    func hasPendingEvents(for identifier: String) -> Bool {
        lock.withLock {
            completionHandlers[identifier] != nil
        }
    }
}

public struct OfflineRegionDownloadResult: Sendable, Equatable {
    public let publish: PinnedPublish
    public let fetchedTileCount: Int
    public let reusedTileCount: Int
    public let fetchedBytes: Int
}

public struct OfflineRegionDownloadProgress: Sendable, Equatable {
    public let region: String
    public let publishVersion: String
    public let completedBytes: Int
    public let totalBytes: Int
    public let completedObjectCount: Int
    public let totalObjectCount: Int
    public let isWaitingForConnectivity: Bool

    public init(
        region: String,
        publishVersion: String,
        completedBytes: Int,
        totalBytes: Int,
        completedObjectCount: Int,
        totalObjectCount: Int,
        isWaitingForConnectivity: Bool = false
    ) {
        self.region = region
        self.publishVersion = publishVersion
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedObjectCount = completedObjectCount
        self.totalObjectCount = totalObjectCount
        self.isWaitingForConnectivity = isWaitingForConnectivity
    }

    public var fractionComplete: Double {
        guard totalBytes > 0 else { return 1 }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }
}

public final class OfflineRegionDownloadControl: @unchecked Sendable {
    fileprivate enum State: Equatable {
        case running
        case paused
        case cancelled
    }

    fileprivate enum Interruption: Sendable {
        case paused
        case cancelled
    }

    private let lock = NSLock()
    private var state: State = .running
    private var interruptionHandlers: [UUID: @Sendable (Interruption) -> Void] = [:]

    public init() {}

    public func pause() {
        MakingTracksLog.downloads.info("control transition state=paused")
        interrupt(with: .paused)
    }

    public func resume() {
        lock.withLock {
            state = .running
        }
        MakingTracksLog.downloads.info("control transition state=running")
    }

    public func cancel() {
        MakingTracksLog.downloads.info("control transition state=cancelled")
        interrupt(with: .cancelled)
    }

    fileprivate func checkpoint() throws {
        let next = lock.withLock { state }
        switch next {
        case .running:
            return
        case .paused:
            MakingTracksLog.downloads.debug("control checkpoint state=paused")
            throw TileError.downloadPaused
        case .cancelled:
            MakingTracksLog.downloads.debug("control checkpoint state=cancelled")
            throw TileError.downloadCancelled
        }
    }

    fileprivate func registerInterruptionHandler(_ handler: @escaping @Sendable (Interruption) -> Void) -> UUID {
        let id = UUID()
        let immediateInterruption = lock.withLock {
            switch state {
            case .running:
                interruptionHandlers[id] = handler
                return nil as Interruption?
            case .paused:
                interruptionHandlers[id] = handler
                return .paused
            case .cancelled:
                return .cancelled
            }
        }
        if let immediateInterruption {
            MakingTracksLog.downloads.debug("control latch immediate state=\(String(describing: immediateInterruption), privacy: .public)")
            handler(immediateInterruption)
        }
        return id
    }

    fileprivate func unregisterInterruptionHandler(_ id: UUID) {
        _ = lock.withLock {
            interruptionHandlers.removeValue(forKey: id)
        }
    }

    private func interrupt(with next: State) {
        let (interruption, handlers) = lock.withLock {
            state = next
            let handlers = Array(interruptionHandlers.values)
            if next == .cancelled {
                interruptionHandlers.removeAll()
            }
            return (next.interruption, handlers)
        }
        for handler in handlers {
            handler(interruption)
        }
        MakingTracksLog.downloads.debug("control handlers notified count=\(handlers.count, privacy: .public) state=\(String(describing: interruption), privacy: .public)")
    }
}

private extension OfflineRegionDownloadControl.State {
    var interruption: OfflineRegionDownloadControl.Interruption {
        switch self {
        case .running:
            preconditionFailure("running is not an interruption")
        case .paused:
            return .paused
        case .cancelled:
            return .cancelled
        }
    }
}

private final class OfflineRegionDownloadInterruptionLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var interruption: OfflineRegionDownloadControl.Interruption?

    func record(_ next: OfflineRegionDownloadControl.Interruption) {
        lock.withLock {
            if next == .cancelled || interruption == nil {
                interruption = next
            }
        }
        MakingTracksLog.downloads.debug("latch recorded state=\(String(describing: next), privacy: .public)")
    }

    func error() -> TileError? {
        lock.withLock {
            switch interruption {
            case .paused:
                MakingTracksLog.downloads.debug("latch resolved state=paused")
                return .downloadPaused
            case .cancelled:
                MakingTracksLog.downloads.debug("latch resolved state=cancelled")
                return .downloadCancelled
            case nil:
                MakingTracksLog.downloads.debug("latch resolved state=none")
                return nil
            }
        }
    }
}

public final class OfflineRegionDownloader: @unchecked Sendable {
    private struct TargetPublish {
        let publish: PinnedPublish
        let source: Source

        enum Source: Equatable {
            case pending
            case current
        }
    }

    private let region: String
    private let metadataFetcher: TileFetching
    private let objectFetcher: OfflineRegionFetching
    private let store: OfflineRegionStore
    private let availableBytes: @Sendable () -> Int64?

    public init(
        region: String,
        fetcher: OfflineRegionFetching,
        store: OfflineRegionStore,
        availableBytes: @escaping @Sendable () -> Int64?
    ) {
        self.region = region
        metadataFetcher = fetcher
        objectFetcher = fetcher
        self.store = store
        self.availableBytes = availableBytes
    }

    public init(
        region: String,
        metadataFetcher: TileFetching,
        objectFetcher: OfflineRegionFetching,
        store: OfflineRegionStore,
        availableBytes: @escaping @Sendable () -> Int64?
    ) {
        self.region = region
        self.metadataFetcher = metadataFetcher
        self.objectFetcher = objectFetcher
        self.store = store
        self.availableBytes = availableBytes
    }

    public func downloadCurrentRegion(
        resumingPausedDownload: Bool = false,
        control: OfflineRegionDownloadControl = OfflineRegionDownloadControl(),
        progress: (@Sendable (OfflineRegionDownloadProgress) -> Void)? = nil
    ) async throws -> OfflineRegionDownloadResult {
        let startedAt = Date()
        guard region.matches(regionIDPattern) else {
            MakingTracksLog.downloads.error("region download rejected reason=invalid-region")
            throw TileError.invalidOfflinePack
        }
        let regionID = region
        do {
            try store.acquireDownloadLease(region: region)
            MakingTracksLog.downloads.info("region download started region=\(regionID, privacy: .private(mask: .hash))")
        } catch {
            MakingTracksLog.downloads.error("region download lease failed region=\(regionID, privacy: .private(mask: .hash)) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            throw error
        }
        defer {
            store.releaseDownloadLease(region: region)
            MakingTracksLog.downloads.debug("region download lease released region=\(regionID, privacy: .private(mask: .hash))")
        }
        let target: TargetPublish
        do {
            target = try await targetPublish(
                allowPending: true,
                resumingPausedDownload: resumingPausedDownload,
                progress: progress
            )
        } catch {
            MakingTracksLog.downloads.error("region metadata failed region=\(regionID, privacy: .private(mask: .hash)) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            throw error
        }
        return try await download(
            target: target,
            startedAt: startedAt,
            control: control,
            progress: progress
        )
    }

    private func download(
        target: TargetPublish,
        startedAt: Date,
        control: OfflineRegionDownloadControl,
        progress: (@Sendable (OfflineRegionDownloadProgress) -> Void)?
    ) async throws -> OfflineRegionDownloadResult {
        let publish: PinnedPublish
        publish = target.publish
        let regionID = region
        let publishVersion = publish.publishVersion
        let manifest = publish.manifest
        let plan = try store.updatePlan(for: publish)
        let fetchObjectCount = plan.tilesToFetch.count + (plan.basemapNeedsFetch ? 1 : 0)
        let reusedObjectCount = plan.reusedTileCount + (plan.basemapNeedsFetch ? 0 : 1)
        MakingTracksLog.downloads.info("plan computed region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) fetchObjects=\(fetchObjectCount, privacy: .public) reusedObjects=\(reusedObjectCount, privacy: .public) bytes=\(plan.bytesToFetch, privacy: .public)")
        let available = availableBytes()
        guard StorageHeadroom.hasHeadroom(requiredBytes: plan.bytesToFetch, availableBytes: available) else {
            MakingTracksLog.downloads.error("plan rejected region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) bytes=\(plan.bytesToFetch, privacy: .public) available=\(available ?? -1, privacy: .public)")
            throw TileError.insufficientStorage
        }
        try store.beginDownload(publish: publish)

        do {
            let totalObjectCount = manifest.tiles.count + 1
            var completedObjectCount = plan.reusedTileCount + (plan.basemapNeedsFetch ? 0 : 1)
            let totalBytes = manifest.tiles.reduce(0) { $0 + $1.bytes } + manifest.basemap.bytes
            var completedBytes = totalBytes - plan.bytesToFetch
            for item in plan.tilesToFetch {
                try control.checkpoint()
                MakingTracksLog.downloads.debug("object fetch planned region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) kind=tile sha=\(item.sha256, privacy: .private(mask: .hash)) bytes=\(item.bytes, privacy: .public)")
                try ensureHeadroomForSmallObject(bytes: item.bytes)
                let fileURL: URL
                let waitingProgress = OfflineRegionDownloadProgress(
                    region: region,
                    publishVersion: publishVersion,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    completedObjectCount: completedObjectCount,
                    totalObjectCount: totalObjectCount,
                    isWaitingForConnectivity: true
                )
                let availableProgress = OfflineRegionDownloadProgress(
                    region: region,
                    publishVersion: publishVersion,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    completedObjectCount: completedObjectCount,
                    totalObjectCount: totalObjectCount,
                    isWaitingForConnectivity: false
                )
                do {
                    let objectStartBytes = completedBytes
                    let objectStartCount = completedObjectCount
                    fileURL = try await downloadObject(
                        try trustedURL("\(region)/\(publishVersion)/tiles/10/\(item.coordinate.x)/\(item.coordinate.y).json.gz"),
                        control: control,
                        connectivityWaiting: { progress?(waitingProgress) },
                        connectivityAvailable: { progress?(availableProgress) },
                        progress: { totalBytesWritten, totalBytesExpectedToWrite in
                            let objectBytes = Self.completedObjectBytes(
                                totalBytesWritten: totalBytesWritten,
                                totalBytesExpectedToWrite: totalBytesExpectedToWrite,
                                expectedObjectBytes: item.bytes
                            )
                            progress?(OfflineRegionDownloadProgress(
                                region: regionID,
                                publishVersion: publishVersion,
                                completedBytes: objectStartBytes + objectBytes,
                                totalBytes: totalBytes,
                                completedObjectCount: objectStartCount,
                                totalObjectCount: totalObjectCount
                            ))
                        }
                    )
                    defer { try? FileManager.default.removeItem(at: fileURL) }
                    try store.stageDownloadedTileObject(fileURL, sha256: item.sha256, bytes: item.bytes)
                } catch {
                    if isOutOfSpace(error) {
                        MakingTracksLog.downloads.info("object fetch interrupted region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) kind=tile reason=out-of-space")
                        throw TileError.downloadPaused
                    }
                    throw error
                }
                completedObjectCount += 1
                completedBytes += item.bytes
                MakingTracksLog.downloads.debug("object staged region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) kind=tile completed=\(completedObjectCount, privacy: .public) total=\(totalObjectCount, privacy: .public) bytes=\(completedBytes, privacy: .public)")
                progress?(OfflineRegionDownloadProgress(
                    region: region,
                    publishVersion: publishVersion,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    completedObjectCount: completedObjectCount,
                    totalObjectCount: totalObjectCount
                ))
            }
            if plan.basemapNeedsFetch {
                try control.checkpoint()
                MakingTracksLog.downloads.debug("object fetch planned region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) kind=basemap sha=\(manifest.basemap.sha256, privacy: .private(mask: .hash)) bytes=\(manifest.basemap.bytes, privacy: .public)")
                try ensureHeadroomForLargeObject(bytes: manifest.basemap.bytes)
                let fileURL: URL
                let waitingProgress = OfflineRegionDownloadProgress(
                    region: region,
                    publishVersion: publishVersion,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    completedObjectCount: completedObjectCount,
                    totalObjectCount: totalObjectCount,
                    isWaitingForConnectivity: true
                )
                let availableProgress = OfflineRegionDownloadProgress(
                    region: region,
                    publishVersion: publishVersion,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    completedObjectCount: completedObjectCount,
                    totalObjectCount: totalObjectCount,
                    isWaitingForConnectivity: false
                )
                do {
                    let objectStartBytes = completedBytes
                    let objectStartCount = completedObjectCount
                    fileURL = try await downloadObject(
                        try trustedURL("\(region)/\(publishVersion)/\(manifest.basemap.filename)"),
                        control: control,
                        connectivityWaiting: { progress?(waitingProgress) },
                        connectivityAvailable: { progress?(availableProgress) },
                        progress: { totalBytesWritten, totalBytesExpectedToWrite in
                            let objectBytes = Self.completedObjectBytes(
                                totalBytesWritten: totalBytesWritten,
                                totalBytesExpectedToWrite: totalBytesExpectedToWrite,
                                expectedObjectBytes: manifest.basemap.bytes
                            )
                            progress?(OfflineRegionDownloadProgress(
                                region: regionID,
                                publishVersion: publishVersion,
                                completedBytes: objectStartBytes + objectBytes,
                                totalBytes: totalBytes,
                                completedObjectCount: objectStartCount,
                                totalObjectCount: totalObjectCount
                            ))
                        }
                    )
                    defer { try? FileManager.default.removeItem(at: fileURL) }
                    try store.stageDownloadedBasemapObject(fileURL, sha256: manifest.basemap.sha256, bytes: manifest.basemap.bytes)
                } catch {
                    if isOutOfSpace(error) {
                        MakingTracksLog.downloads.info("object fetch interrupted region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) kind=basemap reason=out-of-space")
                        throw TileError.downloadPaused
                    }
                    throw error
                }
                completedObjectCount += 1
                completedBytes += manifest.basemap.bytes
                MakingTracksLog.downloads.debug("object staged region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) kind=basemap completed=\(completedObjectCount, privacy: .public) total=\(totalObjectCount, privacy: .public) bytes=\(completedBytes, privacy: .public)")
                progress?(OfflineRegionDownloadProgress(
                    region: region,
                    publishVersion: publishVersion,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    completedObjectCount: completedObjectCount,
                    totalObjectCount: totalObjectCount
                ))
            }
            try control.checkpoint()
            try store.install(publish: publish, tiles: [:], basemap: nil)
        } catch TileError.downloadCancelled {
            MakingTracksLog.downloads.info("region download cancelled region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public)")
            try? store.discardDownload(region: region, publishVersion: publishVersion)
            throw TileError.downloadCancelled
        } catch TileError.downloadPaused {
            MakingTracksLog.downloads.info("region download paused region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public)")
            try? store.markDownloadPaused(region: region, publishVersion: publishVersion)
            throw TileError.downloadPaused
        } catch {
            MakingTracksLog.downloads.error("region download failed region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            throw error
        }
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        MakingTracksLog.downloads.info("region download finished region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) fetchedObjects=\(fetchObjectCount, privacy: .public) reusedObjects=\(reusedObjectCount, privacy: .public) bytes=\(plan.bytesToFetch, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
        return OfflineRegionDownloadResult(
            publish: publish,
            fetchedTileCount: plan.tilesToFetch.count,
            reusedTileCount: plan.reusedTileCount,
            fetchedBytes: plan.bytesToFetch
        )
    }

    private func targetPublish(
        allowPending: Bool,
        resumingPausedDownload: Bool,
        progress: (@Sendable (OfflineRegionDownloadProgress) -> Void)?
    ) async throws -> TargetPublish {
        let regionID = region
        if allowPending {
            if !resumingPausedDownload, try store.hasPausedPendingDownload(region: region) {
                MakingTracksLog.downloads.info("region pending download skipped region=\(regionID, privacy: .private(mask: .hash)) reason=paused")
                throw TileError.downloadPaused
            }
            if let pending = try store.pendingDownload(region: region, includePaused: resumingPausedDownload) {
                MakingTracksLog.downloads.info("region pending download resumed region=\(regionID, privacy: .private(mask: .hash)) version=\(pending.publishVersion, privacy: .public)")
                return TargetPublish(publish: pending, source: .pending)
            }
        }
        let currentData = try await fetchMetadata(
            try trustedURL("\(region)/current.json"),
            connectivityWaiting: {
                progress?(OfflineRegionDownloadProgress(
                    region: regionID,
                    publishVersion: "",
                    completedBytes: 0,
                    totalBytes: 0,
                    completedObjectCount: 0,
                    totalObjectCount: 0,
                    isWaitingForConnectivity: true
                ))
            },
            connectivityAvailable: {
                progress?(OfflineRegionDownloadProgress(
                    region: regionID,
                    publishVersion: "",
                    completedBytes: 0,
                    totalBytes: 0,
                    completedObjectCount: 0,
                    totalObjectCount: 0,
                    isWaitingForConnectivity: false
                ))
            }
        )
        let publishVersion = try ManifestClient.decodeCurrent(currentData)
        MakingTracksLog.downloads.info("region current pinned region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public)")
        let manifestData = try await fetchMetadata(
            try trustedURL("\(region)/\(publishVersion)/manifest.json"),
            connectivityWaiting: {
                progress?(OfflineRegionDownloadProgress(
                    region: regionID,
                    publishVersion: publishVersion,
                    completedBytes: 0,
                    totalBytes: 0,
                    completedObjectCount: 0,
                    totalObjectCount: 0,
                    isWaitingForConnectivity: true
                ))
            },
            connectivityAvailable: {
                progress?(OfflineRegionDownloadProgress(
                    region: regionID,
                    publishVersion: publishVersion,
                    completedBytes: 0,
                    totalBytes: 0,
                    completedObjectCount: 0,
                    totalObjectCount: 0,
                    isWaitingForConnectivity: false
                ))
            }
        )
        let manifest = try Manifest.decode(manifestData)
        guard manifest.region == region, manifest.publishVersion == publishVersion else {
            throw TileError.invalidManifest
        }
        let manifestBytes = manifest.tiles.reduce(0) { $0 + $1.bytes } + manifest.basemap.bytes
        MakingTracksLog.downloads.info("region manifest loaded region=\(regionID, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public) objects=\(manifest.tiles.count + 1, privacy: .public) bytes=\(manifestBytes, privacy: .public)")
        return TargetPublish(
            publish: PinnedPublish(region: region, publishVersion: publishVersion, manifest: manifest),
            source: .current
        )
    }

    private func ensureHeadroomForSmallObject(bytes: Int) throws {
        guard bytes >= 0 else { throw TileError.invalidOfflinePack }
        let peakBytes = bytes.multipliedReportingOverflow(by: 2)
        guard !peakBytes.overflow else { throw TileError.invalidOfflinePack }
        guard StorageHeadroom.hasHeadroom(requiredBytes: peakBytes.partialValue, availableBytes: availableBytes()) else {
            throw TileError.downloadPaused
        }
    }

    private func ensureHeadroomForLargeObject(bytes: Int) throws {
        guard bytes >= 0 else { throw TileError.invalidOfflinePack }
        guard StorageHeadroom.hasHeadroom(requiredBytes: bytes, availableBytes: availableBytes()) else {
            throw TileError.downloadPaused
        }
    }

    private func fetchMetadata(
        _ url: URL,
        connectivityWaiting: (@Sendable () -> Void)? = nil,
        connectivityAvailable: (@Sendable () -> Void)? = nil
    ) async throws -> Data {
        if let waitingFetcher = metadataFetcher as? ConnectivityWaitingOfflineRegionFetching {
            return try await waitingFetcher.fetch(
                url,
                connectivityWaiting: connectivityWaiting,
                connectivityAvailable: connectivityAvailable
            )
        }
        return try await metadataFetcher.fetch(url)
    }

    private func downloadObject(
        _ url: URL,
        control: OfflineRegionDownloadControl,
        connectivityWaiting: (@Sendable () -> Void)? = nil,
        connectivityAvailable: (@Sendable () -> Void)? = nil,
        progress: (@Sendable (_ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)? = nil
    ) async throws -> URL {
        try control.checkpoint()
        let backgroundIdentifier = OfflineDownloadSession.backgroundIdentifier(region: region)
        if let completedURL = OfflineDownloadSession.consumeCompletedDownload(identifier: backgroundIdentifier, url: url) {
            do {
                try control.checkpoint()
            } catch {
                OfflineDownloadSession.restoreConsumedCompletedDownload(
                    identifier: backgroundIdentifier,
                    url: url,
                    fileURL: completedURL
                )
                throw error
            }
            MakingTracksLog.downloads.info("object completed download adopted host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public)")
            return completedURL
        }
        MakingTracksLog.downloads.debug("object task spawning host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public)")
        let downloadTask = Task {
            if let waitingFetcher = objectFetcher as? ConnectivityWaitingOfflineRegionFetching {
                if let progressFetcher = waitingFetcher as? ProgressReportingOfflineRegionFetching {
                    return try await progressFetcher.download(
                        url,
                        connectivityWaiting: connectivityWaiting,
                        connectivityAvailable: connectivityAvailable,
                        progress: progress
                    )
                }
                return try await waitingFetcher.download(
                    url,
                    connectivityWaiting: connectivityWaiting,
                    connectivityAvailable: connectivityAvailable
                )
            }
            return try await objectFetcher.download(url)
        }
        let interruptionLatch = OfflineRegionDownloadInterruptionLatch()
        let handlerID = control.registerInterruptionHandler { interruption in
            interruptionLatch.record(interruption)
            downloadTask.cancel()
        }
        defer {
            control.unregisterInterruptionHandler(handlerID)
        }
        do {
            let fileURL = try await downloadTask.value
            try control.checkpoint()
            MakingTracksLog.downloads.debug("object task finished host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public)")
            return fileURL
        } catch is CancellationError {
            if let error = interruptionLatch.error() {
                MakingTracksLog.downloads.info("object task interrupted host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
                throw error
            }
            throw TileError.downloadCancelled
        } catch let error as URLError where error.code == .cancelled {
            if let error = interruptionLatch.error() {
                MakingTracksLog.downloads.info("object task interrupted host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
                throw error
            }
            throw error
        } catch {
            MakingTracksLog.downloads.error("object task failed host=\(MakingTracksLog.host(url), privacy: .public) kind=\(MakingTracksLog.objectKind(url), privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            throw error
        }
    }

    private static func completedObjectBytes(
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64,
        expectedObjectBytes: Int
    ) -> Int {
        guard expectedObjectBytes >= 0 else { return 0 }
        let upperBound = Int64(expectedObjectBytes)
        let expected = totalBytesExpectedToWrite > 0
            ? min(totalBytesExpectedToWrite, upperBound)
            : upperBound
        let clamped = min(max(totalBytesWritten, 0), expected, upperBound)
        return Int(clamped)
    }
}

private func isOutOfSpace(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
        return true
    }
    if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC) {
        return true
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
        return isOutOfSpace(underlying)
    }
    return false
}

private final class OfflineRegionStoreRootState: @unchecked Sendable {
    let lock = NSLock()
    var activeDownloadRegions = Set<String>()
    var liveTemporaryObjectNames = Set<String>()
}

private enum OfflineRegionStoreRootStates {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var states: [String: OfflineRegionStoreRootState] = [:]

    static func state(for root: URL) -> OfflineRegionStoreRootState {
        let key = root.standardizedFileURL.path
        return registryLock.withLock {
            if let state = states[key] {
                return state
            }
            let state = OfflineRegionStoreRootState()
            states[key] = state
            return state
        }
    }
}

public final class OfflineRegionStore: @unchecked Sendable {
    static let maxInstalledPackCount = 256
    static let maxCurrentPackBytes = 4 * 1024
    static let maxOfflinePackIndexBytes = 1024 * 1024
    static let maxOfflineManifestSnapshotBytes = 16 * 1024 * 1024

    private let root: URL
    private let fm = FileManager.default
    private let rootState: OfflineRegionStoreRootState
    private var validatedPackIndexes: [String: OfflinePackIndex] = [:]
    private var lastPackQuarantinesSnapshot: [OfflinePackQuarantine] = []

    public init(root: URL) throws {
        self.root = root
        self.rootState = OfflineRegionStoreRootStates.state(for: root)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try excludeFromBackup(root)
        MakingTracksLog.install.info("store init completed")
    }

    public func performDeferredMaintenance() throws {
        MakingTracksLog.gc.info("deferred maintenance started")
        do {
            try withLock {
                try recoverInterruptedInstallsLocked()
                try garbageCollectObjects()
            }
            try OfflineBackgroundCompletedDownloadStore.shared.performMaintenance()
            MakingTracksLog.gc.info("deferred maintenance finished")
        } catch {
            MakingTracksLog.gc.error("deferred maintenance failed reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            throw error
        }
    }

    public static func documentsStore() throws -> OfflineRegionStore {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        MakingTracksLog.install.debug("store init requested kind=documents")
        return try OfflineRegionStore(root: documents.appendingPathComponent("MakingTracks/OfflineRegions", isDirectory: true))
    }

    public func install(publish: PinnedPublish, tiles: [TileCoordinate: Data], basemap: Data?) throws {
        try withLock {
            try installLocked(publish: publish, tiles: tiles, basemap: basemap)
        }
    }

    func beginDownload(publish: PinnedPublish) throws {
        try withLock {
            try validatePublish(publish)
            try removeSupersededInProgressDownloads(region: publish.region, keeping: publish.publishVersion)
            let inProgress = inProgressURL(region: publish.region, publishVersion: publish.publishVersion)
            try fm.createDirectory(at: inProgress, withIntermediateDirectories: true)
            try JSONEncoder().encode(publish)
                .write(to: inProgress.appendingPathComponent("manifest-snapshot.json"), options: .atomic)
            try JSONEncoder().encode(packIndex(for: publish))
                .write(to: inProgress.appendingPathComponent("pack-index.json"), options: .atomic)
            let pausedURL = pausedDownloadURL(region: publish.region, publishVersion: publish.publishVersion)
            if fm.fileExists(atPath: pausedURL.path) {
                try fm.removeItem(at: pausedURL)
            }
            MakingTracksLog.downloads.info("download marker written region=\(publish.region, privacy: .private(mask: .hash)) version=\(publish.publishVersion, privacy: .public) objects=\(publish.manifest.tiles.count + 1, privacy: .public)")
            try garbageCollectObjects()
        }
    }

    func acquireDownloadLease(region: String) throws {
        try withLock {
            guard isValidRegion(region) else { throw TileError.invalidOfflinePack }
            guard !rootState.activeDownloadRegions.contains(region) else { throw TileError.downloadAlreadyInProgress }
            rootState.activeDownloadRegions.insert(region)
        }
    }

    func releaseDownloadLease(region: String) {
        _ = withLock {
            rootState.activeDownloadRegions.remove(region)
        }
    }

#if DEBUG
    func withRegisteredLiveTemporaryObjectForTesting(_ url: URL, _ body: () throws -> Void) rethrows {
        registerLiveTemporaryObject(url)
        defer { unregisterLiveTemporaryObject(url) }
        try body()
    }
#endif

    func stageDownloadedTileObject(_ fileURL: URL, sha256: String, bytes: Int) throws {
        try withLock {
            guard bytes <= TileCodec.maxCompressedBytes else { throw TileError.byteCountMismatch }
            guard try fileByteCount(fileURL) == bytes else { throw TileError.byteCountMismatch }
            let data = try Data(contentsOf: fileURL)
            try writeVerifiedTileObject(data, sha256: sha256, bytes: bytes)
            MakingTracksLog.downloads.debug("object verified kind=tile sha=\(sha256, privacy: .private(mask: .hash)) bytes=\(bytes, privacy: .public)")
        }
    }

    func stageDownloadedBasemapObject(_ fileURL: URL, sha256: String, bytes: Int) throws {
        let prepared = basemapObjectTemporaryURL()
        registerLiveTemporaryObject(prepared)
        MakingTracksLog.downloads.debug("live temporary registered kind=basemap")
        defer {
            unregisterLiveTemporaryObject(prepared)
            MakingTracksLog.downloads.debug("live temporary unregistered kind=basemap")
            if fm.fileExists(atPath: prepared.path) {
                try? fm.removeItem(at: prepared)
            }
        }
        try prepareVerifiedBasemapObject(from: fileURL, to: prepared, sha256: sha256, bytes: bytes)
        try withLock {
            do {
                try movePreparedBasemapObject(prepared, sha256: sha256, bytes: bytes)
                MakingTracksLog.downloads.debug("object verified kind=basemap sha=\(sha256, privacy: .private(mask: .hash)) bytes=\(bytes, privacy: .public)")
            } catch {
                throw error
            }
        }
    }

    func discardDownload(region: String, publishVersion: String) throws {
        try withLock {
            OfflineBackgroundCompletedDownloadStore.shared.removeAll(region: region)
            try removeInProgressDownload(region: region, publishVersion: publishVersion)
            try garbageCollectObjects()
            MakingTracksLog.downloads.info("download discarded region=\(region, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public)")
        }
    }

    func pendingDownload(region: String, includePaused: Bool = false) throws -> PinnedPublish? {
        try withLock {
            try pendingDownloadLocked(region: region, includePaused: includePaused)
        }
    }

    func hasPausedPendingDownload(region: String) throws -> Bool {
        try withLock {
            try pausedPendingDownloadLocked(region: region) != nil
        }
    }

    public func pausedPendingDownloadRegions() throws -> [String] {
        try withLock {
            let inProgressRoot = root.appendingPathComponent("in-progress", isDirectory: true)
            guard let regionURLs = try? fm.contentsOfDirectory(at: inProgressRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
            return try regionURLs.compactMap { regionURL -> String? in
                let values = try regionURL.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { return nil }
                let region = regionURL.lastPathComponent
                guard isValidRegion(region), (try? pausedPendingDownloadLocked(region: region)) != nil else { return nil }
                return region
            }.sorted()
        }
    }

    func markDownloadPaused(region: String, publishVersion: String) throws {
        try withLock {
            guard isValidRegion(region), isValidPublishVersion(publishVersion) else { throw TileError.invalidOfflinePack }
            let inProgress = inProgressURL(region: region, publishVersion: publishVersion)
            guard fm.fileExists(atPath: inProgress.path) else { return }
            try Data("paused\n".utf8).write(to: pausedDownloadURL(region: region, publishVersion: publishVersion), options: .atomic)
            MakingTracksLog.downloads.info("download pause marker written region=\(region, privacy: .private(mask: .hash)) version=\(publishVersion, privacy: .public)")
        }
    }

    private func installLocked(publish: PinnedPublish, tiles: [TileCoordinate: Data], basemap: Data?) throws {
        try validatePublish(publish)
        MakingTracksLog.install.info("install started region=\(publish.region, privacy: .private(mask: .hash)) version=\(publish.publishVersion, privacy: .public) objects=\(publish.manifest.tiles.count + 1, privacy: .public)")
        let requiredCoordinates = Set(publish.manifest.tiles.map { TileCoordinate(z: publish.manifest.tileZ, x: $0.x, y: $0.y) })
        guard Set(tiles.keys).isSubset(of: requiredCoordinates) else { throw TileError.invalidOfflinePack }
        if let basemap {
            guard basemap.count == publish.manifest.basemap.bytes,
                  sha256(basemap) == publish.manifest.basemap.sha256
            else { throw TileError.checksumMismatch }
        } else {
            try verifyExistingBasemapObject(sha256: publish.manifest.basemap.sha256, bytes: publish.manifest.basemap.bytes)
        }
        for manifestTile in publish.manifest.tiles {
            let coordinate = TileCoordinate(z: publish.manifest.tileZ, x: manifestTile.x, y: manifestTile.y)
            if let data = tiles[coordinate] {
                _ = try TileCodec.decode(gzipped: data, expectedSHA256: manifestTile.sha256, expectedBytes: manifestTile.bytes)
            } else {
                try verifyExistingTileObject(sha256: manifestTile.sha256, bytes: manifestTile.bytes)
            }
        }
        MakingTracksLog.install.info("install prerequisites verified region=\(publish.region, privacy: .private(mask: .hash)) version=\(publish.publishVersion, privacy: .public) tileObjects=\(publish.manifest.tiles.count, privacy: .public) basemapObjects=1")

        let temp = root.appendingPathComponent("tmp/\(UUID().uuidString)", isDirectory: true)
        let backup = root.appendingPathComponent("tmp/\(UUID().uuidString)-backup", isDirectory: true)
        let final = packURL(region: publish.region, publishVersion: publish.publishVersion)
        do {
            try fm.createDirectory(at: tileObjectsURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: basemapObjectsURL, withIntermediateDirectories: true)
            for manifestTile in publish.manifest.tiles {
                let coordinate = TileCoordinate(z: publish.manifest.tileZ, x: manifestTile.x, y: manifestTile.y)
                if let data = tiles[coordinate] {
                    try writeVerifiedTileObject(data, sha256: manifestTile.sha256, bytes: manifestTile.bytes)
                }
            }
            if let basemap {
                try writeVerifiedBasemapObject(basemap, sha256: publish.manifest.basemap.sha256, bytes: publish.manifest.basemap.bytes)
            }

            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            try JSONEncoder().encode(publish).write(to: temp.appendingPathComponent("manifest-snapshot.json"), options: .atomic)
            try JSONEncoder().encode(packIndex(for: publish)).write(to: temp.appendingPathComponent("pack-index.json"), options: .atomic)
            try excludeFromBackup(temp)
            try fm.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: final.path) {
                try fm.moveItem(at: final, to: backup)
            }
            validatedPackIndexes.removeValue(forKey: packIndexCacheKey(region: publish.region, publishVersion: publish.publishVersion))
            try fm.moveItem(at: temp, to: final)
            try excludeFromBackup(final)
            let regionDirectory = regionURL(region: publish.region)
            try fm.createDirectory(at: regionDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(OfflineCurrentPack(publishVersion: publish.publishVersion))
                .write(to: regionDirectory.appendingPathComponent("current-pack.json"), options: .atomic)
            MakingTracksLog.install.info("install promoted region=\(publish.region, privacy: .private(mask: .hash)) version=\(publish.publishVersion, privacy: .public)")
            try removeInProgressDownload(region: publish.region, publishVersion: publish.publishVersion)
            if fm.fileExists(atPath: backup.path) {
                try fm.removeItem(at: backup)
            }
            try? garbageCollectObjects()
            MakingTracksLog.install.info("install finished region=\(publish.region, privacy: .private(mask: .hash)) version=\(publish.publishVersion, privacy: .public)")
        } catch {
            MakingTracksLog.install.error("install failed region=\(publish.region, privacy: .private(mask: .hash)) version=\(publish.publishVersion, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            if fm.fileExists(atPath: temp.path) {
                try? fm.removeItem(at: temp)
            }
            if fm.fileExists(atPath: final.path), fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: final)
            }
            if fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: final)
                MakingTracksLog.install.info("install recovered previous region=\(publish.region, privacy: .private(mask: .hash)) version=\(publish.publishVersion, privacy: .public)")
            }
            try? removeInProgressDownload(region: publish.region, publishVersion: publish.publishVersion)
            try? garbageCollectObjects()
            throw error
        }
    }

    public func installedPublish(region: String) throws -> PinnedPublish? {
        try withLock {
            try installedPublishLocked(region: region)
        }
    }

    public func installedPublishes(intersecting viewport: BBox) throws -> [PinnedPublish] {
        try withLock {
            do {
                return try installedPublishesLocked(intersecting: viewport)
            } catch {
                lastPackQuarantinesSnapshot = []
                throw error
            }
        }
    }

    public func installedTileResolution(intersecting viewport: BBox) throws -> OfflinePackResolution {
        try withLock {
            do {
                let resolution = try installedTileResolutionLocked(intersecting: viewport)
                lastPackQuarantinesSnapshot = resolution.quarantinedPacks
                return resolution
            } catch {
                lastPackQuarantinesSnapshot = []
                throw error
            }
        }
    }

    public func installedTiles(intersecting viewport: BBox) throws -> [InstalledPackTile] {
        try withLock {
            do {
                let resolution = try installedTileResolutionLocked(intersecting: viewport)
                lastPackQuarantinesSnapshot = resolution.quarantinedPacks
                return resolution.tiles
            } catch {
                lastPackQuarantinesSnapshot = []
                throw error
            }
        }
    }

    public func lastPackQuarantines() -> [OfflinePackQuarantine] {
        withLock {
            lastPackQuarantinesSnapshot
        }
    }

    public func installedPackStorageSummary() throws -> OfflinePackStorageSummary {
        let snapshot = try withLock {
            try installedPackStorageSnapshotLocked()
        }
        return try installedPackStorageSummary(from: snapshot)
    }

    public func pendingDownloadRegions() throws -> [String] {
        try withLock {
            let inProgressRoot = root.appendingPathComponent("in-progress", isDirectory: true)
            guard let regionURLs = try? fm.contentsOfDirectory(at: inProgressRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
            return try regionURLs.compactMap { regionURL -> String? in
                let values = try regionURL.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { return nil }
                let region = regionURL.lastPathComponent
                guard isValidRegion(region), (try? pendingDownloadLocked(region: region)) != nil else { return nil }
                return region
            }.sorted()
        }
    }

    private func installedPublishesLocked(intersecting viewport: BBox) throws -> [PinnedPublish] {
        let resolution = try installedTileResolutionLocked(intersecting: viewport)
        lastPackQuarantinesSnapshot = resolution.quarantinedPacks
        let regions = Set(resolution.tiles.map(\.region))
        return try regions.sorted().compactMap { try installedPublishLocked(region: $0) }
    }

    private func installedTileResolutionLocked(intersecting viewport: BBox) throws -> OfflinePackResolution {
        let directories = try installedRegionDirectoriesLocked()
        let viewportCoordinates = Set(TileCoverage.tiles(for: viewport))
        var tiles: [InstalledPackTile] = []
        var quarantines: [OfflinePackQuarantine] = []
        for child in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let region = child.lastPathComponent
            guard isValidRegion(region) else { continue }
            let current: OfflineCurrentPack?
            do {
                current = try installedCurrentPackLocked(region: region)
            } catch {
                let quarantine = try corruptCurrentPackQuarantineLocked(region: region, viewportCoordinates: viewportCoordinates)
                quarantines.append(quarantine)
                let affected = quarantine.coordinates.count
                MakingTracksLog.resolution.error("quarantine raised region=\(region, privacy: .private(mask: .hash)) version=unknown affected=\(affected, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
                continue
            }
            guard let current else { continue }
            let packIndex: OfflinePackIndex
            do {
                packIndex = try offlinePackIndexLocked(region: region, publishVersion: current.publishVersion)
            } catch {
                let quarantine = corruptPackIndexQuarantineLocked(
                    region: region,
                    publishVersion: current.publishVersion,
                    viewportCoordinates: viewportCoordinates
                )
                quarantines.append(quarantine)
                let affected = quarantine.coordinates.count
                MakingTracksLog.resolution.error("quarantine raised region=\(region, privacy: .private(mask: .hash)) version=\(current.publishVersion, privacy: .public) affected=\(affected, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
                continue
            }
            let basemap = InstalledPackBasemap(
                region: region,
                publishVersion: current.publishVersion,
                sha256: packIndex.basemapSHA,
                bytes: packIndex.basemapBytes
            )
            for coordinate in viewportCoordinates.sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }) {
                guard let entry = packIndex.tiles["\(coordinate.x)/\(coordinate.y)"] else { continue }
                tiles.append(InstalledPackTile(
                    region: region,
                    publishVersion: current.publishVersion,
                    coordinate: coordinate,
                    tile: ManifestTile(x: coordinate.x, y: coordinate.y, sha256: entry.sha256, bytes: entry.bytes),
                    attribution: packIndex.attribution,
                    attributionSources: packIndex.attributionSources,
                    packTileCount: packIndex.tiles.count,
                    basemap: basemap
                ))
            }
        }
        MakingTracksLog.resolution.debug("offline resolved packs=\(directories.count, privacy: .public) tiles=\(tiles.count, privacy: .public) quarantines=\(quarantines.count, privacy: .public)")
        return OfflinePackResolution(tiles: tiles, quarantinedPacks: quarantines)
    }

    private func installedPackStorageSummary(from snapshot: OfflinePackStorageSnapshot) throws -> OfflinePackStorageSummary {
        var packs: [InstalledOfflinePackStorage] = []
        var failedRegions = Set(snapshot.failedRegions)
        var tileBytesBySHA: [String: Int] = [:]
        var basemapBytesBySHA: [String: Int] = [:]
        for pack in snapshot.packs {
            do {
                var tileBytes = 0
                for tile in pack.tiles {
                    let bytes = try verifiedObjectSize(
                        url: tileObjectURL(sha256: tile.sha256),
                        expectedBytes: tile.bytes
                    )
                    tileBytes = try checkedAdd(tileBytes, bytes)
                    tileBytesBySHA[tile.sha256] = bytes
                }
                let basemapBytes = try verifiedObjectSize(
                    url: basemapObjectURL(sha256: pack.basemap.sha256),
                    expectedBytes: pack.basemap.bytes
                )
                basemapBytesBySHA[pack.basemap.sha256] = basemapBytes
                packs.append(InstalledOfflinePackStorage(
                    region: pack.region,
                    publishVersion: pack.publishVersion,
                    tileCount: pack.tiles.count,
                    tileBytes: tileBytes,
                    basemapBytes: basemapBytes,
                    referencedBytes: try checkedAdd(tileBytes, basemapBytes)
                ))
            } catch {
                failedRegions.insert(pack.region)
            }
        }
        let totalTileBytes = try checkedSum(tileBytesBySHA.values)
        let totalBasemapBytes = try checkedSum(basemapBytesBySHA.values)
        return OfflinePackStorageSummary(
            packs: packs.sorted { $0.region < $1.region },
            failedRegions: failedRegions.sorted(),
            totalBytes: try checkedAdd(totalTileBytes, totalBasemapBytes)
        )
    }

    private func installedPackStorageSnapshotLocked() throws -> OfflinePackStorageSnapshot {
        var packs: [OfflinePackStoragePackSnapshot] = []
        var failedRegions: [String] = []
        for child in try installedRegionDirectoriesLocked().sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let region = child.lastPathComponent
            guard isValidRegion(region) else { continue }
            let current: OfflineCurrentPack?
            do {
                current = try installedCurrentPackLocked(region: region)
            } catch {
                failedRegions.append(region)
                continue
            }
            guard let current else { continue }
            let packIndex: OfflinePackIndex
            do {
                packIndex = try offlinePackIndexLocked(region: region, publishVersion: current.publishVersion)
            } catch {
                failedRegions.append(region)
                continue
            }
            packs.append(OfflinePackStoragePackSnapshot(
                region: region,
                publishVersion: current.publishVersion,
                tiles: packIndex.tiles.values.map {
                    OfflinePackStorageObjectSnapshot(sha256: $0.sha256, bytes: $0.bytes)
                },
                basemap: OfflinePackStorageObjectSnapshot(
                    sha256: packIndex.basemapSHA,
                    bytes: packIndex.basemapBytes
                )
            ))
        }
        return OfflinePackStorageSnapshot(packs: packs, failedRegions: failedRegions)
    }

    private func installedRegionDirectoriesLocked() throws -> [URL] {
        let regionsRoot = root.appendingPathComponent("regions", isDirectory: true)
        guard fm.fileExists(atPath: regionsRoot.path) else { return [] }
        let children = try fm.contentsOfDirectory(at: regionsRoot, includingPropertiesForKeys: [.isDirectoryKey])
        let directories = try children.compactMap { child -> URL? in
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true ? child : nil
        }
        guard directories.count <= Self.maxInstalledPackCount else { throw TileError.invalidOfflinePack }
        return directories
    }

    private func installedPublishLocked(region: String) throws -> PinnedPublish? {
        guard isValidRegion(region) else { throw TileError.invalidOfflinePack }
        guard let current = try installedCurrentPackLocked(region: region) else { return nil }
        return try publishSnapshotLocked(region: region, publishVersion: current.publishVersion)
    }

    private func publishSnapshotLocked(region: String, publishVersion: String) throws -> PinnedPublish {
        let manifestURL = packURL(region: region, publishVersion: publishVersion).appendingPathComponent("manifest-snapshot.json")
        let publish = try JSONDecoder().decode(
            PinnedPublish.self,
            from: try boundedData(contentsOf: manifestURL, maxBytes: Self.maxOfflineManifestSnapshotBytes)
        )
        let strictManifest = try Manifest.decode(try JSONEncoder().encode(publish.manifest))
        guard publish.region == region,
              publish.publishVersion == publishVersion,
              strictManifest.region == region,
              strictManifest.publishVersion == publishVersion
        else { throw TileError.invalidOfflinePack }
        return PinnedPublish(region: publish.region, publishVersion: publish.publishVersion, manifest: strictManifest)
    }

    private func corruptCurrentPackQuarantineLocked(
        region: String,
        viewportCoordinates: Set<TileCoordinate>
    ) throws -> OfflinePackQuarantine {
        let packsRoot = root.appendingPathComponent("packs").appendingPathComponent(region, isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(at: packsRoot, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return OfflinePackQuarantine(region: region, publishVersion: nil, coordinates: [])
        }
        let directories = try children.compactMap { child -> URL? in
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true ? child : nil
        }
        guard directories.count <= Self.maxInstalledPackCount else { throw TileError.invalidOfflinePack }
        var coordinates = Set<TileCoordinate>()
        for child in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let publishVersion = child.lastPathComponent
            guard isValidPublishVersion(publishVersion) else { continue }
            coordinates.formUnion(packCoverageFromManifestSnapshotLocked(
                region: region,
                publishVersion: publishVersion,
                viewportCoordinates: viewportCoordinates
            ))
        }
        return OfflinePackQuarantine(region: region, publishVersion: nil, coordinates: coordinates)
    }

    private func corruptPackIndexQuarantineLocked(
        region: String,
        publishVersion: String,
        viewportCoordinates: Set<TileCoordinate>
    ) -> OfflinePackQuarantine {
        OfflinePackQuarantine(
            region: region,
            publishVersion: publishVersion,
            coordinates: packCoverageFromManifestSnapshotLocked(
                region: region,
                publishVersion: publishVersion,
                viewportCoordinates: viewportCoordinates
            )
        )
    }

    private func packCoverageFromManifestSnapshotLocked(
        region: String,
        publishVersion: String,
        viewportCoordinates: Set<TileCoordinate>
    ) -> Set<TileCoordinate> {
        guard let publish = try? publishSnapshotLocked(region: region, publishVersion: publishVersion) else {
            return []
        }
        return Set(publish.manifest.tiles.map {
            TileCoordinate(z: publish.manifest.tileZ, x: $0.x, y: $0.y)
        }).intersection(viewportCoordinates)
    }

    private func installedCurrentPackLocked(region: String) throws -> OfflineCurrentPack? {
        let currentURL = regionURL(region: region).appendingPathComponent("current-pack.json")
        guard fm.fileExists(atPath: currentURL.path) else { return nil }
        let current = try JSONDecoder().decode(
            OfflineCurrentPack.self,
            from: try boundedData(contentsOf: currentURL, maxBytes: Self.maxCurrentPackBytes)
        )
        guard isValidPublishVersion(current.publishVersion) else { throw TileError.invalidOfflinePack }
        return current
    }

    private func pendingDownloadLocked(region: String, includePaused: Bool = false) throws -> PinnedPublish? {
        guard isValidRegion(region) else { throw TileError.invalidOfflinePack }
        let regionRoot = root.appendingPathComponent("in-progress").appendingPathComponent(region, isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(at: regionRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        guard children.count <= Self.maxInstalledPackCount else { throw TileError.invalidOfflinePack }
        for child in children.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let publishVersion = child.lastPathComponent
            guard isValidPublishVersion(publishVersion) else { continue }
            let manifestURL = child.appendingPathComponent("manifest-snapshot.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            do {
                guard includePaused || !isDownloadPaused(child) else { continue }
                let publish = try JSONDecoder().decode(
                    PinnedPublish.self,
                    from: try boundedData(contentsOf: manifestURL, maxBytes: Self.maxOfflineManifestSnapshotBytes)
                )
                let strictManifest = try Manifest.decode(try JSONEncoder().encode(publish.manifest))
                guard publish.region == region,
                      publish.publishVersion == publishVersion,
                      strictManifest.region == region,
                      strictManifest.publishVersion == publishVersion
                else { continue }
                return PinnedPublish(region: publish.region, publishVersion: publish.publishVersion, manifest: strictManifest)
            } catch {
                continue
            }
        }
        return nil
    }

    private func pausedPendingDownloadLocked(region: String) throws -> PinnedPublish? {
        guard isValidRegion(region) else { throw TileError.invalidOfflinePack }
        let regionRoot = root.appendingPathComponent("in-progress").appendingPathComponent(region, isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(at: regionRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        guard children.count <= Self.maxInstalledPackCount else { throw TileError.invalidOfflinePack }
        for child in children.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true, isDownloadPaused(child) else { continue }
            let publishVersion = child.lastPathComponent
            guard isValidPublishVersion(publishVersion) else { continue }
            let manifestURL = child.appendingPathComponent("manifest-snapshot.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let publish = try JSONDecoder().decode(
                    PinnedPublish.self,
                    from: try boundedData(contentsOf: manifestURL, maxBytes: Self.maxOfflineManifestSnapshotBytes)
                )
                let strictManifest = try Manifest.decode(try JSONEncoder().encode(publish.manifest))
                guard publish.region == region,
                      publish.publishVersion == publishVersion,
                      strictManifest.region == region,
                      strictManifest.publishVersion == publishVersion
                else { continue }
                return PinnedPublish(region: publish.region, publishVersion: publish.publishVersion, manifest: strictManifest)
            } catch {
                continue
            }
        }
        return nil
    }

    private func offlinePackIndexLocked(region: String, publishVersion: String) throws -> OfflinePackIndex {
        let cacheKey = packIndexCacheKey(region: region, publishVersion: publishVersion)
        if let cached = validatedPackIndexes[cacheKey] {
            return cached
        }
        let indexURL = packURL(region: region, publishVersion: publishVersion).appendingPathComponent("pack-index.json")
        let index = try JSONDecoder().decode(
            OfflinePackIndex.self,
            from: try boundedData(contentsOf: indexURL, maxBytes: Self.maxOfflinePackIndexBytes)
        )
        guard index.tileSHAs.count <= 1_048_576,
              index.tiles.count <= 1_048_576
        else { throw TileError.invalidOfflinePack }
        let resolvedIndex = try offlinePackIndexFromManifestSnapshotLocked(
            region: region,
            publishVersion: publishVersion,
            storedIndex: index
        )
        guard resolvedIndex.region == region,
              resolvedIndex.publishVersion == publishVersion,
              resolvedIndex.basemapSHA.matches("^[0-9a-f]{64}$"),
              resolvedIndex.basemapBytes > 0
        else { throw TileError.invalidOfflinePack }
        for (key, tile) in resolvedIndex.tiles {
            guard key.matches("^[0-9]{1,4}/[0-9]{1,4}$"),
                  tile.sha256.matches("^[0-9a-f]{64}$"),
                  (1...TileCodec.maxCompressedBytes).contains(tile.bytes)
            else { throw TileError.invalidOfflinePack }
        }
        guard resolvedIndex.attributionSources.count <= 32,
              resolvedIndex.attributionSources.allSatisfy({ (1...32).contains($0.scalarCount) && $0.isSafeText })
        else { throw TileError.invalidOfflinePack }
        for item in resolvedIndex.attribution {
            try item.validate()
        }
        validatedPackIndexes[cacheKey] = resolvedIndex
        return resolvedIndex
    }

    private func offlinePackIndexFromManifestSnapshotLocked(
        region: String,
        publishVersion: String,
        storedIndex: OfflinePackIndex
    ) throws -> OfflinePackIndex {
        let publish = try publishSnapshotLocked(region: region, publishVersion: publishVersion)
        let strictManifest = publish.manifest
        guard publish.region == region,
              publish.publishVersion == publishVersion,
              strictManifest.region == region,
              strictManifest.publishVersion == publishVersion,
              strictManifest.basemap.sha256 == storedIndex.basemapSHA
        else { throw TileError.invalidOfflinePack }
        let tiles = Dictionary(uniqueKeysWithValues: strictManifest.tiles.map {
            (
                "\($0.x)/\($0.y)",
                OfflinePackTileIndexEntry(sha256: $0.sha256, bytes: $0.bytes)
            )
        })
        guard tiles.mapValues(\.sha256) == storedIndex.tileSHAs else { throw TileError.invalidOfflinePack }
        if storedIndex.hasTileMetadata {
            guard storedIndex.tiles == tiles,
                  storedIndex.basemapBytes == strictManifest.basemap.bytes,
                  storedIndex.attribution == strictManifest.attribution,
                  storedIndex.attributionSources == strictManifest.attribution.map(\.source)
            else { throw TileError.invalidOfflinePack }
        }
        return OfflinePackIndex(
            region: region,
            publishVersion: publishVersion,
            tileSHAs: storedIndex.tileSHAs,
            tiles: tiles,
            basemapSHA: storedIndex.basemapSHA,
            basemapBytes: strictManifest.basemap.bytes,
            attribution: strictManifest.attribution,
            attributionSources: strictManifest.attribution.map(\.source)
        )
    }

    public func updatePlan(for target: PinnedPublish) throws -> OfflineRegionUpdatePlan {
        try withLock {
            try updatePlanLocked(for: target)
        }
    }

    private func updatePlanLocked(for target: PinnedPublish) throws -> OfflineRegionUpdatePlan {
        guard target.region == target.manifest.region,
              target.publishVersion == target.manifest.publishVersion,
              isValidRegion(target.region),
              isValidPublishVersion(target.publishVersion)
        else { throw TileError.invalidOfflinePack }
        var reused = 0
        var fetches: [OfflineTileFetch] = []
        for tile in target.manifest.tiles {
            if (try? verifyExistingTileObject(sha256: tile.sha256, bytes: tile.bytes)) != nil {
                reused += 1
                MakingTracksLog.downloads.debug("object skipped region=\(target.region, privacy: .private(mask: .hash)) version=\(target.publishVersion, privacy: .public) kind=tile sha=\(tile.sha256, privacy: .private(mask: .hash)) bytes=\(tile.bytes, privacy: .public)")
            } else {
                fetches.append(OfflineTileFetch(coordinate: TileCoordinate(z: target.manifest.tileZ, x: tile.x, y: tile.y), sha256: tile.sha256, bytes: tile.bytes))
            }
        }
        let basemapNeedsFetch = (try? verifyExistingBasemapObject(sha256: target.manifest.basemap.sha256, bytes: target.manifest.basemap.bytes)) == nil
        if !basemapNeedsFetch {
            MakingTracksLog.downloads.debug("object skipped region=\(target.region, privacy: .private(mask: .hash)) version=\(target.publishVersion, privacy: .public) kind=basemap sha=\(target.manifest.basemap.sha256, privacy: .private(mask: .hash)) bytes=\(target.manifest.basemap.bytes, privacy: .public)")
        }
        let tileBytes = fetches.reduce(0) { $0 + $1.bytes }
        return OfflineRegionUpdatePlan(
            tilesToFetch: fetches,
            reusedTileCount: reused,
            basemapNeedsFetch: basemapNeedsFetch,
            bytesToFetch: tileBytes + (basemapNeedsFetch ? target.manifest.basemap.bytes : 0)
        )
    }

    public func tile(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String) -> Data? {
        withLock {
            tileLocked(region: region, publishVersion: publishVersion, coordinate: coordinate, sha256: sha256)
        }
    }

    private func tileLocked(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String) -> Data? {
        guard isValidRegion(region),
              isValidPublishVersion(publishVersion),
              coordinate.z == 10,
              (0...1023).contains(coordinate.x),
              (0...1023).contains(coordinate.y),
              sha256.matches("^[0-9a-f]{64}$")
        else { return nil }
        guard fm.fileExists(atPath: packURL(region: region, publishVersion: publishVersion).path) else { return nil }
        return try? Data(contentsOf: tileObjectURL(sha256: sha256))
    }

    public func basemapURL(region: String, publishVersion: String, sha256: String, bytes: Int) -> URL? {
        withLock {
            basemapURLLocked(region: region, publishVersion: publishVersion, sha256: sha256, bytes: bytes)
        }
    }

    private func basemapURLLocked(region: String, publishVersion: String, sha256: String, bytes: Int) -> URL? {
        guard isValidRegion(region),
              isValidPublishVersion(publishVersion),
              sha256.matches("^[0-9a-f]{64}$"),
              bytes > 0
        else { return nil }
        guard fm.fileExists(atPath: packURL(region: region, publishVersion: publishVersion).path),
              (try? verifyExistingBasemapObject(sha256: sha256, bytes: bytes)) != nil
        else { return nil }
        return basemapObjectURL(sha256: sha256)
    }

    public func delete(region: String) throws {
        try withLock {
            try deleteLocked(region: region)
        }
    }

    public func discardInProgressDownloads(region: String) throws {
        try withLock {
            guard isValidRegion(region) else { throw TileError.invalidOfflinePack }
            guard !rootState.activeDownloadRegions.contains(region) else {
                MakingTracksLog.downloads.info("in-progress discard skipped region=\(region, privacy: .private(mask: .hash)) reason=active-download")
                throw TileError.downloadAlreadyInProgress
            }
            MakingTracksLog.downloads.info("in-progress discard started region=\(region, privacy: .private(mask: .hash))")
            let inProgressRegion = root.appendingPathComponent("in-progress").appendingPathComponent(region, isDirectory: true)
            if fm.fileExists(atPath: inProgressRegion.path) {
                try fm.removeItem(at: inProgressRegion)
            }
            OfflineBackgroundCompletedDownloadStore.shared.removeAll(region: region)
            try garbageCollectObjects()
            MakingTracksLog.downloads.info("in-progress discard finished region=\(region, privacy: .private(mask: .hash))")
        }
    }

    private func deleteLocked(region: String) throws {
        guard isValidRegion(region) else { throw TileError.invalidOfflinePack }
        guard !rootState.activeDownloadRegions.contains(region) else {
            MakingTracksLog.install.info("delete skipped region=\(region, privacy: .private(mask: .hash)) reason=active-download")
            throw TileError.downloadAlreadyInProgress
        }
        MakingTracksLog.install.info("delete started region=\(region, privacy: .private(mask: .hash))")
        let packs = root.appendingPathComponent("packs").appendingPathComponent(region)
        if fm.fileExists(atPath: packs.path) {
            try fm.removeItem(at: packs)
        }
        let regionDirectory = regionURL(region: region)
        if fm.fileExists(atPath: regionDirectory.path) {
            try fm.removeItem(at: regionDirectory)
        }
        let inProgressRegion = root.appendingPathComponent("in-progress").appendingPathComponent(region, isDirectory: true)
        if fm.fileExists(atPath: inProgressRegion.path) {
            try fm.removeItem(at: inProgressRegion)
        }
        OfflineBackgroundCompletedDownloadStore.shared.removeAll(region: region)
        validatedPackIndexes = validatedPackIndexes.filter { key, _ in
            !key.hasPrefix("\(region)/")
        }
        try garbageCollectObjects()
        MakingTracksLog.install.info("delete finished region=\(region, privacy: .private(mask: .hash))")
    }

    private func removeSupersededInProgressDownloads(region: String, keeping publishVersion: String) throws {
        let inProgressRegion = root.appendingPathComponent("in-progress").appendingPathComponent(region, isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(at: inProgressRegion, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for child in children where child.lastPathComponent != publishVersion {
            try fm.removeItem(at: child)
        }
    }

    func packURL(region: String, publishVersion: String) -> URL {
        root.appendingPathComponent("packs").appendingPathComponent(region).appendingPathComponent(publishVersion, isDirectory: true)
    }

    func regionURL(region: String) -> URL {
        root.appendingPathComponent("regions").appendingPathComponent(region, isDirectory: true)
    }

    private func inProgressURL(region: String, publishVersion: String) -> URL {
        root.appendingPathComponent("in-progress").appendingPathComponent(region).appendingPathComponent(publishVersion, isDirectory: true)
    }

    private func pausedDownloadURL(region: String, publishVersion: String) -> URL {
        inProgressURL(region: region, publishVersion: publishVersion).appendingPathComponent("paused")
    }

    private func isDownloadPaused(_ inProgressURL: URL) -> Bool {
        fm.fileExists(atPath: inProgressURL.appendingPathComponent("paused").path)
    }

    private var tileObjectsURL: URL {
        root.appendingPathComponent("objects/tiles", isDirectory: true)
    }

    private var basemapObjectsURL: URL {
        root.appendingPathComponent("objects/basemaps", isDirectory: true)
    }

    private func tileObjectURL(sha256: String) -> URL {
        tileObjectsURL.appendingPathComponent("\(sha256).json.gz")
    }

    private func basemapObjectURL(sha256: String) -> URL {
        basemapObjectsURL.appendingPathComponent("\(sha256).pmtiles")
    }

    private func writeVerifiedTileObject(_ data: Data, sha256: String, bytes: Int) throws {
        let url = tileObjectURL(sha256: sha256)
        if (try? verifyExistingTileObject(sha256: sha256, bytes: bytes)) != nil {
            MakingTracksLog.downloads.debug("object skipped kind=tile sha=\(sha256, privacy: .private(mask: .hash)) bytes=\(bytes, privacy: .public)")
            return
        }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).json.gz.tmp")
        do {
            if fm.fileExists(atPath: temp.path) {
                try fm.removeItem(at: temp)
            }
            try data.write(to: temp, options: .atomic)
            try verifyTileObject(temp, sha256: sha256, bytes: bytes)
            try fm.moveItem(at: temp, to: url)
            try verifyExistingTileObject(sha256: sha256, bytes: bytes)
            MakingTracksLog.downloads.debug("object written kind=tile sha=\(sha256, privacy: .private(mask: .hash)) bytes=\(bytes, privacy: .public)")
        } catch {
            if fm.fileExists(atPath: temp.path) {
                try? fm.removeItem(at: temp)
            }
            throw error
        }
    }

    private func writeVerifiedBasemapObject(_ data: Data, sha256: String, bytes: Int) throws {
        let url = basemapObjectURL(sha256: sha256)
        if (try? verifyExistingBasemapObject(sha256: sha256, bytes: bytes)) != nil {
            MakingTracksLog.downloads.debug("object skipped kind=basemap sha=\(sha256, privacy: .private(mask: .hash)) bytes=\(bytes, privacy: .public)")
            return
        }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try verifyExistingBasemapObject(sha256: sha256, bytes: bytes)
        MakingTracksLog.downloads.debug("object written kind=basemap sha=\(sha256, privacy: .private(mask: .hash)) bytes=\(bytes, privacy: .public)")
    }

    private func writeVerifiedBasemapObject(from fileURL: URL, sha256: String, bytes: Int) throws {
        if (try? verifyExistingBasemapObject(sha256: sha256, bytes: bytes)) != nil {
            MakingTracksLog.downloads.debug("object skipped kind=basemap sha=\(sha256, privacy: .private(mask: .hash)) bytes=\(bytes, privacy: .public)")
            return
        }
        let temp = try prepareVerifiedBasemapObject(from: fileURL, sha256: sha256, bytes: bytes)
        try movePreparedBasemapObject(temp, sha256: sha256, bytes: bytes)
    }

    private func basemapObjectTemporaryURL() -> URL {
        basemapObjectsURL.appendingPathComponent(".\(UUID().uuidString).pmtiles.tmp")
    }

    private func prepareVerifiedBasemapObject(from fileURL: URL, sha256: String, bytes: Int) throws -> URL {
        let temp = basemapObjectTemporaryURL()
        try prepareVerifiedBasemapObject(from: fileURL, to: temp, sha256: sha256, bytes: bytes)
        return temp
    }

    private func prepareVerifiedBasemapObject(from fileURL: URL, to temp: URL, sha256: String, bytes: Int) throws {
        try verifyFileObject(fileURL, sha256: sha256, bytes: bytes)
        try fm.createDirectory(at: temp.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            if fm.fileExists(atPath: temp.path) {
                try fm.removeItem(at: temp)
            }
            try fm.moveItem(at: fileURL, to: temp)
            try verifyFileObject(temp, sha256: sha256, bytes: bytes)
        } catch {
            if fm.fileExists(atPath: temp.path) {
                try? fm.removeItem(at: temp)
            }
            throw error
        }
    }

    private func registerLiveTemporaryObject(_ url: URL) {
        _ = withLock {
            rootState.liveTemporaryObjectNames.insert(url.lastPathComponent)
        }
    }

    private func unregisterLiveTemporaryObject(_ url: URL) {
        _ = withLock {
            rootState.liveTemporaryObjectNames.remove(url.lastPathComponent)
        }
    }

    private func movePreparedBasemapObject(_ temp: URL, sha256: String, bytes: Int) throws {
        let url = basemapObjectURL(sha256: sha256)
        if (try? verifyExistingBasemapObject(sha256: sha256, bytes: bytes)) != nil {
            if fm.fileExists(atPath: temp.path) {
                try fm.removeItem(at: temp)
            }
            MakingTracksLog.downloads.debug("object skipped kind=basemap sha=\(sha256, privacy: .private(mask: .hash)) bytes=\(bytes, privacy: .public)")
            return
        }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.moveItem(at: temp, to: url)
        try verifyExistingBasemapObject(sha256: sha256, bytes: bytes)
        MakingTracksLog.downloads.debug("object written kind=basemap sha=\(sha256, privacy: .private(mask: .hash)) bytes=\(bytes, privacy: .public)")
    }

    private func verifyExistingTileObject(sha256: String, bytes: Int) throws {
        try verifyTileObject(tileObjectURL(sha256: sha256), sha256: sha256, bytes: bytes)
    }

    private func verifyTileObject(_ url: URL, sha256: String, bytes: Int) throws {
        let data = try Data(contentsOf: url)
        _ = try TileCodec.decode(gzipped: data, expectedSHA256: sha256, expectedBytes: bytes)
    }

    private func verifyExistingBasemapObject(sha256 expectedSHA256: String, bytes: Int) throws {
        let url = basemapObjectURL(sha256: expectedSHA256)
        try verifyFileObject(url, sha256: expectedSHA256, bytes: bytes)
    }

    private func verifyFileObject(_ url: URL, sha256 expectedSHA256: String, bytes: Int) throws {
        let (actualSHA256, actualBytes) = try sha256AndByteCount(of: url)
        guard actualBytes == bytes else { throw TileError.byteCountMismatch }
        guard actualSHA256 == expectedSHA256 else { throw TileError.checksumMismatch }
    }

    private func fileByteCount(_ url: URL) throws -> Int {
        guard let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw TileError.byteCountMismatch
        }
        return fileSize
    }

    private func sha256AndByteCount(of url: URL) throws -> (String, Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        var byteCount = 0
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty {
                break
            }
            byteCount += chunk.count
            hasher.update(data: chunk)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), byteCount)
    }

    private func verifiedObjectSize(url: URL, expectedBytes: Int) throws -> Int {
        guard expectedBytes >= 0 else { throw TileError.invalidOfflinePack }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, values.fileSize == expectedBytes else {
                throw TileError.invalidOfflinePack
            }
            return expectedBytes
        } catch let error as TileError {
            throw error
        } catch {
            throw TileError.invalidOfflinePack
        }
    }

    private func checkedSum<S: Sequence>(_ values: S) throws -> Int where S.Element == Int {
        try values.reduce(0) { total, value in
            try checkedAdd(total, value)
        }
    }

    private func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw TileError.invalidOfflinePack }
        return sum
    }

    private func garbageCollectObjects() throws {
        let tempInstallsSwept = try sweepTemporaryInstallDirectories()
        let tileTemps = try sweepTemporaryObjectFiles(in: tileObjectsURL)
        let basemapTemps = try sweepTemporaryObjectFiles(in: basemapObjectsURL)
        MakingTracksLog.gc.debug("gc temporary sweep installs=\(tempInstallsSwept, privacy: .public) tileSwept=\(tileTemps.swept, privacy: .public) tileRetained=\(tileTemps.retained, privacy: .public) basemapSwept=\(basemapTemps.swept, privacy: .public) basemapRetained=\(basemapTemps.retained, privacy: .public)")
        guard let references = try referencedObjectsForDeletion() else { return }
        let tileGC = try removeUnreferencedObjects(in: tileObjectsURL, keeping: references.tileSHAs, extension: "gz")
        let basemapGC = try removeUnreferencedObjects(in: basemapObjectsURL, keeping: references.basemapSHAs, extension: "pmtiles")
        MakingTracksLog.gc.info("gc pass kind=tile swept=\(tileGC.swept, privacy: .public) retained=\(tileGC.retained, privacy: .public)")
        MakingTracksLog.gc.info("gc pass kind=basemap swept=\(basemapGC.swept, privacy: .public) retained=\(basemapGC.retained, privacy: .public)")
    }

    private func referencedObjectsForDeletion() throws -> (tileSHAs: Set<String>, basemapSHAs: Set<String>)? {
        do {
            return try referencedObjects()
        } catch {
            MakingTracksLog.gc.error("gc skipped reason=reference-scan-failed detail=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            return nil
        }
    }

    private func recoverInterruptedInstallsLocked() throws {
        let tmpRoot = root.appendingPathComponent("tmp", isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(at: tmpRoot, includingPropertiesForKeys: [.isDirectoryKey]) else {
            MakingTracksLog.install.debug("install recovery scanned backups=0 recovered=0 removed=0 skipped=0")
            return
        }
        var scanned = 0
        var recovered = 0
        var removed = 0
        var skipped = 0
        for child in children where child.lastPathComponent.hasSuffix("-backup") {
            scanned += 1
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            guard let publish = try? JSONDecoder().decode(
                PinnedPublish.self,
                from: boundedData(contentsOf: child.appendingPathComponent("manifest-snapshot.json"), maxBytes: Self.maxOfflineManifestSnapshotBytes)
            ) else {
                skipped += 1
                continue
            }
            guard isValidRegion(publish.region),
                  isValidPublishVersion(publish.publishVersion),
                  (try? installedCurrentPackLocked(region: publish.region))?.publishVersion == publish.publishVersion
            else {
                try? fm.removeItem(at: child)
                removed += 1
                continue
            }
            let final = packURL(region: publish.region, publishVersion: publish.publishVersion)
            if fm.fileExists(atPath: final.path) {
                try? fm.removeItem(at: child)
                removed += 1
            } else {
                try fm.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: child, to: final)
                try excludeFromBackup(final)
                recovered += 1
            }
            try removeNonCurrentPackDirectoriesLocked(region: publish.region, currentPublishVersion: publish.publishVersion)
        }
        MakingTracksLog.install.info("install recovery scanned backups=\(scanned, privacy: .public) recovered=\(recovered, privacy: .public) removed=\(removed, privacy: .public) skipped=\(skipped, privacy: .public)")
    }

    private func removeNonCurrentPackDirectoriesLocked(region: String, currentPublishVersion: String) throws {
        let packsRoot = root.appendingPathComponent("packs").appendingPathComponent(region, isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(at: packsRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for child in children where child.lastPathComponent != currentPublishVersion {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            try? fm.removeItem(at: child)
        }
    }

    private func sweepTemporaryInstallDirectories() throws -> Int {
        let tmpRoot = root.appendingPathComponent("tmp", isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(at: tmpRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return 0 }
        var swept = 0
        for child in children {
            guard !child.lastPathComponent.hasSuffix("-backup") else { continue }
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            try? fm.removeItem(at: child)
            swept += 1
        }
        return swept
    }

    private func sweepTemporaryObjectFiles(in directory: URL) throws -> (swept: Int, retained: Int) {
        guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return (0, 0) }
        let liveTemporaryObjectNames = rootState.liveTemporaryObjectNames
        var swept = 0
        var retained = 0
        for child in children where Self.shouldSweepTemporaryObjectFile(
            named: child.lastPathComponent,
            liveTemporaryObjectNames: liveTemporaryObjectNames
        ) {
            let values = try child.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                try? fm.removeItem(at: child)
                swept += 1
            }
        }
        for child in children where liveTemporaryObjectNames.contains(child.lastPathComponent) {
            let values = try child.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                retained += 1
            }
        }
        return (swept, retained)
    }

    static func shouldSweepTemporaryObjectFile(named name: String, liveTemporaryObjectNames: Set<String>) -> Bool {
        name.hasPrefix(".") && name.hasSuffix(".tmp") && !liveTemporaryObjectNames.contains(name)
    }

    private func referencedObjects() throws -> (tileSHAs: Set<String>, basemapSHAs: Set<String>) {
        let regionsRoot = root.appendingPathComponent("regions", isDirectory: true)
        guard fm.fileExists(atPath: regionsRoot.path) else {
            return try referencedInProgressObjects(tileSHAs: [], basemapSHAs: [])
        }
        let regions = try fm.contentsOfDirectory(at: regionsRoot, includingPropertiesForKeys: [.isDirectoryKey])
        var tileSHAs = Set<String>()
        var basemapSHAs = Set<String>()
        for regionURL in regions {
            let values = try regionURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let region = regionURL.lastPathComponent
            guard isValidRegion(region) else { continue }
            guard let current = try installedCurrentPackLocked(region: region) else { continue }
            let publish = try publishSnapshotLocked(region: region, publishVersion: current.publishVersion)
            tileSHAs.formUnion(publish.manifest.tiles.map(\.sha256))
            basemapSHAs.insert(publish.manifest.basemap.sha256)
        }
        return try referencedInProgressObjects(tileSHAs: tileSHAs, basemapSHAs: basemapSHAs)
    }

    private func referencedInProgressObjects(
        tileSHAs: Set<String>,
        basemapSHAs: Set<String>
    ) throws -> (tileSHAs: Set<String>, basemapSHAs: Set<String>) {
        var tileSHAs = tileSHAs
        var basemapSHAs = basemapSHAs
        let inProgressRoot = root.appendingPathComponent("in-progress")
        guard let enumerator = fm.enumerator(at: inProgressRoot, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return (tileSHAs, basemapSHAs)
        }
        for case let url as URL in enumerator where url.lastPathComponent == "pack-index.json" {
            guard let index = try? JSONDecoder().decode(OfflinePackIndex.self, from: Data(contentsOf: url)),
                  index.tileSHAs.count <= 1_048_576,
                  index.tileSHAs.values.allSatisfy({ $0.matches("^[0-9a-f]{64}$") }),
                  index.basemapSHA.matches("^[0-9a-f]{64}$")
            else { continue }
            tileSHAs.formUnion(index.tileSHAs.values)
            basemapSHAs.insert(index.basemapSHA)
        }
        return (tileSHAs, basemapSHAs)
    }

    private func removeUnreferencedObjects(in directory: URL, keeping references: Set<String>, extension pathExtension: String) throws -> (swept: Int, retained: Int) {
        guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return (0, 0) }
        var swept = 0
        var retained = 0
        for child in children where child.pathExtension == pathExtension {
            let sha = objectSHA(from: child)
            if !references.contains(sha) {
                try? fm.removeItem(at: child)
                swept += 1
            } else {
                retained += 1
            }
        }
        return (swept, retained)
    }

    private func objectSHA(from url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasSuffix(".json.gz") {
            return String(name.dropLast(".json.gz".count))
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func isValidRegion(_ value: String) -> Bool {
        value.matches(regionIDPattern)
    }

    private func isValidPublishVersion(_ value: String) -> Bool {
        value.matches("^[0-9]{8}T[0-9]{6}Z$")
    }

    private func packIndexCacheKey(region: String, publishVersion: String) -> String {
        "\(region)/\(publishVersion)"
    }

    private func boundedData(contentsOf url: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw TileError.invalidOfflinePack }
        return data
    }

    private func validatePublish(_ publish: PinnedPublish) throws {
        guard publish.region.matches(regionIDPattern),
              publish.publishVersion.matches("^[0-9]{8}T[0-9]{6}Z$"),
              publish.region == publish.manifest.region,
              publish.publishVersion == publish.manifest.publishVersion
        else { throw TileError.invalidOfflinePack }
    }

    private func packIndex(for publish: PinnedPublish) -> OfflinePackIndex {
        OfflinePackIndex(
            region: publish.region,
            publishVersion: publish.publishVersion,
            tileSHAs: Dictionary(uniqueKeysWithValues: publish.manifest.tiles.map {
                ("\($0.x)/\($0.y)", $0.sha256)
            }),
            tiles: Dictionary(uniqueKeysWithValues: publish.manifest.tiles.map {
                (
                    "\($0.x)/\($0.y)",
                    OfflinePackTileIndexEntry(sha256: $0.sha256, bytes: $0.bytes)
                )
            }),
            basemapSHA: publish.manifest.basemap.sha256,
            basemapBytes: publish.manifest.basemap.bytes,
            attribution: publish.manifest.attribution,
            attributionSources: publish.manifest.attribution.map(\.source)
        )
    }

    private func removeInProgressDownload(region: String, publishVersion: String) throws {
        let url = inProgressURL(region: region, publishVersion: publishVersion)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        rootState.lock.lock()
        defer { rootState.lock.unlock() }
        return try body()
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}

private struct OfflineCurrentPack: Codable {
    let publishVersion: String
}

private struct OfflinePackIndex: Codable {
    let region: String
    let publishVersion: String
    let tileSHAs: [String: String]
    let tiles: [String: OfflinePackTileIndexEntry]
    let basemapSHA: String
    let basemapBytes: Int
    let attribution: [Attribution]
    let attributionSources: [String]
    let hasTileMetadata: Bool

    enum CodingKeys: String, CodingKey {
        case region
        case publishVersion
        case tileSHAs
        case tiles
        case basemapSHA
        case basemapBytes
        case attribution
        case attributionSources
    }

    init(
        region: String,
        publishVersion: String,
        tileSHAs: [String: String],
        tiles: [String: OfflinePackTileIndexEntry],
        basemapSHA: String,
        basemapBytes: Int,
        attribution: [Attribution],
        attributionSources: [String]
    ) {
        self.region = region
        self.publishVersion = publishVersion
        self.tileSHAs = tileSHAs
        self.tiles = tiles
        self.basemapSHA = basemapSHA
        self.basemapBytes = basemapBytes
        self.attribution = attribution
        self.attributionSources = attributionSources
        hasTileMetadata = true
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        region = try container.decode(String.self, forKey: .region)
        publishVersion = try container.decode(String.self, forKey: .publishVersion)
        tileSHAs = try container.decode([String: String].self, forKey: .tileSHAs)
        if let decodedTiles = try container.decodeIfPresent([String: OfflinePackTileIndexEntry].self, forKey: .tiles) {
            tiles = decodedTiles
            hasTileMetadata = true
        } else {
            tiles = [:]
            hasTileMetadata = false
        }
        basemapSHA = try container.decode(String.self, forKey: .basemapSHA)
        basemapBytes = try container.decodeIfPresent(Int.self, forKey: .basemapBytes) ?? 0
        attribution = try container.decodeIfPresent([Attribution].self, forKey: .attribution) ?? []
        attributionSources = try container.decodeIfPresent([String].self, forKey: .attributionSources) ?? attribution.map(\.source)
    }
}

private struct OfflinePackTileIndexEntry: Codable, Sendable, Equatable {
    let sha256: String
    let bytes: Int
}

public final class TileCache: @unchecked Sendable {
    /// Tunable budget; B7 offline packs are intentionally outside this B3 cache.
    public static let maxBytes = 64 * 1024 * 1024

    private let directory: URL
    private let maxBytes: Int
    private let fm = FileManager.default
    private let lock = NSLock()
    private var accessCounter: Int
    private var accessEntries: [String: Int]

    public init(directory: URL, maxBytes: Int = TileCache.maxBytes) throws {
        self.directory = directory
        self.maxBytes = maxBytes
        if let stored = try? JSONDecoder().decode(TileAccess.self, from: Data(contentsOf: directory.appendingPathComponent("tile-access.json"))) {
            accessCounter = stored.next
            accessEntries = stored.entries
        } else {
            accessCounter = 1
            accessEntries = [:]
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func recordVerifiedPublish(region: String, publish: PinnedPublish) throws {
        let data = try JSONEncoder().encode(publish)
        let url = manifestURL(region: region)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func lastVerifiedPublish(region: String) throws -> PinnedPublish? {
        let url = manifestURL(region: region)
        guard fm.fileExists(atPath: url.path) else { return nil }
        let cached = try JSONDecoder().decode(PinnedPublish.self, from: Data(contentsOf: url))
        let strictManifest = try Manifest.decode(try JSONEncoder().encode(cached.manifest))
        return PinnedPublish(region: cached.region, publishVersion: cached.publishVersion, manifest: strictManifest)
    }

    public func storeTile(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String, data: Data) throws {
        let url = tileURL(region: region, publishVersion: publishVersion, coordinate: coordinate, sha256: sha256)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try touch(url)
        try trimIfNeeded()
    }

    public func tile(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String) -> Data? {
        let url = tileURL(region: region, publishVersion: publishVersion, coordinate: coordinate, sha256: sha256)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? touch(url)
        return data
    }

    public func evictPublish(region: String, publishVersion: String) {
        try? fm.removeItem(at: directory.appendingPathComponent(region).appendingPathComponent(publishVersion))
    }

    public func purgeNonPinned(region: String, pinnedPublishVersion: String) {
        let root = directory.appendingPathComponent(region)
        guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for child in children where child.lastPathComponent != pinnedPublishVersion && child.lastPathComponent != "last-publish.json" {
            try? fm.removeItem(at: child)
        }
    }

    private func manifestURL(region: String) -> URL {
        directory.appendingPathComponent(region).appendingPathComponent("last-publish.json")
    }

    private func tileURL(region: String, publishVersion: String, coordinate: TileCoordinate, sha256: String) -> URL {
        directory
            .appendingPathComponent(region)
            .appendingPathComponent(publishVersion)
            .appendingPathComponent("tiles")
            .appendingPathComponent(String(coordinate.z))
            .appendingPathComponent(String(coordinate.x))
            .appendingPathComponent("\(coordinate.y)-\(sha256).json.gz")
    }

    private func trimIfNeeded() throws {
        let access = accessSnapshot()
        let files = try tileFiles()
        var total = files.reduce(0) { $0 + $1.bytes }
        for file in files.sorted(by: { access[cacheKey($0.url), default: 0] < access[cacheKey($1.url), default: 0] }) where total > maxBytes {
            try? fm.removeItem(at: file.url)
            total -= file.bytes
        }
    }

    private func tileFiles() throws -> [(url: URL, bytes: Int)] {
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return []
        }
        var files: [(URL, Int)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true, url.pathExtension == "gz" {
                files.append((url, values.fileSize ?? 0))
            }
        }
        return files
    }

    private func touch(_ url: URL) throws {
        lock.lock()
        accessEntries[cacheKey(url)] = accessCounter
        accessCounter += 1
        let snapshot = TileAccess(next: accessCounter, entries: accessEntries)
        lock.unlock()
        try JSONEncoder().encode(snapshot).write(to: accessURL, options: .atomic)
    }

    private var accessURL: URL {
        directory.appendingPathComponent("tile-access.json")
    }

    private func accessSnapshot() -> [String: Int] {
        lock.lock()
        let snapshot = accessEntries
        lock.unlock()
        return snapshot
    }

    private func cacheKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}

private struct TileAccess: Codable {
    var next: Int
    var entries: [String: Int]
}

public enum TileFetchConcurrency {
    /// Bounded concurrency for viewport tile fetch/decode work; tune after pan telemetry.
    public static let maxConcurrent = 4
}

private final class AsyncBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 0
    private var continuations: [Int: AsyncStream<Element>.Continuation] = [:]

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = lock.withLock {
                let id = nextID
                nextID += 1
                continuations[id] = continuation
                return id
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.continuations[id] = nil
                }
            }
        }
    }

    func yield(_ value: Element) {
        let snapshot = lock.withLock { Array(continuations.values) }
        for continuation in snapshot {
            continuation.yield(value)
        }
    }
}

public actor TileClient {
    // Tunable: enough refs for open/recent card actions after panning, still a hard memory bound.
    private static let recentPlaceRefLimit = 128

    private let region: String
    private let fetcher: TileFetching
    private let cache: TileCache
    private let offlineStore: OfflineRegionStore?
    private var pin: PinnedPublish?
    private var state: TileLoadState = .unavailable
    private var loadedPlaces: [String: DecodedPlace] = [:]
    private var loadedImages: [String: PlaceImage] = [:]
    private var recentPlaceRefs: [String: PlaceRef] = [:]
    private var recentPlaceRefOrder: [String] = []
    private var viewportBasemap: InstalledPackBasemap?
    private var viewportAttribution: [Attribution] = []
    private var viewportGeneration = 0
    private var imageLoadTask: Task<Void, Never>?
    private let imageChangeBroadcaster = AsyncBroadcaster<Set<String>>()
    public nonisolated var imageChanges: AsyncStream<Set<String>> {
        imageChangeBroadcaster.stream()
    }

    public init(region: String, fetcher: TileFetching, cache: TileCache, offlineStore: OfflineRegionStore? = nil) {
        self.region = region
        self.fetcher = fetcher
        self.cache = cache
        self.offlineStore = offlineStore
    }

    public func refreshPin() async throws {
        let startedAt = Date()
        let regionID = region
        MakingTracksLog.resolution.info("pin refresh started region=\(regionID, privacy: .private(mask: .hash))")
        let oldPublishVersion = pin?.publishVersion
        let result = await ManifestClient(region: region, fetcher: fetcher, cache: cache).refresh()
        let installed = try? offlineStore?.installedPublish(region: region)
        let resolved = resolvePin(remote: result, installed: installed)
        pin = resolved.publish
        state = resolved.state
        if oldPublishVersion != resolved.publish?.publishVersion {
            clearLoadedPlaceRefs()
            viewportBasemap = nil
            viewportAttribution = []
        }
        if let pin {
            cache.purgeNonPinned(region: region, pinnedPublishVersion: pin.publishVersion)
        }
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        let stateLabel = state.rawValue
        let version = pin?.publishVersion ?? "none"
        MakingTracksLog.resolution.info("pin refresh finished region=\(regionID, privacy: .private(mask: .hash)) state=\(stateLabel, privacy: .public) version=\(version, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
    }

    public func loadLocalPin() {
        guard pin == nil else { return }
        let cached = try? cache.lastVerifiedPublish(region: region)
        let installed = try? offlineStore?.installedPublish(region: region)
        let result = ManifestPinResult(
            publish: cached,
            state: cached == nil ? .unavailable : .stale
        )
        let resolved = resolvePin(remote: result, installed: installed)
        pin = resolved.publish
        state = resolved.state
    }

    public func places(inViewport bbox: BBox, zoom: Int, allowManifestRefresh: Bool = true) async -> [MapPlace] {
        if pin == nil {
            if allowManifestRefresh {
                try? await refreshPin()
            } else {
                loadLocalPin()
            }
        }
        let startedAt = Date()
        let regionID = region
        let coveredCoordinates = Set(TileCoverage.tiles(for: bbox))
        let offlineResolution: OfflinePackResolution
        do {
            offlineResolution = try offlineStore?.installedTileResolution(intersecting: bbox)
                ?? OfflinePackResolution(tiles: [], quarantinedPacks: [])
        } catch {
            loadedPlaces = [:]
            loadedImages = [:]
            viewportBasemap = nil
            viewportAttribution = []
            state = .manifestInvalid
            MakingTracksLog.resolution.error("viewport failed region=\(regionID, privacy: .private(mask: .hash)) zoom=\(zoom, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            return []
        }
        let blockedCoordinates = offlineResolution.blockedCoordinates.intersection(coveredCoordinates)
        let needed = tileRequests(
            installedTiles: offlineResolution.tiles,
            fallback: pin,
            coveredCoordinates: coveredCoordinates,
            blockedFallbackCoordinates: blockedCoordinates
        )
        let covered = coveredCoordinates.count
        let blocked = blockedCoordinates.count
        let installedRequests = needed.filter(\.source.isInstalled).count
        let fallbackRequests = needed.count - installedRequests
        MakingTracksLog.resolution.debug("viewport planned region=\(regionID, privacy: .private(mask: .hash)) zoom=\(zoom, privacy: .public) covered=\(covered, privacy: .public) blocked=\(blocked, privacy: .public) installed=\(installedRequests, privacy: .public) fallback=\(fallbackRequests, privacy: .public) quarantines=\(offlineResolution.quarantinedPacks.count, privacy: .public)")
        guard !needed.isEmpty else {
            loadedPlaces = [:]
            loadedImages = [:]
            viewportBasemap = nil
            viewportAttribution = []
            if !blockedCoordinates.isEmpty, state != .updateAvailable {
                state = .manifestInvalid
            }
            let stateLabel = state.rawValue
            MakingTracksLog.resolution.info("viewport empty region=\(regionID, privacy: .private(mask: .hash)) state=\(stateLabel, privacy: .public)")
            return []
        }
        viewportBasemap = needed.reduce(nil as PublishTileRequest?) { current, request in
            guard request.basemap != nil else { return current }
            return tileRequest(request, winsOver: current) ? request : current
        }?.basemap
        viewportAttribution = mergedAttribution(from: needed)
        viewportGeneration += 1
        imageLoadTask?.cancel()
        imageLoadTask = nil
        let generation = viewportGeneration

        var viewportPlaces: [String: DecodedPlace] = [:]
        var viewportRequests: [String: PublishTileRequest] = [:]
        var usedCache = false
        var trustedTile = false
        var missingTile = false

        await withTaskGroup(of: TileLoadResult.self) { group in
            var iterator = needed.makeIterator()
            for _ in 0..<TileFetchConcurrency.maxConcurrent {
                guard let request = iterator.next() else { break }
                group.addTask {
                    await loadTile(
                        request: request,
                        fetcher: self.fetcher,
                        cache: self.cache,
                        offlineStore: self.offlineStore
                    )
                }
            }
            while let result = await group.next() {
                if generation != viewportGeneration {
                    group.cancelAll()
                    return
                }
                switch result {
                case .loaded(let loaded):
                    switch loaded.source {
                    case .cache:
                        usedCache = true
                    case .network:
                        trustedTile = true
                    case .offlinePack:
                        trustedTile = true
                    }
                    if !loaded.decoded.missingAttributionSources.isEmpty {
                        cache.evictPublish(region: loaded.request.region, publishVersion: loaded.request.publishVersion)
                        self.pin = nil
                        clearLoadedPlaceRefs()
                        state = .manifestInvalid
                        MakingTracksLog.resolution.error("viewport rejected region=\(regionID, privacy: .private(mask: .hash)) reason=missing-attribution sources=\(loaded.decoded.missingAttributionSources.count, privacy: .public)")
                        group.cancelAll()
                        return
                    }
                    for place in loaded.decoded.places {
                        let currentRequest = viewportRequests[place.mapPlace.id]
                        if tileRequest(loaded.request, winsOver: currentRequest) {
                            viewportPlaces[place.mapPlace.id] = place
                            viewportRequests[place.mapPlace.id] = loaded.request
                        }
                    }
                case .missing:
                    missingTile = true
                case .invalid:
                    missingTile = true
                }
                guard let request = iterator.next() else { continue }
                group.addTask {
                    await loadTile(
                        request: request,
                        fetcher: self.fetcher,
                        cache: self.cache,
                        offlineStore: self.offlineStore
                    )
                }
            }
        }
        guard generation == viewportGeneration else { return [] }
        if state == .manifestInvalid { return [] }
        loadedPlaces = viewportPlaces
        loadedImages = [:]
        if usedCache {
            state = .stale
        } else if trustedTile, state != .updateAvailable {
            state = .ok
        } else if missingTile, !needed.isEmpty, state != .updateAvailable {
            state = .unavailable
        }
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        let stateLabel = state.rawValue
        MakingTracksLog.resolution.info("viewport finished region=\(regionID, privacy: .private(mask: .hash)) state=\(stateLabel, privacy: .public) loaded=\(viewportPlaces.count, privacy: .public) requests=\(needed.count, privacy: .public) cache=\(usedCache, privacy: .public) trusted=\(trustedTile, privacy: .public) missing=\(missingTile, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
        let imageRequests = imageIndexLoadRequests(from: viewportRequests)
        if !imageRequests.isEmpty {
            let imageFetcher = fetcher
            imageLoadTask = Task {
                await self.loadViewportImages(imageRequests, generation: generation, fetcher: imageFetcher)
            }
        }
        return viewportPlaces.values.map(\.mapPlace).sorted(by: { $0.id < $1.id })
    }

    public func isPresentInCurrentTiles(_ placeID: String) async -> Bool {
        loadedPlaces[placeID] != nil
    }

    public func placeRef(for placeID: String) async -> PlaceRef? {
        if let placeRef = loadedPlaces[placeID]?.placeRef {
            rememberRecentPlaceRef(placeRef)
            return placeRef
        }
        return recentPlaceRefs[placeID]
    }

    public func placeImage(for placeID: String) async -> PlaceImage? {
        loadedImages[placeID]
    }

    private func loadViewportImages(
        _ requests: [ImageIndexLoadRequest],
        generation: Int,
        fetcher: TileFetching
    ) async {
        var imagesByPlace: [String: PlaceImage] = [:]
        await withTaskGroup(of: [String: PlaceImage].self) { group in
            var iterator = requests.makeIterator()
            for _ in 0..<TileFetchConcurrency.maxConcurrent {
                guard let request = iterator.next() else { break }
                group.addTask {
                    await loadImageIndex(request: request.tile, placeIDs: request.placeIDs, fetcher: fetcher)
                }
            }
            while let images = await group.next() {
                if generation != viewportGeneration {
                    group.cancelAll()
                    return
                }
                imagesByPlace.merge(images) { current, _ in current }
                guard let request = iterator.next() else { continue }
                group.addTask {
                    await loadImageIndex(request: request.tile, placeIDs: request.placeIDs, fetcher: fetcher)
                }
            }
        }
        guard generation == viewportGeneration else { return }
        let currentPlaceIDs = Set(loadedPlaces.keys)
        loadedImages = imagesByPlace.filter { currentPlaceIDs.contains($0.key) }
        imageLoadTask = nil
        if !loadedImages.isEmpty {
            imageChangeBroadcaster.yield(Set(loadedImages.keys))
        }
    }

    private func rememberRecentPlaceRef(_ placeRef: PlaceRef) {
        recentPlaceRefs[placeRef.placeID] = placeRef
        recentPlaceRefOrder.removeAll { $0 == placeRef.placeID }
        recentPlaceRefOrder.append(placeRef.placeID)
        while recentPlaceRefOrder.count > Self.recentPlaceRefLimit {
            let evicted = recentPlaceRefOrder.removeFirst()
            recentPlaceRefs[evicted] = nil
        }
    }

    private func clearLoadedPlaceRefs() {
        loadedPlaces.removeAll()
        loadedImages.removeAll()
        imageLoadTask?.cancel()
        imageLoadTask = nil
        recentPlaceRefs.removeAll()
        recentPlaceRefOrder.removeAll()
    }

    public var attribution: [Attribution] {
        get async { viewportAttribution.isEmpty ? (pin?.attribution ?? []) : viewportAttribution }
    }

    public var basemapURL: URL? {
        get async {
            if let viewportBasemap,
               let offlineURL = offlineStore?.basemapURL(
                   region: viewportBasemap.region,
                   publishVersion: viewportBasemap.publishVersion,
                   sha256: viewportBasemap.sha256,
                   bytes: viewportBasemap.bytes
               ) {
                return offlineURL
            }
            guard let pin else { return nil }
            return offlineStore?.basemapURL(
                region: pin.region,
                publishVersion: pin.publishVersion,
                sha256: pin.manifest.basemap.sha256,
                bytes: pin.manifest.basemap.bytes
            ) ?? pin.basemapURL
        }
    }

    public var basemapIntegrity: (sha256: String, bytes: Int)? {
        get async {
            if let viewportBasemap {
                return (viewportBasemap.sha256, viewportBasemap.bytes)
            }
            return pin?.basemapIntegrity
        }
    }

    public var loadState: TileLoadState {
        get async { state }
    }

    private func resolvePin(remote: ManifestPinResult, installed: PinnedPublish?) -> ManifestPinResult {
        guard let installed else { return remote }
        guard let remotePublish = remote.publish else {
            let resolvedState: TileLoadState = switch remote.state {
            case .updateRequired:
                .updateAvailable
            case .unavailable:
                .offline
            default:
                remote.state
            }
            return ManifestPinResult(publish: installed, state: resolvedState)
        }
        if remote.state == .ok, remotePublish.publishVersion != installed.publishVersion {
            return ManifestPinResult(publish: installed, state: .updateAvailable)
        }
        if remotePublish.publishVersion == installed.publishVersion {
            return ManifestPinResult(publish: installed, state: remote.state == .stale ? .stale : .ok)
        }
        return ManifestPinResult(publish: installed, state: .updateAvailable)
    }

    private func tileRequests(
        installedTiles: [InstalledPackTile],
        fallback: PinnedPublish?,
        coveredCoordinates: Set<TileCoordinate>,
        blockedFallbackCoordinates: Set<TileCoordinate> = []
    ) -> [PublishTileRequest] {
        var requestsByCoordinate: [TileCoordinate: PublishTileRequest] = [:]
        for installedTile in installedTiles {
            let request = PublishTileRequest(
                region: installedTile.region,
                publishVersion: installedTile.publishVersion,
                coordinate: installedTile.coordinate,
                tile: installedTile.tile,
                attribution: installedTile.attribution,
                attributionSources: Set(installedTile.attributionSources),
                source: .installed(packTileCount: installedTile.packTileCount),
                basemap: installedTile.basemap
            )
            if tileRequest(request, winsOver: requestsByCoordinate[installedTile.coordinate]) {
                requestsByCoordinate[installedTile.coordinate] = request
            }
        }
        if let fallback {
            for tile in fallback.manifest.tiles {
                let coordinate = TileCoordinate(z: fallback.manifest.tileZ, x: tile.x, y: tile.y)
                guard coveredCoordinates.contains(coordinate) else { continue }
                guard !blockedFallbackCoordinates.contains(coordinate) else { continue }
                let request = PublishTileRequest(
                    region: fallback.region,
                    publishVersion: fallback.publishVersion,
                    coordinate: coordinate,
                    tile: tile,
                    attribution: fallback.manifest.attribution,
                    attributionSources: Set(fallback.manifest.attribution.map(\.source)),
                    source: .fallback,
                    basemap: nil
                )
                if tileRequest(request, winsOver: requestsByCoordinate[coordinate]) {
                    requestsByCoordinate[coordinate] = request
                }
            }
        }
        return requestsByCoordinate.values.sorted(by: {
            ($0.coordinate.x, $0.coordinate.y, $0.region, $0.publishVersion) <
                ($1.coordinate.x, $1.coordinate.y, $1.region, $1.publishVersion)
        })
    }

    private func mergedAttribution(from requests: [PublishTileRequest]) -> [Attribution] {
        var bySource: [String: Attribution] = [:]
        for request in requests {
            for attribution in request.attribution where bySource[attribution.source] == nil {
                bySource[attribution.source] = attribution
            }
        }
        return bySource.values.sorted(by: { $0.source < $1.source })
    }
}

private struct PublishTileRequest: Sendable {
    let region: String
    let publishVersion: String
    let coordinate: TileCoordinate
    let tile: ManifestTile
    let attribution: [Attribution]
    let attributionSources: Set<String>
    let source: TileRequestSource
    let basemap: InstalledPackBasemap?
}

private struct ImageIndexLoadRequest: Sendable {
    let tile: PublishTileRequest
    let placeIDs: Set<String>
}

private struct LoadedTile: Sendable {
    let decoded: DecodedTile
    let source: TileLoadSource
    let request: PublishTileRequest
}

private enum TileRequestSource: Sendable, Equatable {
    case installed(packTileCount: Int)
    case fallback

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    var packTileCount: Int {
        switch self {
        case .installed(let packTileCount):
            packTileCount
        case .fallback:
            Int.max
        }
    }
}

private enum TileLoadSource: Sendable {
    case network
    case cache
    case offlinePack
}

private extension TileLoadSource {
    var logLabel: String {
        switch self {
        case .network:
            return "network"
        case .cache:
            return "cache"
        case .offlinePack:
            return "offlinePack"
        }
    }
}

private enum TileLoadResult: Sendable {
    case loaded(LoadedTile)
    case missing
    case invalid
}

private func loadTile(
    request: PublishTileRequest,
    fetcher: TileFetching,
    cache: TileCache,
    offlineStore: OfflineRegionStore?
) async -> TileLoadResult {
    var gzipped: Data
    var source: TileLoadSource
    if let offline = offlineStore?.tile(
        region: request.region,
        publishVersion: request.publishVersion,
        coordinate: request.coordinate,
        sha256: request.tile.sha256
    ) {
        gzipped = offline
        source = .offlinePack
        MakingTracksLog.resolution.debug("tile loaded source=offlinePack region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) bytes=\(request.tile.bytes, privacy: .public)")
    } else {
        do {
            gzipped = try await fetcher.fetch(try trustedURL("\(request.region)/\(request.publishVersion)/tiles/10/\(request.coordinate.x)/\(request.coordinate.y).json.gz"))
            _ = try TileCodec.decode(gzipped: gzipped, expectedSHA256: request.tile.sha256, expectedBytes: request.tile.bytes)
            try cache.storeTile(region: request.region, publishVersion: request.publishVersion, coordinate: request.coordinate, sha256: request.tile.sha256, data: gzipped)
            source = .network
            MakingTracksLog.resolution.debug("tile loaded source=network region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) bytes=\(request.tile.bytes, privacy: .public)")
        } catch let error as TileError {
            MakingTracksLog.resolution.error("tile load failed source=network region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            switch error {
            case .checksumMismatch, .byteCountMismatch, .compressedTooLarge, .inflatedTooLarge, .invalidGzip, .invalidTile:
                guard let cached = cache.tile(region: request.region, publishVersion: request.publishVersion, coordinate: request.coordinate, sha256: request.tile.sha256) else {
                    return .missing
                }
                gzipped = cached
                source = .cache
                MakingTracksLog.resolution.debug("tile loaded source=cache region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) bytes=\(request.tile.bytes, privacy: .public)")
            default:
                guard let cached = cache.tile(region: request.region, publishVersion: request.publishVersion, coordinate: request.coordinate, sha256: request.tile.sha256) else {
                    return .missing
                }
                gzipped = cached
                source = .cache
                MakingTracksLog.resolution.debug("tile loaded source=cache region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) bytes=\(request.tile.bytes, privacy: .public)")
            }
        } catch {
            MakingTracksLog.resolution.error("tile load failed source=network region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            guard let cached = cache.tile(region: request.region, publishVersion: request.publishVersion, coordinate: request.coordinate, sha256: request.tile.sha256) else {
                return .missing
            }
            gzipped = cached
            source = .cache
            MakingTracksLog.resolution.debug("tile loaded source=cache region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) bytes=\(request.tile.bytes, privacy: .public)")
        }
    }

    do {
        let raw = try TileCodec.decode(gzipped: gzipped, expectedSHA256: request.tile.sha256, expectedBytes: request.tile.bytes)
        let decoded = try PlaceDecoder.decode(tileData: raw, expected: request.coordinate, attributionSources: request.attributionSources)
        MakingTracksLog.resolution.debug("tile decoded source=\(source.logLabel, privacy: .public) region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) places=\(decoded.places.count, privacy: .public)")
        return .loaded(LoadedTile(decoded: decoded, source: source, request: request))
    } catch {
        MakingTracksLog.resolution.error("tile decode failed source=\(source.logLabel, privacy: .public) region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
        return .missing
    }
}

private func loadImageIndex(
    request: PublishTileRequest,
    placeIDs: Set<String>,
    fetcher: TileFetching
) async -> [String: PlaceImage] {
    do {
        let url = try trustedURL("\(request.region)/\(request.publishVersion)/images/10/\(request.coordinate.x)/\(request.coordinate.y).json")
        let data = try await fetchBounded(fetcher, url: url, maxBytes: ImagePayloadLimits.maxImageIndexBytes)
        let images = try ImageIndexDecoder.decode(data, expected: request.coordinate)
            .filter { placeIDs.contains($0.placeID) }
        MakingTracksLog.resolution.debug("image index decoded region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) images=\(images.count, privacy: .public)")
        return Dictionary(uniqueKeysWithValues: images.map { ($0.placeID, $0) })
    } catch {
        MakingTracksLog.resolution.debug("image index unavailable region=\(request.region, privacy: .private(mask: .hash)) version=\(request.publishVersion, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
        return [:]
    }
}

private func imageIndexLoadRequests(from requestsByPlace: [String: PublishTileRequest]) -> [ImageIndexLoadRequest] {
    var requestsByKey: [String: ImageIndexLoadRequest] = [:]
    for (placeID, request) in requestsByPlace {
        guard !request.source.isInstalled else { continue }
        let key = "\(request.region)/\(request.publishVersion)/\(request.coordinate.z)/\(request.coordinate.x)/\(request.coordinate.y)"
        if let existing = requestsByKey[key] {
            requestsByKey[key] = ImageIndexLoadRequest(tile: existing.tile, placeIDs: existing.placeIDs.union([placeID]))
        } else {
            requestsByKey[key] = ImageIndexLoadRequest(tile: request, placeIDs: [placeID])
        }
    }
    return requestsByKey.values.sorted { lhs, rhs in
        if lhs.tile.region != rhs.tile.region { return lhs.tile.region < rhs.tile.region }
        if lhs.tile.publishVersion != rhs.tile.publishVersion { return lhs.tile.publishVersion < rhs.tile.publishVersion }
        if lhs.tile.coordinate.x != rhs.tile.coordinate.x { return lhs.tile.coordinate.x < rhs.tile.coordinate.x }
        return lhs.tile.coordinate.y < rhs.tile.coordinate.y
    }
}

private func tileRequest(_ candidate: PublishTileRequest, winsOver current: PublishTileRequest?) -> Bool {
    guard let current else { return true }
    if candidate.source.isInstalled != current.source.isInstalled {
        return candidate.source.isInstalled
    }
    if candidate.publishVersion != current.publishVersion {
        return candidate.publishVersion > current.publishVersion
    }
    if candidate.source.packTileCount != current.source.packTileCount {
        return candidate.source.packTileCount < current.source.packTileCount
    }
    if candidate.coordinate != current.coordinate {
        return (candidate.coordinate.x, candidate.coordinate.y) < (current.coordinate.x, current.coordinate.y)
    }
    return candidate.region > current.region
}

func trustedURL(_ path: String) throws -> URL {
    guard let url = URL(string: "https://\(HTTPTileFetcher.trustedHost)/\(path)") else {
        throw TileError.invalidURL
    }
    try HTTPTileFetcher.validateOrigin(url)
    return url
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func stableJSONString(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

extension String {
    var scalarCount: Int {
        unicodeScalars.count
    }

    var isSafeText: Bool {
        unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x0000...0x001f, 0x007f...0x009f,
                 0x200b...0x200d, 0x2028...0x2029, 0x202a...0x202e,
                 0x2060, 0x2066...0x2069, 0xfeff:
                return false
            default:
                return true
            }
        }
    }

    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) == startIndex..<endIndex
    }

    var isSafeURLString: Bool {
        !isEmpty && unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x0000...0x001f, 0x007f...0x009f, 0x20:
                return false
            default:
                return true
            }
        }
    }
}
