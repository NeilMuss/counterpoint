import Foundation

public struct DebugReference: Codable, Equatable {
    public var svgPathD: String
    public var transform: String?
    public var opacity: Double?

    public init(svgPathD: String, transform: String? = nil, opacity: Double? = nil) {
        self.svgPathD = svgPathD
        self.transform = transform
        self.opacity = opacity
    }
}
