import DesignSystem
import ImageIO
import SwiftUI
import UIKit
import MakingTracksCore
import MakingTracksTiles

struct PlaceCardAppearance {
    static let cardBackgroundToken = SemanticColorToken.surface
    static let mediaBackgroundToken = SemanticColorToken.road
    static let primaryTextToken = SemanticColorToken.ink
    static let secondaryTextToken = SemanticColorToken.muted
    static let linkTextToken = SemanticColorToken.accent

    let theme: MaterialTheme

    var cardBackground: Color {
        theme.tokens[Self.cardBackgroundToken].swiftUIColor
    }

    var mediaBackground: Color {
        theme.tokens[Self.mediaBackgroundToken].swiftUIColor
    }

    var primaryText: Color {
        theme.tokens[Self.primaryTextToken].swiftUIColor
    }

    var secondaryText: Color {
        theme.tokens[Self.secondaryTextToken].swiftUIColor
    }

    var linkText: Color {
        theme.tokens[Self.linkTextToken].swiftUIColor
    }
}

enum PlaceCardLayout {
    static let closeSystemImageName = "ellipsis"
    static let cardCornerRadius: CGFloat = 22
    static let mediaCornerRadius: CGFloat = 8
    static let typeSwatchSide: CGFloat = 14
    static let actionBarHorizontalPadding: CGFloat = 18
}

struct PlaceCardActionPresentation: Equatable {
    let title: String
    let systemImage: String?
    let style: PlaceCardActionStyle
}

enum PlaceCardActionStyle: Equatable {
    case tonal
    case quiet
    case state(
        foreground: SemanticColorToken,
        background: SemanticColorToken
    )
}

enum PlaceCardActionAppearance {
    static func presentation(
        for action: PlaceCardAction,
        isSaved: Bool
    ) -> PlaceCardActionPresentation {
        switch action {
        case .save where isSaved:
            PlaceCardActionPresentation(
                title: "Saved",
                systemImage: "bookmark.fill",
                style: .state(
                    foreground: .accentContrast,
                    background: .accentDeepContainer
                )
            )
        case .save:
            PlaceCardActionPresentation(
                title: "Save",
                systemImage: "bookmark",
                style: .tonal
            )
        case .seen:
            PlaceCardActionPresentation(
                title: "Seen",
                systemImage: "eye",
                style: .tonal
            )
        case .unsee:
            PlaceCardActionPresentation(
                title: "Seen",
                systemImage: "eye.fill",
                style: .state(
                    foreground: .accentContrast,
                    background: .accent
                )
            )
        case .love:
            PlaceCardActionPresentation(
                title: "Love",
                systemImage: "heart",
                style: .state(
                    foreground: .love,
                    background: .loveContainer
                )
            )
        case .unlove:
            PlaceCardActionPresentation(
                title: "Loved",
                systemImage: "heart.fill",
                style: .state(
                    foreground: .accentContrast,
                    background: .love
                )
            )
        case .hide:
            PlaceCardActionPresentation(
                title: "Hide",
                systemImage: nil,
                style: .quiet
            )
        case .unhide:
            PlaceCardActionPresentation(
                title: "Unhide",
                systemImage: nil,
                style: .quiet
            )
        }
    }

    static func usesQuietTextPressInset(for action: PlaceCardAction) -> Bool {
        switch action {
        case .hide, .unhide:
            true
        case .save, .seen, .love, .unlove, .unsee:
            false
        }
    }
}

struct PlaceCardActionStyleModifier: ViewModifier {
    let action: PlaceCardAction
    let isSaved: Bool
    let theme: MaterialTheme

    func body(content: Content) -> some View {
        PlaceCardActionStyledContent(
            content: content,
            action: action,
            isSaved: isSaved,
            theme: theme
        )
    }
}

struct PlaceCardActionStyledContent<Content: View>: View {
    let content: Content
    let action: PlaceCardAction
    let isSaved: Bool
    let theme: MaterialTheme

    @ViewBuilder
    var body: some View {
        switch PlaceCardActionAppearance.presentation(
            for: action,
            isSaved: isSaved
        ).style {
        case .tonal:
            content.buttonStyle(MaterialTonalButtonStyle(theme: theme))
        case .quiet:
            if PlaceCardActionAppearance.usesQuietTextPressInset(for: action) {
                content.buttonStyle(
                    MaterialQuietButtonStyle.textOnly(theme: theme)
                )
            } else {
                content.buttonStyle(MaterialQuietButtonStyle(theme: theme))
            }
        case let .state(foregroundToken, backgroundToken):
            content.buttonStyle(
                MaterialStateToggleButtonStyle(
                    foreground: foregroundToken,
                    background: backgroundToken,
                    theme: theme
                )
            )
        }
    }
}

enum PlaceCardPhotoLayout {
    static let preferredMinimumHeight: CGFloat = 112
    static let maximumHeight: CGFloat = 260
    static let fallbackAspectRatio: CGFloat = 4 / 3

    static func height(
        containerWidth: CGFloat,
        imageWidth: Int?,
        imageHeight: Int?
    ) -> CGFloat {
        size(
            containerWidth: containerWidth,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        ).height
    }

    static func size(
        containerWidth: CGFloat,
        imageWidth: Int?,
        imageHeight: Int?
    ) -> CGSize {
        guard containerWidth.isFinite, containerWidth > 0 else {
            return CGSize(width: 0, height: preferredMinimumHeight)
        }

        let aspectRatio: CGFloat
        if let imageWidth,
           let imageHeight,
           imageWidth > 0,
           imageHeight > 0
        {
            aspectRatio = CGFloat(imageWidth) / CGFloat(imageHeight)
        } else {
            aspectRatio = fallbackAspectRatio
        }

        let proposedHeight = containerWidth / aspectRatio
        // A hard minimum is incompatible with fixed available width, no crop,
        // and no letterbox for extreme panoramas. Preserve the intrinsic ratio
        // below the preferred minimum; a tall image can satisfy the hard
        // maximum by narrowing its frame.
        let clampedHeight = min(proposedHeight, maximumHeight)
        let frameWidth = proposedHeight > maximumHeight
            ? min(containerWidth, clampedHeight * aspectRatio)
            : containerWidth
        return CGSize(width: frameWidth, height: clampedHeight)
    }
}

struct PlaceCardSheet: View {
    let placeID: String
    let model: MapScreenModel?
    let onHide: (String, String) -> Void
    let onManageVisits: (String) -> Void
    let setNearbyPromptSuppressed: @MainActor (String, Bool) -> Bool
    let showHiddenMode: Bool

    @State private var sheetInstanceID = UUID().uuidString
    @State private var card: PlaceCardModel?
    @State private var isLoading = true
    @State private var actionError: String?
    @State private var showListPicker = false
    @State private var actionBarHeight: CGFloat = 0
    @State private var isPerformingAction = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let theme = MaterialTheme.snow

    private var appearance: PlaceCardAppearance {
        PlaceCardAppearance(theme: theme)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                cardContent
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, CGFloat(
                        PlaceCardOverlayMetrics.contentBottomPadding(
                            actionBarHeight: Double(actionBarHeight)
                        )
                    ))
            }
            .accessibilityIdentifier("place-card.instance.\(sheetInstanceID)")

            if let card {
                VStack(spacing: 0) {
                    placeCardBottomFade
                        .allowsHitTesting(false)
                    actionBar(card)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: PlaceCardActionBarHeightKey.self,
                                    value: proxy.size.height
                                )
                            }
                        )
                }
                .onPreferenceChange(PlaceCardActionBarHeightKey.self) { height in
                    actionBarHeight = height
                }
            }
        }
        .presentationDetents(cardDetents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(PlaceCardLayout.cardCornerRadius)
        .presentationBackground(appearance.cardBackground)
        .presentationBackgroundInteraction(
            .enabled(upThrough: dynamicTypeSize.isAccessibilitySize ? .large : .medium)
        )
        .task(id: placeID) {
            await loadCard()
        }
        .sheet(isPresented: $showListPicker) {
            ListPickerView(
                placeID: placeID,
                model: model,
                onChanged: { _ in
                    Task { await refreshCard() }
                }
            )
        }
        .task(id: placeID) {
            await observeImageChanges()
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let card {
                header
                Text(verbatim: card.name)
                    .font(Typography.font(for: .placeName))
                    .foregroundStyle(appearance.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("place-card.title")
                typeRow(card)
                photoSlot(card)
                if let blurb = card.blurb {
                    Text(verbatim: blurb)
                        .font(Typography.font(for: .body))
                        .foregroundStyle(appearance.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("place-card.description")
                }
                sourceArticleLink(card.sourceArticleLink)
                listChips(card.listNames)
                attributionText(card)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(verbatim: "Place unavailable")
                    .font(Typography.font(for: .label))
                Text(verbatim: placeID)
                    .font(Typography.font(for: .metadata))
                    .textSelection(.enabled)
            }
        }
    }

    private var cardDetents: Set<PresentationDetent> {
        Set(
            PlaceCardDetentPolicy.identifiers(
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            ).compactMap { identifier in
                switch identifier {
                case "medium":
                    return .medium
                case "large":
                    return .large
                default:
                    return nil
                }
            }
        )
    }

    var header: some View {
        HStack {
            Spacer()

            Menu {
                Button("Add to list") {
                    showListPicker = true
                }
                .accessibilityIdentifier("place-card.add-to-list")
            } label: {
                PlaceCardMoreIconGlyph()
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
            .accessibilityIdentifier("place-card.more")
        }
    }

    private var placeCardBottomFade: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: appearance.cardBackground.opacity(0), location: 0),
                Gradient.Stop(color: appearance.cardBackground, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: CGFloat(PlaceCardOverlayMetrics.fadeHeight))
    }

    @ViewBuilder
    private func sourceArticleLink(_ link: SourceArticleLink?) -> some View {
        if let link {
            Link(destination: link.url) {
                Text(verbatim: link.label)
                    .font(Typography.font(for: .button))
                    .foregroundStyle(appearance.linkText)
            }
            .accessibilityIdentifier("place-card.source-article")
            .accessibilityLabel(Text(verbatim: "\(link.sourceName) source article"))
        }
    }

    @ViewBuilder
    private func typeRow(_ card: PlaceCardModel) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(appearance.mediaBackground)
                .frame(
                    width: PlaceCardLayout.typeSwatchSide,
                    height: PlaceCardLayout.typeSwatchSide
                )
                .accessibilityHidden(true)
            Text(verbatim: categoryLabel(card.category))
                .font(Typography.font(for: .label))
                .foregroundStyle(appearance.secondaryText)
                .accessibilityIdentifier("place-card.type.label")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func photoSlot(_ card: PlaceCardModel) -> some View {
        if let photo = card.photo {
            PlaceCardPhotoSlot(photo: photo, model: model, appearance: appearance)
        }
    }

    @ViewBuilder
    private func listChips(_ names: [String]) -> some View {
        if !names.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    MaterialChip(
                        name,
                        state: .active,
                        theme: theme
                    ) {
                        showListPicker = true
                    }
                }
            }
            .accessibilityIdentifier("place-card.list-chips")
        }
    }

    @ViewBuilder
    private func attributionText(_ card: PlaceCardModel) -> some View {
        let parts = attributionParts(card)
        if !parts.isEmpty {
            Text(verbatim: parts.joined(separator: " / "))
                .font(Typography.font(for: .metadata))
                .foregroundStyle(appearance.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("place-card.attribution")
        }
    }

    @ViewBuilder
    private func actionBar(_ card: PlaceCardModel) -> some View {
        let slots = PlaceCardActionSlots(pinState: card.pinState).actions
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        VStack(alignment: .leading, spacing: 8) {
            if let actionError {
                Text(verbatim: actionError)
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(appearance.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("place-card.action-error")
            }

            layout {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, action in
                    actionButton(action, card: card)
                        .frame(maxWidth: .infinity)
                        .accessibilitySortPriority(10)
                }
            }
        }
        .disabled(isPerformingAction)
        .padding(.horizontal, PlaceCardLayout.actionBarHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(appearance.cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-card.action-bar")
        .accessibilitySortPriority(10)
    }

    @ViewBuilder
    private func actionButton(_ action: PlaceCardAction, card: PlaceCardModel) -> some View {
        switch action {
        case .save:
            saveButton(card)
        case .seen:
            Button {
                startAction { await setVisited(true, action: .seen) }
            } label: {
                actionLabel(action, isSaved: card.pinState.saved)
            }
            .modifier(PlaceCardActionStyleModifier(
                action: action,
                isSaved: card.pinState.saved,
                theme: theme
            ))
            .accessibilityIdentifier("place-card.visited")
            .accessibilityValue("Not seen")
        case .love:
            Button {
                startAction { await setLoved(true, action: .love) }
            } label: {
                actionLabel(action, isSaved: card.pinState.saved)
            }
            .modifier(PlaceCardActionStyleModifier(
                action: action,
                isSaved: card.pinState.saved,
                theme: theme
            ))
            .accessibilityIdentifier("place-card.loved")
            .accessibilityValue("Not loved")
        case .unlove:
            Button {
                startAction { await setLoved(false, action: .unlove) }
            } label: {
                actionLabel(action, isSaved: card.pinState.saved)
            }
            .modifier(PlaceCardActionStyleModifier(
                action: action,
                isSaved: card.pinState.saved,
                theme: theme
            ))
            .accessibilityIdentifier("place-card.loved")
            .accessibilityValue("Loved")
        case .hide:
            hideButton(card)
        case let .unsee(isEnabled):
            Button {
                startAction { await setVisited(false, action: action) }
            } label: {
                actionLabel(action, isSaved: card.pinState.saved)
            }
            .modifier(PlaceCardActionStyleModifier(
                action: action,
                isSaved: card.pinState.saved,
                theme: theme
            ))
            .accessibilityIdentifier("place-card.unsee")
            .accessibilityValue("Seen")
            .disabled(!isEnabled)
        case .unhide:
            unhideButton(card)
        }
    }

    private func saveButton(_ card: PlaceCardModel) -> some View {
        Button {
            showListPicker = true
        } label: {
            actionLabel(.save, isSaved: card.pinState.saved)
        }
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    showListPicker = true
                }
        )
        .modifier(PlaceCardActionStyleModifier(
            action: .save,
            isSaved: card.pinState.saved,
            theme: theme
        ))
        .accessibilityIdentifier("place-card.save")
        .accessibilityValue(card.pinState.saved ? "Saved" : "Not saved")
        .accessibilityHint(
            PlaceCardAction.save.accessibilityHint(isSaved: card.pinState.saved) ?? ""
        )
    }

    private func hideButton(_ card: PlaceCardModel) -> some View {
        Button {
            startAction { await setHidden(card) }
        } label: {
            actionLabel(.hide, isSaved: card.pinState.saved)
        }
        .modifier(PlaceCardActionStyleModifier(
            action: .hide,
            isSaved: card.pinState.saved,
            theme: theme
        ))
        .accessibilityIdentifier("place-card.hide")
        .accessibilityValue("Not hidden")
    }

    private func unhideButton(_ card: PlaceCardModel) -> some View {
        Button {
            startAction { await setHidden(false) }
        } label: {
            actionLabel(.unhide, isSaved: card.pinState.saved)
        }
        .modifier(PlaceCardActionStyleModifier(
            action: .unhide,
            isSaved: card.pinState.saved,
            theme: theme
        ))
        .accessibilityIdentifier("place-card.unhide")
        .accessibilityValue("Hidden")
    }

    @ViewBuilder
    private func actionLabel(_ action: PlaceCardAction, isSaved: Bool) -> some View {
        let presentation = PlaceCardActionAppearance.presentation(
            for: action,
            isSaved: isSaved
        )
        if let systemImage = presentation.systemImage {
            Label(
                presentation.title,
                systemImage: systemImage
            )
            .frame(maxWidth: .infinity)
        } else {
            Text(verbatim: presentation.title)
                .frame(maxWidth: .infinity)
        }
    }

    private func loadCard() async {
        await MainActor.run {
            card = nil
            actionError = nil
            isLoading = true
        }
        let nextCard = await model?.cardModel(for: placeID)
        await MainActor.run {
            card = nextCard
            isLoading = false
            if let nextCard {
                MakingTracksLog.flowEvent("place viewed", fields: [
                    .object("placeID", placeID),
                    .object("placeName", nextCard.name),
                    .public("source", "card"),
                ])
            }
        }
    }

    private func refreshCard() async {
        let nextCard = await model?.cardModel(for: placeID)
        await MainActor.run {
            card = nextCard
        }
    }

    private func observeImageChanges() async {
        guard let changes = model?.imageChanges else { return }
        for await ids in changes {
            guard !Task.isCancelled else { return }
            guard ids.contains(placeID) else { continue }
            await refreshCard()
        }
    }

    private func setVisited(_ visited: Bool, action: PlaceCardAction) async {
        if !visited, (await model?.visitCount(placeID: placeID) ?? 0) > 1 {
            // #217: Rob has not fixed the stale single-visit threshold yet, so
            // only the unambiguous multi-visit case routes to row selection here.
            await MainActor.run {
                isPerformingAction = false
                dismiss()
                onManageVisits(placeID)
            }
            return
        }
        await performAction(suppressingPromptFor: action) {
            try await model?.setVisited(placeID: placeID, visited: visited)
        }
    }

    private func setLoved(_ loved: Bool, action: PlaceCardAction) async {
        await performAction(suppressingPromptFor: action) {
            try await model?.setLoved(placeID: placeID, loved: loved)
        }
    }

    private func startAction(_ action: @escaping () async -> Void) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        Task {
            await action()
        }
    }

    private func setHidden(_ card: PlaceCardModel) async {
        let insertedNearbyPromptSuppression = await beginNearbyPromptSuppression(for: .hide)
        await MainActor.run {
            actionError = nil
        }
        do {
            try await model?.setHidden(placeID: placeID, hidden: true)
            await MainActor.run {
                isPerformingAction = false
                self.card = nil
                dismiss()
                onHide(placeID, card.name)
            }
        } catch {
            await rollbackNearbyPromptSuppressionIfNeeded(insertedNearbyPromptSuppression)
            await MainActor.run {
                isPerformingAction = false
                actionError = "Could not save that change."
            }
        }
    }

    private func setHidden(_ hidden: Bool) async {
        await performAction(suppressingPromptFor: hidden ? .hide : .unhide) {
            try await model?.setHidden(placeID: placeID, hidden: hidden)
        }
    }

    private func performAction(
        suppressingPromptFor nearbyPromptAction: PlaceCardAction? = nil,
        _ action: () async throws -> Void
    ) async {
        let insertedNearbyPromptSuppression = await beginNearbyPromptSuppression(
            for: nearbyPromptAction
        )
        do {
            try await action()
            await clearNearbyPromptSuppressionIfNeeded(for: nearbyPromptAction)
            await MainActor.run { actionError = nil }
            await refreshCard()
            await MainActor.run { isPerformingAction = false }
        } catch {
            await rollbackNearbyPromptSuppressionIfNeeded(insertedNearbyPromptSuppression)
            await MainActor.run {
                isPerformingAction = false
                actionError = "Could not save that change."
            }
        }
    }

    private func beginNearbyPromptSuppression(for action: PlaceCardAction?) async -> Bool {
        guard let action,
              NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: action)
        else { return false }
        return setNearbyPromptSuppressed(placeID, true)
    }

    private func clearNearbyPromptSuppressionIfNeeded(for action: PlaceCardAction?) async {
        guard let action,
              NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: action)
        else { return }
        _ = setNearbyPromptSuppressed(placeID, false)
    }

    private func rollbackNearbyPromptSuppressionIfNeeded(_ insertedSuppression: Bool) async {
        guard insertedSuppression else { return }
        // Correct while startAction serialises card actions; concurrent
        // suppressing actions would need per-action contribution tracking.
        _ = setNearbyPromptSuppressed(placeID, false)
    }

    private func categoryLabel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func attributionParts(_ card: PlaceCardModel) -> [String] {
        var parts: [String] = []
        if let photo = card.photo {
            parts.append(photo.attribution)
        }
        if !card.sourceNames.isEmpty {
            parts.append(card.sourceNames.joined(separator: " / "))
        }
        return parts
    }
}

private struct PlaceCardActionBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PlaceCardMoreIconGlyph: View {
    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Image(systemName: PlaceCardLayout.closeSystemImageName)
            .iconRole(.hero)
            .foregroundStyle(tokens.muted.swiftUIColor)
    }
}

struct PlaceCardMissingPhotoIconGlyph: View {
    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Image(systemName: "photo")
            .iconRole(.hero)
            .foregroundStyle(tokens.muted.swiftUIColor)
    }
}

struct PlaceCardPhotoSlot: View {
    let photo: PlaceCardPhoto
    let model: MapScreenModel?
    let appearance: PlaceCardAppearance

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var availableWidth: CGFloat = 0

    private var loadID: String {
        photo.thumbSHA256 ?? photo.accessibilityLabel
    }

    private var slotAccessibilityLabel: String {
        didFail && photo.thumbURL != nil ? "Photo unavailable" : photo.accessibilityLabel
    }

    private var slotHeight: CGFloat {
        slotSize.height
    }

    private var slotSize: CGSize {
        PlaceCardPhotoLayout.size(
            containerWidth: availableWidth > 0 ? availableWidth : 320,
            imageWidth: photo.width ?? image?.cgImage?.width,
            imageHeight: photo.height ?? image?.cgImage?.height
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: PlaceCardLayout.mediaCornerRadius,
                style: .continuous
            )
            .fill(appearance.mediaBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            } else if photo.thumbURL == nil || didFail {
                PlaceCardMissingPhotoIconGlyph()
                    .accessibilityHidden(true)
            } else if !didFail {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: slotSize.width, height: slotHeight)
        .clipShape(
            RoundedRectangle(
                cornerRadius: PlaceCardLayout.mediaCornerRadius,
                style: .continuous
            )
        )
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        availableWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        availableWidth = width
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slotAccessibilityLabel)
        .accessibilityIdentifier("place-card.photo")
        .task(id: loadID) {
            await loadPhoto(expectedLoadID: loadID)
        }
    }

    private func loadPhoto(expectedLoadID: String) async {
        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard !Task.isCancelled, loadID == expectedLoadID else { return }
            image = nil
            didFail = false
        }
        guard photo.thumbURL != nil else { return }
        guard let data = await model?.photoData(for: photo) else {
            await MainActor.run {
                guard !Task.isCancelled, loadID == expectedLoadID else { return }
                didFail = true
            }
            return
        }
        await MainActor.run {
            guard !Task.isCancelled, loadID == expectedLoadID else { return }
            if Self.isSafeDecodedImage(data), let decoded = UIImage(data: data) {
                image = decoded
            } else {
                didFail = true
            }
        }
    }

    private static func isSafeDecodedImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0
        else { return false }
        // Tunable guard shared with the card contract: enough for thumbnails,
        // bounded against decode bombs.
        return width <= 16_000_000 / height
    }
}
