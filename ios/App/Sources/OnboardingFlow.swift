import Foundation
import SwiftUI
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles

struct MakingTracksRootView: View {
    let database: AppDatabase
    let startupViewportArgument: String?
    let isFixtureMap: Bool
    let debugInstallOfflineRegion: String?
    let debugForceTileNetworkOffline: Bool
    let offlineDownloadProgress: OfflineDownloadProgress?
    let debugCoverageBBoxes: [CoverageBBox]
    let debugExposeFixturePinDiagnostics: Bool
    let debugHideFixtureChrome: Bool
    let debugUseDenseFixturePins: Bool
    let forceFirstRunOnboarding: Bool
    let locationManager: AppLocationManager

    @AppStorage(OnboardingStorage.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage(OnboardingStorage.chosenRegionKey) private var chosenRegionRawValue = OnboardingRegionChoice.malaysia.rawValue
    @AppStorage(OfflineDownloadSettings.allowsCellularDownloadsKey) private var allowsCellularDownloads = OfflineDownloadSettings.defaultAllowsCellularDownloads
    @StateObject private var locationPermission: LocationPermission
    @State private var isReplayingOnboarding = false
    @State private var didConsumeForcedFirstRunOnboarding = false
    @State private var downloadState: OnboardingDownloadState = .idle
    @State private var cameraRequestID = 0
    @State private var cameraRequest: ViewportCameraRequest?

    init(
        database: AppDatabase,
        startupViewportArgument: String?,
        isFixtureMap: Bool,
        debugInstallOfflineRegion: String?,
        debugForceTileNetworkOffline: Bool,
        offlineDownloadProgress: OfflineDownloadProgress?,
        debugCoverageBBoxes: [CoverageBBox] = [],
        debugExposeFixturePinDiagnostics: Bool,
        debugHideFixtureChrome: Bool = false,
        debugUseDenseFixturePins: Bool = false,
        forceFirstRunOnboarding: Bool = false,
        locationManager: AppLocationManager
    ) {
        self.database = database
        self.startupViewportArgument = startupViewportArgument
        self.isFixtureMap = isFixtureMap
        self.debugInstallOfflineRegion = debugInstallOfflineRegion
        self.debugForceTileNetworkOffline = debugForceTileNetworkOffline
        self.offlineDownloadProgress = offlineDownloadProgress
        self.debugCoverageBBoxes = debugCoverageBBoxes
        self.debugExposeFixturePinDiagnostics = debugExposeFixturePinDiagnostics
        self.debugHideFixtureChrome = debugHideFixtureChrome
        self.debugUseDenseFixturePins = debugUseDenseFixturePins
        self.forceFirstRunOnboarding = forceFirstRunOnboarding
        self.locationManager = locationManager
        _locationPermission = StateObject(wrappedValue: LocationPermission(manager: locationManager))
    }

    var body: some View {
        if shouldShowFirstRunOnboarding {
            onboardingFlow(isReplay: false)
        } else {
            mapScreen
        }
    }

    private var shouldShowFirstRunOnboarding: Bool {
        ((forceFirstRunOnboarding && !didConsumeForcedFirstRunOnboarding) || !hasCompletedOnboarding)
            && !isReplayingOnboarding
    }

    private var mapScreen: some View {
        MapScreen(
            database: database,
            startupViewport: OnboardingStorage.startupViewport(
                argumentSeed: startupViewportArgument,
                chosenRegionRawValue: chosenRegionRawValue
            ),
            isFixtureMap: isFixtureMap,
            debugInstallOfflineRegion: debugInstallOfflineRegion,
            debugForceTileNetworkOffline: debugForceTileNetworkOffline,
            offlineDownloadProgress: offlineDownloadProgress,
            debugCoverageBBoxes: debugCoverageBBoxes,
            debugExposeFixturePinDiagnostics: debugExposeFixturePinDiagnostics,
            debugHideFixtureChrome: debugHideFixtureChrome,
            debugUseDenseFixturePins: debugUseDenseFixturePins,
            locationManager: locationManager,
            locationPermission: locationPermission,
            cameraRequest: cameraRequest,
            onReplayOnboarding: {
                downloadState = .idle
                isReplayingOnboarding = true
            }
        )
        .fullScreenCover(isPresented: replayOnboardingPresented) {
            onboardingFlow(isReplay: true)
        }
        .onAppear {
            let completed = hasCompletedOnboarding
            let replay = isReplayingOnboarding
            MakingTracksLog.startup.info("root appeared completed=\(completed, privacy: .public) replay=\(replay, privacy: .public)")
        }
    }

    private var replayOnboardingPresented: Binding<Bool> {
        Binding(
            get: { isReplayingOnboarding },
            set: { presented in
                if !presented, isReplayingOnboarding {
                    isReplayingOnboarding = false
                }
            }
        )
    }

    private func onboardingFlow(isReplay: Bool) -> some View {
        OnboardingFlow(
            isReplay: isReplay,
            initialSelectedRegion: OnboardingFlowState.initialSelectedRegion(
                isReplay: isReplay,
                chosenRegionRawValue: chosenRegionRawValue
            ),
            locationPermission: locationPermission,
            downloadState: downloadState,
            showsUITestingDiagnostics: isFixtureMap,
            prepareDownload: { region in
                prepareOfflineDownload(for: region)
            },
            startDownload: { region in
                startOfflineDownload(for: region)
            },
            complete: { region in
                completeOnboarding(region: region)
            }
        )
        .onAppear {
            let completed = hasCompletedOnboarding
            MakingTracksLog.startup.info("onboarding presented replay=\(isReplay, privacy: .public) completed=\(completed, privacy: .public)")
        }
        .onDisappear {
            let completed = hasCompletedOnboarding
            MakingTracksLog.startup.info("onboarding dismissed replay=\(isReplay, privacy: .public) completed=\(completed, privacy: .public)")
        }
    }

    @MainActor
    private func completeOnboarding(region: OnboardingRegionChoice?) {
        let resolvedRegion = region ?? OnboardingRegionChoice(rawValue: chosenRegionRawValue) ?? .malaysia
        chosenRegionRawValue = resolvedRegion.rawValue
        cameraRequestID += 1
        cameraRequest = ViewportCameraRequest(id: cameraRequestID, viewport: resolvedRegion.startupViewport)
        hasCompletedOnboarding = true
        didConsumeForcedFirstRunOnboarding = true
        isReplayingOnboarding = false
        let requestID = cameraRequestID
        MakingTracksLog.startup.info("onboarding completed region=\(resolvedRegion.rawValue, privacy: .private(mask: .hash)) cameraRequest=\(requestID, privacy: .public)")
    }

    @MainActor
    private func prepareOfflineDownload(for region: OnboardingRegionChoice) {
        switch downloadState {
        case let .planning(activeRegion) where activeRegion == region:
            return
        case let .ready(plan) where plan.region == region:
            return
        case let .storageFull(plan) where plan.region == region:
            return
        case let .complete(plan) where plan.region == region:
            return
        case let .downloading(plan, _, _) where plan.region == region:
            return
        default:
            break
        }
        guard !isFixtureMap else {
            downloadState = .ready(OnboardingDownloadPlan.fixture(region: region))
            MakingTracksLog.startup.info("onboarding plan fixture region=\(region.rawValue, privacy: .private(mask: .hash))")
            return
        }
        downloadState = .planning(region)
        MakingTracksLog.startup.info("onboarding plan started region=\(region.rawValue, privacy: .private(mask: .hash))")
        Task {
            do {
                let plan = try await makeOfflinePlan(for: region)
                await MainActor.run {
                    guard downloadState.region == region else { return }
                    downloadState = plan.hasHeadroom ? .ready(plan) : .storageFull(plan)
                    MakingTracksLog.startup.info("onboarding plan finished region=\(region.rawValue, privacy: .private(mask: .hash)) bytes=\(plan.bytesToFetch, privacy: .public) headroom=\(plan.hasHeadroom, privacy: .public)")
                }
            } catch {
                await MainActor.run {
                    guard downloadState.region == region else { return }
                    downloadState = .failed(region)
                    MakingTracksLog.startup.error("onboarding plan failed region=\(region.rawValue, privacy: .private(mask: .hash)) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
                }
            }
        }
    }

    @MainActor
    private func startOfflineDownload(for region: OnboardingRegionChoice) {
        guard !downloadState.isDownloading else { return }
        let plan: OnboardingDownloadPlan
        switch downloadState {
        case let .ready(readyPlan) where readyPlan.region == region:
            plan = readyPlan
        case let .complete(completePlan) where completePlan.region == region:
            return
        default:
            prepareOfflineDownload(for: region)
            return
        }
        guard plan.hasHeadroom else {
            downloadState = .storageFull(plan)
            MakingTracksLog.startup.info("onboarding download blocked region=\(region.rawValue, privacy: .private(mask: .hash)) bytes=\(plan.bytesToFetch, privacy: .public)")
            return
        }
        guard !isFixtureMap else {
            downloadState = .complete(plan)
            MakingTracksLog.startup.info("onboarding download fixture region=\(region.rawValue, privacy: .private(mask: .hash))")
            return
        }
        downloadState = .downloading(plan, fetchedBytes: 0, isWaitingForConnectivity: false)
        MakingTracksLog.startup.info("onboarding download started region=\(region.rawValue, privacy: .private(mask: .hash)) bytes=\(plan.bytesToFetch, privacy: .public)")
        let downloadAllowsCellular = allowsCellularDownloads
        Task {
            do {
                let documents = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let backgroundIdentifier = OfflineDownloadSession.backgroundIdentifier(region: region.publishRegionID)
                await OfflineDownloadSession.prepareBackgroundSessionForPolicyChange(
                    identifier: backgroundIdentifier,
                    allowsCellularDownloads: downloadAllowsCellular
                )
                let result = try await OfflineDownloadSession.withBackgroundSessionUse(
                    identifier: backgroundIdentifier
                ) {
                    let downloader = OfflineRegionDownloader(
                        region: region.publishRegionID,
                        metadataFetcher: HTTPTileFetcher.offlineForeground(
                            allowsCellularDownloads: downloadAllowsCellular
                        ),
                        objectFetcher: HTTPTileFetcher.offlineBackground(
                            identifier: backgroundIdentifier,
                            allowsCellularDownloads: downloadAllowsCellular
                        ),
                        store: try .documentsStore(),
                        availableBytes: { StorageHeadroom.availableBytes(at: documents) }
                    )
                    return try await downloader.downloadCurrentRegion { progress in
                        Task { @MainActor in
                            guard downloadState.isDownloading else { return }
                            downloadState = .downloading(
                                plan,
                                fetchedBytes: progress.completedBytes,
                                isWaitingForConnectivity: progress.isWaitingForConnectivity
                            )
                        }
                    }
                }
                await MainActor.run {
                    guard downloadState.isDownloading else { return }
                    downloadState = .complete(plan.withFetchedBytes(result.fetchedBytes))
                    MakingTracksLog.startup.info("onboarding download finished region=\(region.rawValue, privacy: .private(mask: .hash)) bytes=\(result.fetchedBytes, privacy: .public)")
                }
            } catch {
                await MainActor.run {
                    guard downloadState.isDownloading else { return }
                    downloadState = .failed(region)
                    MakingTracksLog.startup.error("onboarding download failed region=\(region.rawValue, privacy: .private(mask: .hash)) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
                }
            }
        }
    }

    private func makeOfflinePlan(for region: OnboardingRegionChoice) async throws -> OnboardingDownloadPlan {
        let startedAt = Date()
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MakingTracks/OnboardingManifest", isDirectory: true)
        let cache = try TileCache(directory: cacheRoot)
        let client = ManifestClient(region: region.publishRegionID, fetcher: HTTPTileFetcher(), cache: cache)
        let result = await client.refresh()
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        MakingTracksLog.startup.info("onboarding manifest polled region=\(region.rawValue, privacy: .private(mask: .hash)) state=\(result.state.rawValue, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
        guard let publish = result.publish else { throw OnboardingDownloadError.planUnavailable }
        let store = try OfflineRegionStore.documentsStore()
        let updatePlan = try store.updatePlan(for: publish)
        let availableBytes = StorageHeadroom.availableBytes(at: documents)
        return OnboardingDownloadPlan(
            region: region,
            bytesToFetch: updatePlan.bytesToFetch,
            availableBytes: availableBytes,
            hasHeadroom: StorageHeadroom.hasHeadroom(requiredBytes: updatePlan.bytesToFetch, availableBytes: availableBytes),
            fetchedBytes: 0
        )
    }
}

enum OnboardingRegionChoice: String, CaseIterable, Sendable, Equatable, Identifiable {
    case uk
    case malaysia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uk:
            return "UK"
        case .malaysia:
            return "Malaysia"
        }
    }

    var publishRegionID: String {
        switch self {
        case .uk:
            return MapRegion.unitedKingdom.rawValue
        case .malaysia:
            return MapRegion.malaysiaSingaporeBrunei.rawValue
        }
    }

    var startupViewport: ViewportSeed {
        switch self {
        case .uk:
            return .uk
        case .malaysia:
            return .kl
        }
    }
}

enum OnboardingStorage {
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let chosenRegionKey = "chosenRegion"

    static func startupViewport(argumentSeed: String?, chosenRegionRawValue: String?) -> ViewportSeed {
        if let argumentSeed {
            return ViewportSeed.selected(argumentSeed)
        }
        return OnboardingRegionChoice(rawValue: chosenRegionRawValue ?? "")?.startupViewport ?? .kl
    }
}

enum OnboardingCopy {
    static let savedActivityPrivacy = "Nothing you save leaves unless you choose to share it."
    static let offlinePackOffer = "Download this region so the map works with no connection. Keep the app open while downloading."
}

struct OnboardingDownloadPlan: Equatable {
    let region: OnboardingRegionChoice
    let bytesToFetch: Int
    let availableBytes: Int64?
    let hasHeadroom: Bool
    let fetchedBytes: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesToFetch), countStyle: .file)
    }

    var formattedFetchedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(min(fetchedBytes, bytesToFetch)), countStyle: .file)
    }

    var progressFraction: Double {
        guard bytesToFetch > 0 else { return 1 }
        return min(max(Double(fetchedBytes) / Double(bytesToFetch), 0), 1)
    }

    var storageFullMessage: String {
        if let availableBytes {
            let available = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
            return "Not enough storage. This pack needs \(formattedSize), with 512 MB kept free. Available: \(available)."
        }
        return "Storage could not be checked. Free up space and try again."
    }

    func withFetchedBytes(_ fetchedBytes: Int) -> OnboardingDownloadPlan {
        OnboardingDownloadPlan(
            region: region,
            bytesToFetch: bytesToFetch,
            availableBytes: availableBytes,
            hasHeadroom: hasHeadroom,
            fetchedBytes: fetchedBytes
        )
    }

    static func fixture(region: OnboardingRegionChoice) -> OnboardingDownloadPlan {
        OnboardingDownloadPlan(region: region, bytesToFetch: 0, availableBytes: nil, hasHeadroom: true, fetchedBytes: 0)
    }
}

enum OnboardingDownloadState: Equatable {
    case idle
    case planning(OnboardingRegionChoice)
    case ready(OnboardingDownloadPlan)
    case storageFull(OnboardingDownloadPlan)
    case downloading(OnboardingDownloadPlan, fetchedBytes: Int, isWaitingForConnectivity: Bool = false)
    case complete(OnboardingDownloadPlan)
    case failed(OnboardingRegionChoice)

    var region: OnboardingRegionChoice? {
        switch self {
        case .idle:
            return nil
        case let .planning(region), let .failed(region):
            return region
        case let .ready(plan), let .storageFull(plan), let .complete(plan):
            return plan.region
        case let .downloading(plan, _, _):
            return plan.region
        }
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var statusText: String? {
        switch self {
        case let .downloading(plan, fetchedBytes, isWaitingForConnectivity):
            if isWaitingForConnectivity {
                return "Waiting for Wi-Fi"
            }
            return "\(plan.withFetchedBytes(fetchedBytes).formattedFetchedBytes) of \(plan.formattedSize)"
        default:
            return nil
        }
    }
}

enum OnboardingDownloadError: Error {
    case planUnavailable
}

enum OnboardingFlowState {
    static func initialSelectedRegion(isReplay: Bool, chosenRegionRawValue: String?) -> OnboardingRegionChoice? {
        guard isReplay else { return nil }
        return OnboardingRegionChoice(rawValue: chosenRegionRawValue ?? "")
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case about
    case region
    case offline
    case location
    case snow
}

struct OnboardingFlow: View {
    let isReplay: Bool
    @ObservedObject var locationPermission: LocationPermission
    let showsUITestingDiagnostics: Bool
    let prepareDownload: (OnboardingRegionChoice) -> Void
    let startDownload: (OnboardingRegionChoice) -> Void
    let complete: (OnboardingRegionChoice?) -> Void

    @State private var selectedRegion: OnboardingRegionChoice?
    @State private var step: OnboardingStep = .welcome
    @State private var didRequestLocation = false
    @AccessibilityFocusState private var isProgressFocused: Bool
    private let downloadState: OnboardingDownloadState

    init(
        isReplay: Bool,
        initialSelectedRegion: OnboardingRegionChoice?,
        locationPermission: LocationPermission,
        downloadState: OnboardingDownloadState,
        showsUITestingDiagnostics: Bool = false,
        prepareDownload: @escaping (OnboardingRegionChoice) -> Void,
        startDownload: @escaping (OnboardingRegionChoice) -> Void,
        complete: @escaping (OnboardingRegionChoice?) -> Void
    ) {
        self.isReplay = isReplay
        self.locationPermission = locationPermission
        self.downloadState = downloadState
        self.showsUITestingDiagnostics = showsUITestingDiagnostics
        self.prepareDownload = prepareDownload
        self.startDownload = startDownload
        self.complete = complete
        _selectedRegion = State(initialValue: initialSelectedRegion)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                progressText
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                controls
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Making Tracks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        complete(selectedRegion)
                    }
                    .accessibilityIdentifier("onboarding.skip")
                }
            }
        }
    }

    private var progressText: some View {
        Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
            .accessibilityIdentifier("onboarding.progress")
            .accessibilityFocused($isProgressFocused)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            onboardingSection(
                title: "Interesting places around you",
                body: "The map is fresh snow. Find overlooked history, architecture, and oddities; exploring marks it."
            )
        case .about:
            VStack(alignment: .leading, spacing: 14) {
                onboardingSection(
                    title: "Where places come from",
                    body: "Making Tracks uses open data from Wikipedia, OpenStreetMap, and heritage registers, and credits sources in About."
                )
                Label(OnboardingCopy.savedActivityPrivacy, systemImage: "lock")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.privacy-row")
                Label("The app is open source.", systemImage: "curlybraces")
                    .font(.body)
            }
        case .region:
            VStack(alignment: .leading, spacing: 16) {
                onboardingSection(
                    title: "Choose your first region",
                    body: "You can change regions later. This only sets the map you see first."
                )
                ForEach(OnboardingRegionChoice.allCases) { choice in
                    regionButton(choice)
                }
            }
        case .offline:
            VStack(alignment: .leading, spacing: 14) {
                onboardingSection(
                    title: "Download \(selectedRegionTitle)",
                    body: OnboardingCopy.offlinePackOffer.replacingOccurrences(of: "this region", with: selectedRegionTitle)
                )
                downloadStatus
                Button(downloadButtonTitle) {
                    startDownload(selectedRegion ?? .malaysia)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartDownload)
                .accessibilityIdentifier("onboarding.download")
            }
            .task(id: selectedRegion ?? .malaysia) {
                prepareDownload(selectedRegion ?? .malaysia)
            }
        case .location:
            VStack(alignment: .leading, spacing: 14) {
                onboardingSection(
                    title: "Show your position?",
                    body: "Use your location to find places nearby. The app never marks places seen automatically."
                )
                if locationPermission.isLocationOff {
                    Text("Location is off. You can turn it on later in Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("onboarding.location-off")
                }
                if didRequestLocation {
                    Text("Location requested")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding.location-requested")
                }
                locationRequestCountDiagnostic
            }
        case .snow:
            VStack(alignment: .leading, spacing: 14) {
                onboardingSection(
                    title: "Fresh snow",
                    body: "Seen places fade as your tracks build up. Faded means progress, not loss."
                )
                locationRequestCountDiagnostic
            }
        }
    }

    private var selectedRegionTitle: String {
        (selectedRegion ?? .malaysia).title
    }

    @ViewBuilder
    private var locationRequestCountDiagnostic: some View {
        if showsUITestingDiagnostics {
            Text(verbatim: "Location requests: \(locationPermission.authorizationRequestCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.location-request-count")
        }
    }

    @ViewBuilder
    private var downloadStatus: some View {
        switch downloadState {
        case .idle:
            Text("Checking download size...")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.download.size")
        case .planning:
            ProgressView("Checking download size")
                .accessibilityIdentifier("onboarding.download.planning")
        case let .ready(plan):
            Label("Download size: \(plan.formattedSize)", systemImage: "internaldrive")
                .accessibilityIdentifier("onboarding.download.size")
        case let .storageFull(plan):
            Label(plan.storageFullMessage, systemImage: "externaldrive.badge.exclamationmark")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.download.storage-full")
        case let .downloading(plan, fetchedBytes, _):
            let activePlan = plan.withFetchedBytes(fetchedBytes)
            let statusText = downloadState.statusText ?? "\(activePlan.formattedFetchedBytes) of \(activePlan.formattedSize)"
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: activePlan.progressFraction)
                    .accessibilityLabel("Download progress")
                    .accessibilityValue(statusText)
                    .accessibilityIdentifier("onboarding.download.progress")
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.download.progress-text")
            }
        case let .complete(plan):
            Label("Download ready: \(plan.formattedSize)", systemImage: "checkmark.circle")
                .accessibilityIdentifier("onboarding.download.complete")
        case .failed:
            Label("Download failed. You can keep using the map online.", systemImage: "exclamationmark.triangle")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.download.failed")
        }
    }

    private var canStartDownload: Bool {
        guard case let .ready(plan) = downloadState else { return false }
        return plan.region == (selectedRegion ?? .malaysia) && plan.hasHeadroom
    }

    private var downloadButtonTitle: String {
        if downloadState.isDownloading {
            return "Downloading \(selectedRegionTitle)"
        }
        return "Download \(selectedRegionTitle)"
    }

    private func onboardingSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func regionButton(_ choice: OnboardingRegionChoice) -> some View {
        let isSelected = selectedRegion == choice
        Button {
            selectedRegion = choice
        } label: {
            HStack {
                Text(choice.title)
                    .font(.body.weight(.semibold))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityIdentifier("onboarding.region.\(choice.rawValue)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var controls: some View {
        switch step {
        case .location:
            VStack(spacing: 10) {
                Button("Use my location") {
                    didRequestLocation = true
                    locationPermission.requestWhenInUseIfNeeded()
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("onboarding.location.allow")

                Button("Skip location") {
                    advance()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("onboarding.location.skip")
            }
        case .snow:
            Button("Start exploring") {
                complete(selectedRegion)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("onboarding.finish")
        default:
            Button("Next") {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(step == .region && selectedRegion == nil)
            .accessibilityIdentifier("onboarding.next")
        }
    }

    private func advance() {
        guard let nextRaw = OnboardingStep(rawValue: step.rawValue + 1) else {
            complete(selectedRegion)
            return
        }
        step = nextRaw
        isProgressFocused = true
    }
}
