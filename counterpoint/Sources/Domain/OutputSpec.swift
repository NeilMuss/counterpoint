import Foundation

public enum OutputCoordinateMode: String, Codable {
    case raw
    case normalized
}

public struct OutputSpec: Codable, Equatable {
    public var coordinateMode: OutputCoordinateMode

    public init(coordinateMode: OutputCoordinateMode = .normalized) {
        self.coordinateMode = coordinateMode
    }
}
