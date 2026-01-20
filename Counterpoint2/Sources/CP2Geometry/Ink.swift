import Foundation

public struct InkPoint: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct InkLine: Codable, Equatable {
    public var p0: InkPoint
    public var p1: InkPoint

    public init(p0: InkPoint, p1: InkPoint) {
        self.p0 = p0
        self.p1 = p1
    }
}

public struct InkCubic: Codable, Equatable {
    public var p0: InkPoint
    public var p1: InkPoint
    public var p2: InkPoint
    public var p3: InkPoint

    public init(p0: InkPoint, p1: InkPoint, p2: InkPoint, p3: InkPoint) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }
}

public enum InkPrimitive: Codable, Equatable {
    case line(InkLine)
    case cubic(InkCubic)

    private enum CodingKeys: String, CodingKey {
        case type
        case p0
        case p1
        case p2
        case p3
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type.lowercased() {
        case "line":
            let p0 = try container.decode(InkPoint.self, forKey: .p0)
            let p1 = try container.decode(InkPoint.self, forKey: .p1)
            self = .line(InkLine(p0: p0, p1: p1))
        case "cubic":
            let p0 = try container.decode(InkPoint.self, forKey: .p0)
            let p1 = try container.decode(InkPoint.self, forKey: .p1)
            let p2 = try container.decode(InkPoint.self, forKey: .p2)
            let p3 = try container.decode(InkPoint.self, forKey: .p3)
            self = .cubic(InkCubic(p0: p0, p1: p1, p2: p2, p3: p3))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown ink primitive type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .line(let line):
            try container.encode("line", forKey: .type)
            try container.encode(line.p0, forKey: .p0)
            try container.encode(line.p1, forKey: .p1)
        case .cubic(let cubic):
            try container.encode("cubic", forKey: .type)
            try container.encode(cubic.p0, forKey: .p0)
            try container.encode(cubic.p1, forKey: .p1)
            try container.encode(cubic.p2, forKey: .p2)
            try container.encode(cubic.p3, forKey: .p3)
        }
    }
}

public struct Ink: Codable, Equatable {
    public var stem: InkPrimitive?

    public init(stem: InkPrimitive?) {
        self.stem = stem
    }
}
