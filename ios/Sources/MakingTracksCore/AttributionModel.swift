import Foundation
import MakingTracksTiles

public struct CreditLine: Sendable, Equatable {
    public let source: String
    public let license: String
    public let text: String
}

public struct AttributionModel: Sendable, Equatable {
    public let credits: [CreditLine]

    public init(_ attribution: [Attribution]) {
        credits = attribution.map {
            CreditLine(source: $0.source, license: $0.license, text: $0.text)
        }
    }

    public func sourceNames(for refs: [String]) -> [String] {
        SourceNames.names(from: refs)
    }
}
