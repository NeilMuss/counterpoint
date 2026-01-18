import Foundation

public enum OutputCoordinateMode: String, Codable {
    case raw
    case normalized
}

public enum StrokeOutlineMethod: String, Codable {
    case union
    case rails
}

public struct OutputSpec: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case coordinateMode
        case outlineMethod
    }

    public var coordinateMode: OutputCoordinateMode
    public var outlineMethod: StrokeOutlineMethod

    public init(coordinateMode: OutputCoordinateMode = .normalized, outlineMethod: StrokeOutlineMethod = .union) {
        self.coordinateMode = coordinateMode
        self.outlineMethod = outlineMethod
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coordinateMode = try container.decodeIfPresent(OutputCoordinateMode.self, forKey: .coordinateMode) ?? .normalized
        outlineMethod = try container.decodeIfPresent(StrokeOutlineMethod.self, forKey: .outlineMethod) ?? .union
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinateMode, forKey: .coordinateMode)
        try container.encode(outlineMethod, forKey: .outlineMethod)
    }
}
