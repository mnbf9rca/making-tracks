import SwiftUI

struct MaterialProgressPresentation: Equatable {
    let fraction: Double?
    let visibleCount: String?
    let accessibilityValue: String
}

struct MaterialProgressAppearance: Equatable {
    let fill: MaterialColor
    let track: MaterialColor
    let count: MaterialColor
    let barHeight: CGFloat
}

struct MaterialProgressRenderConfiguration: Equatable {
    let appearance: MaterialProgressAppearance
    let presentation: MaterialProgressPresentation
    let accessibilityLabel: String
}

public enum MaterialProgressState: Hashable, Sendable {
    case count(completed: Int, total: Int)
    case percentage(Int)
    case indeterminate

    var presentation: MaterialProgressPresentation {
        presentation(countSuffix: nil)
    }

    func presentation(countSuffix: String?) -> MaterialProgressPresentation {
        switch self {
        case let .count(completed, total):
            let clampedTotal = max(total, 0)
            let clampedCompleted = min(max(completed, 0), clampedTotal)
            let clampedCount = "\(clampedCompleted) of \(clampedTotal)"
            let count = if let countSuffix, !countSuffix.isEmpty {
                "\(clampedCount) \(countSuffix)"
            } else {
                clampedCount
            }
            let fraction = clampedTotal == 0
                ? 0
                : Double(clampedCompleted) / Double(clampedTotal)

            return MaterialProgressPresentation(
                fraction: fraction,
                visibleCount: count,
                accessibilityValue: count
            )
        case let .percentage(value):
            let clampedValue = min(max(value, 0), 100)
            let percentage = "\(clampedValue)%"

            return MaterialProgressPresentation(
                fraction: Double(clampedValue) / 100,
                visibleCount: percentage,
                accessibilityValue: percentage
            )
        case .indeterminate:
            return MaterialProgressPresentation(
                fraction: nil,
                visibleCount: nil,
                accessibilityValue: "In progress"
            )
        }
    }
}

public struct MaterialProgress<LeadingHeader: View>: View {
    private let leadingHeader: LeadingHeader
    let renderConfiguration: MaterialProgressRenderConfiguration

    public init(
        state: MaterialProgressState,
        accessibilityLabel: String = "Progress",
        countSuffix: String? = nil,
        theme: MaterialTheme = .snow,
        @ViewBuilder leadingHeader: () -> LeadingHeader
    ) {
        self.leadingHeader = leadingHeader()
        renderConfiguration = MaterialProgressRenderConfiguration(
            appearance: MaterialProgressAppearance(
                fill: theme.tokens.accent,
                track: theme.tokens.hairline,
                count: theme.tokens.muted,
                barHeight: 3
            ),
            presentation: state.presentation(countSuffix: countSuffix),
            accessibilityLabel: accessibilityLabel
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let visibleCount = renderConfiguration.presentation.visibleCount {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    leadingHeader
                    Spacer(minLength: 8)
                    Text(verbatim: visibleCount)
                        .foregroundStyle(
                            renderConfiguration.appearance.count.swiftUIColor
                        )
                }
            }

            progressBar
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(renderConfiguration.accessibilityLabel)
        .accessibilityValue(renderConfiguration.presentation.accessibilityValue)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(renderConfiguration.appearance.track.swiftUIColor)

                Capsule()
                    .fill(renderConfiguration.appearance.fill.swiftUIColor)
                    .frame(width: fillWidth(in: geometry.size.width))
            }
        }
        .frame(height: renderConfiguration.appearance.barHeight)
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        if let fraction = renderConfiguration.presentation.fraction {
            return width * fraction
        }

        return min(width, 32)
    }
}

public extension MaterialProgress where LeadingHeader == EmptyView {
    init(
        state: MaterialProgressState,
        accessibilityLabel: String = "Progress",
        countSuffix: String? = nil,
        theme: MaterialTheme = .snow
    ) {
        self.init(
            state: state,
            accessibilityLabel: accessibilityLabel,
            countSuffix: countSuffix,
            theme: theme
        ) {
            EmptyView()
        }
    }
}
