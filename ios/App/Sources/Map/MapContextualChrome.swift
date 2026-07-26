import DesignSystem
import SwiftUI

struct MapDownloadProgressToast: View {
    let progress: OfflineDownloadProgress
    let onOpenOfflineMaps: () -> Void

    var body: some View {
        MaterialToast(
            message: progress.isWaitingForConnectivity
                ? "Offline maps \(progress.statusText)"
                : "Offline maps",
            surfaceAction: MaterialToastSurfaceAction(
                accessibilityLabel: "Offline maps download",
                accessibilityHint: "Opens Offline maps",
                accessibilityIdentifier: "map.download-progress",
                action: onOpenOfflineMaps
            ),
            leadingSystemImage: "arrow.down.circle",
            progressState: .percentage(progress.percentComplete)
        )
    }
}

struct MapLocationOffToast: View {
    let onOpenSettings: () -> Void

    var body: some View {
        MaterialToast(
            message: "Location is off",
            primaryActionAccessibilityIdentifier: "map.location-settings"
        ) {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .symbolRenderingMode(.monochrome)
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens location settings")
            .buttonStyle(MaterialQuietButtonStyle())
        }
    }
}

struct MapNearbyPromptToast: View {
    let message: String
    let onSeen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        MaterialToast(
            message: message,
            primaryActionAccessibilityIdentifier: "map.nearby-prompt.seen",
            dismissAction: onDismiss,
            dismissAccessibilityLabel: "Dismiss nearby prompt",
            dismissAccessibilityIdentifier: "map.nearby-prompt.dismiss"
        ) {
            Button("Seen it", action: onSeen)
                .buttonStyle(MaterialFilledButtonStyle())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.nearby-prompt")
    }
}

struct MapHiddenUndoToast: View {
    let onUndo: () -> Void

    var body: some View {
        MaterialToast(
            message: "Hidden — Undo",
            primaryActionAccessibilityIdentifier: "place-card.hide.undo"
        ) {
            Button("Undo", action: onUndo)
                .buttonStyle(MaterialTonalButtonStyle())
        }
    }
}
