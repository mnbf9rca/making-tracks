import Foundation
import SwiftUI
import MakingTracksData
import MakingTracksTiles

struct MakingTracksRootView: View {
    let database: AppDatabase
    let startupViewportArgument: String?
    let isFixtureMap: Bool
    let debugInstallOfflineRegion: String?
    let debugForceTileNetworkOffline: Bool
    let offlineDownloadProgress: OfflineDownloadProgress?
    let locationManager: AppLocationManager

    @AppStorage(OnboardingStorage.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage(OnboardingStorage.chosenRegionKey) private var chosenRegionRawValue = OnboardingRegionChoice.malaysia.rawValue
    @StateObject private var locationPermission: LocationPermission
    @State private var isReplayingOnboarding = false
    @State private var downloadState: OnboardingDownloadState = .idle

    init(
        database: AppDatabase,
        startupViewportArgument: String?,
        isFixtureMap: Bool,
        debugInstallOfflineRegion: String?,
        debugForceTileNetworkOffline: Bool,
        offlineDownloadProgress: OfflineDownloadProgress?,
        locationManager: AppLocationManager
    ) {
        self.database = database
        self.startupViewportArgument = startupViewportArgument
        self.isFixtureMap = isFixtureMap
        self.debugInstallOfflineRegion = debugInstallOfflineRegion
        self.debugForceTileNetworkOffline = debugForceTileNetworkOffline
        self.offlineDownloadProgress = offlineDownloadProgress
        self.locationManager = locationManager
        _locationPermission = StateObject(wrappedValue: LocationPermission(manager: locationManager))
    }

    var body: some View {
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
            locationManager: locationManager,
            locationPermission: locationPermission,
            onReplayOnboarding: {
                isReplayingOnboarding = true
            }
        )
        .fullScreenCover(isPresented: onboardingPresented) {
            OnboardingFlow(
                isReplay: isReplayingOnboarding,
                initialSelectedRegion: OnboardingFlowState.initialSelectedRegion(
                    isReplay: isReplayingOnboarding,
                    chosenRegionRawValue: chosenRegionRawValue
                ),
                locationPermission: locationPermission,
                downloadState: downloadState,
                startDownload: { region in
                    startOfflineDownload(for: region)
                },
                complete: { region in
                    completeOnboarding(region: region)
                }
            )
        }
    }

    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding || isReplayingOnboarding },
            set: { presented in
                if !presented, isReplayingOnboarding {
                    isReplayingOnboarding = false
                }
            }
        )
    }

    @MainActor
    private func completeOnboarding(region: OnboardingRegionChoice?) {
        let resolvedRegion = region ?? OnboardingRegionChoice(rawValue: chosenRegionRawValue) ?? .malaysia
        chosenRegionRawValue = resolvedRegion.rawValue
        hasCompletedOnboarding = true
        isReplayingOnboarding = false
    }

    @MainActor
    private func startOfflineDownload(for region: OnboardingRegionChoice) {
        guard !isFixtureMap else {
            downloadState = .complete
            return
        }
        downloadState = .downloading
        Task {
            do {
                let documents = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let downloader = OfflineRegionDownloader(
                    region: region.mapRegion.rawValue,
                    fetcher: HTTPTileFetcher(),
                    store: try .documentsStore(),
                    availableBytes: { StorageHeadroom.availableBytes(at: documents) }
                )
                _ = try await downloader.downloadCurrentRegion()
                await MainActor.run {
                    downloadState = .complete
                }
            } catch {
                await MainActor.run {
                    downloadState = .failed
                }
            }
        }
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

    var mapRegion: MapRegion {
        switch self {
        case .uk:
            return .uk
        case .malaysia:
            return .malaysia
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

enum OnboardingDownloadState: Equatable {
    case idle
    case downloading
    case complete
    case failed
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
    let startDownload: (OnboardingRegionChoice) -> Void
    let complete: (OnboardingRegionChoice?) -> Void

    @State private var selectedRegion: OnboardingRegionChoice?
    @State private var step: OnboardingStep = .welcome
    @State private var didRequestLocation = false
    private let downloadState: OnboardingDownloadState

    init(
        isReplay: Bool,
        initialSelectedRegion: OnboardingRegionChoice?,
        locationPermission: LocationPermission,
        downloadState: OnboardingDownloadState,
        startDownload: @escaping (OnboardingRegionChoice) -> Void,
        complete: @escaping (OnboardingRegionChoice?) -> Void
    ) {
        self.isReplay = isReplay
        self.locationPermission = locationPermission
        self.downloadState = downloadState
        self.startDownload = startDownload
        self.complete = complete
        _selectedRegion = State(initialValue: initialSelectedRegion)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                progressText
                content
                Spacer(minLength: 0)
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
                if downloadState == .downloading {
                    ProgressView()
                        .accessibilityIdentifier("onboarding.download.progress")
                } else if downloadState == .complete {
                    Label("Download ready", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("onboarding.download.complete")
                } else if downloadState == .failed {
                    Label("Download failed. You can keep using the map online.", systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("onboarding.download.failed")
                }
                Button("Download \(selectedRegionTitle)") {
                    startDownload(selectedRegion ?? .malaysia)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.download")
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
            }
        case .snow:
            onboardingSection(
                title: "Fresh snow",
                body: "Seen places fade as your tracks build up. Faded means progress, not loss."
            )
        }
    }

    private var selectedRegionTitle: String {
        (selectedRegion ?? .malaysia).title
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
            .accessibilityIdentifier("onboarding.next")
        }
    }

    private func advance() {
        guard let nextRaw = OnboardingStep(rawValue: step.rawValue + 1) else {
            complete(selectedRegion)
            return
        }
        step = nextRaw
    }
}
