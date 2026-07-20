import Foundation

public struct TrackLineStyle: Equatable, Sendable {
    public let cap: String
    public let join: String
    public let color: String
    public let opacity: Double
    public let width: Double
    public let dashPattern: [Double]

    public init(
        cap: String,
        join: String,
        color: String,
        opacity: Double,
        width: Double,
        dashPattern: [Double]
    ) {
        self.cap = cap
        self.join = join
        self.color = color
        self.opacity = opacity
        self.width = width
        self.dashPattern = dashPattern
    }
}
