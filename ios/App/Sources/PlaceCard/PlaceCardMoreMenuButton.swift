import Foundation

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
