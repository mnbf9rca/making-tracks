import Foundation
import SwiftUI
import UIKit

enum PlaceCardCopyIDConfirmationState: Equatable {
    case idle
    case copied
}

@MainActor
final class PlaceCardCopyIDConfirmationController {
    private let copy: (String) -> Void
    private let announce: (String) -> Void
    private let setState: (PlaceCardCopyIDConfirmationState) -> Void
    private let delay: () async -> Void
    private let dismiss: () -> Void

    private var confirmationTask: Task<Void, Never>?
    private var generation = 0

    init(
        copy: @escaping (String) -> Void,
        announce: @escaping (String) -> Void,
        setState: @escaping (PlaceCardCopyIDConfirmationState) -> Void,
        delay: @escaping () async -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.copy = copy
        self.announce = announce
        self.setState = setState
        self.delay = delay
        self.dismiss = dismiss
    }

    func activate(placeID: String) {
        guard confirmationTask == nil else { return }

        copy(placeID)
        announce("Place ID copied.")
        setState(.copied)

        generation += 1
        let activationGeneration = generation
        confirmationTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.delay()
            guard
                !Task.isCancelled,
                self.generation == activationGeneration
            else { return }

            self.dismiss()
            self.setState(.idle)
            self.confirmationTask = nil
        }
    }

    func cancel() {
        guard confirmationTask != nil else { return }

        generation += 1
        confirmationTask?.cancel()
        confirmationTask = nil
        setState(.idle)
    }
}

@MainActor
struct PlaceCardMoreMenuContent {
    static func menu(
        state: PlaceCardCopyIDConfirmationState,
        onAddToList: @escaping () -> Void,
        onCopyID: @escaping () -> Void
    ) -> UIMenu {
        let addToList = UIAction(
            title: "Add to list",
            identifier: UIAction.Identifier("place-card.add-to-list")
        ) { _ in
            onAddToList()
        }
        addToList.accessibilityIdentifier = "place-card.add-to-list"

        let copyID: UIAction
        switch state {
        case .idle:
            copyID = UIAction(
                title: "Copy ID",
                identifier: UIAction.Identifier("place-card.copy-id"),
                attributes: [.keepsMenuPresented]
            ) { _ in
                onCopyID()
            }
        case .copied:
            copyID = UIAction(
                title: "Copied",
                image: UIImage(systemName: "checkmark"),
                identifier: UIAction.Identifier("place-card.copy-id"),
                attributes: [.disabled, .keepsMenuPresented]
            ) { _ in }
        }
        copyID.accessibilityIdentifier = "place-card.copy-id"

        return UIMenu(
            title: "",
            options: [.displayInline],
            children: [addToList, copyID]
        )
    }
}

struct PlaceCardMoreMenuButton: View {
    let placeID: String
    let onAddToList: () -> Void

    var body: some View {
        ZStack {
            PlaceCardMoreMenuInteractionView(
                placeID: placeID,
                onAddToList: onAddToList
            )
            PlaceCardMoreIconGlyph()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

private struct PlaceCardMoreMenuInteractionView: UIViewRepresentable {
    let placeID: String
    let onAddToList: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(placeID: placeID, onAddToList: onAddToList)
    }

    func makeUIView(context: Context) -> PlaceCardMenuUIButton {
        let button = PlaceCardMenuUIButton(type: .custom)
        button.backgroundColor = .clear
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.isAccessibilityElement = true
        button.accessibilityLabel = "More"
        button.accessibilityHint = "Shows place actions"
        button.accessibilityIdentifier = "place-card.more"
        context.coordinator.attach(to: button)
        return button
    }

    func updateUIView(_ button: PlaceCardMenuUIButton, context: Context) {
        context.coordinator.update(
            placeID: placeID,
            onAddToList: onAddToList
        )
        context.coordinator.attach(to: button)
    }

    static func dismantleUIView(
        _ button: PlaceCardMenuUIButton,
        coordinator: Coordinator
    ) {
        coordinator.cancel()
        button.onMenuWillEnd = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        private var placeID: String
        private var onAddToList: () -> Void
        private var state: PlaceCardCopyIDConfirmationState = .idle
        private weak var button: PlaceCardMenuUIButton?
        private var confirmationController: PlaceCardCopyIDConfirmationController?

        init(placeID: String, onAddToList: @escaping () -> Void) {
            self.placeID = placeID
            self.onAddToList = onAddToList
        }

        func attach(to button: PlaceCardMenuUIButton) {
            self.button = button
            button.onMenuWillEnd = { [weak self] in
                self?.confirmationController?.cancel()
            }
            if confirmationController == nil {
                confirmationController = makeConfirmationController()
            }
            refreshMenu()
        }

        func update(placeID: String, onAddToList: @escaping () -> Void) {
            self.placeID = placeID
            self.onAddToList = onAddToList
        }

        func cancel() {
            confirmationController?.cancel()
        }

        private func makeConfirmationController() -> PlaceCardCopyIDConfirmationController {
            PlaceCardCopyIDConfirmationController(
                copy: { placeID in
                    UIPasteboard.general.string = placeID
                },
                announce: { message in
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: message
                    )
                },
                setState: { [weak self] state in
                    self?.state = state
                    self?.refreshMenu()
                },
                delay: {
                    try? await Task.sleep(for: .seconds(1))
                },
                dismiss: { [weak self] in
                    self?.button?.contextMenuInteraction?.dismissMenu()
                }
            )
        }

        private func refreshMenu() {
            let menu = makeMenu()
            button?.menu = menu
            button?.contextMenuInteraction?.updateVisibleMenu { _ in menu }
        }

        private func makeMenu() -> UIMenu {
            PlaceCardMoreMenuContent.menu(
                state: state,
                onAddToList: { [weak self] in
                    self?.confirmationController?.cancel()
                    self?.onAddToList()
                },
                onCopyID: { [weak self] in
                    guard let self else { return }
                    self.confirmationController?.activate(placeID: self.placeID)
                }
            )
        }
    }
}

@MainActor
private final class PlaceCardMenuUIButton: UIButton {
    var onMenuWillEnd: (() -> Void)?

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(
            interaction,
            willEndFor: configuration,
            animator: animator
        )
        onMenuWillEnd?()
    }
}
