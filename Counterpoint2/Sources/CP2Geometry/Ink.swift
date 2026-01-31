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

public enum InkSegment: Codable, Equatable {
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
                debugDescription: "Unknown ink segment type: \(type)"
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

public struct InkPath: Codable, Equatable {
    public var segments: [InkSegment]

    public init(segments: [InkSegment]) {
        self.segments = segments
    }
}

public struct Heartline: Codable, Equatable {
    public var parts: [String]
    public var allowGaps: Bool?

    public init(parts: [String], allowGaps: Bool? = nil) {
        self.parts = parts
        self.allowGaps = allowGaps
    }
}

public enum InkPrimitive: Codable, Equatable {
    case line(InkLine)
    case cubic(InkCubic)
    case path(InkPath)
    case heartline(Heartline)

    private enum CodingKeys: String, CodingKey {
        case type
        case p0
        case p1
        case p2
        case p3
        case segments
        case parts
        case allowGaps
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
        case "path":
            let segments = try container.decode([InkSegment].self, forKey: .segments)
            self = .path(InkPath(segments: segments))
        case "heartline":
            let parts = try container.decode([String].self, forKey: .parts)
            let allowGaps = try container.decodeIfPresent(Bool.self, forKey: .allowGaps)
            self = .heartline(Heartline(parts: parts, allowGaps: allowGaps))
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
        case .path(let path):
            try container.encode("path", forKey: .type)
            try container.encode(path.segments, forKey: .segments)
        case .heartline(let heartline):
            try container.encode("heartline", forKey: .type)
            try container.encode(heartline.parts, forKey: .parts)
            try container.encodeIfPresent(heartline.allowGaps, forKey: .allowGaps)
        }
    }
}

public struct Ink: Codable, Equatable {
    public var stem: InkPrimitive?
    public var entries: [String: InkPrimitive]

    public init(stem: InkPrimitive?) {
        self.stem = stem
        if let stem {
            self.entries = ["stem": stem]
        } else {
            self.entries = [:]
        }
    }

    public init(stem: InkPrimitive?, entries: [String: InkPrimitive]) {
        self.stem = stem
        self.entries = entries
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var map: [String: InkPrimitive] = [:]
        for key in container.allKeys {
            let primitive = try container.decode(InkPrimitive.self, forKey: key)
            map[key.stringValue] = primitive
        }
        self.entries = map
        self.stem = map["stem"]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for key in entries.keys.sorted() {
            if let value = entries[key], let codingKey = DynamicKey(stringValue: key) {
                try container.encode(value, forKey: codingKey)
            }
        }
    }
}

public struct CounterSet: Codable, Equatable {
    public var entries: [String: CounterPrimitive]

    public init(entries: [String: CounterPrimitive]) {
        self.entries = entries
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var map: [String: CounterPrimitive] = [:]
        for key in container.allKeys {
            let primitive = try container.decode(CounterPrimitive.self, forKey: key)
            map[key.stringValue] = primitive
        }
        self.entries = map
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for key in entries.keys.sorted() {
            if let value = entries[key], let codingKey = DynamicKey(stringValue: key) {
                try container.encode(value, forKey: codingKey)
            }
        }
    }
}

public struct CounterOffset: Codable, Equatable {
    public var t: Double
    public var n: Double

    public init(t: Double, n: Double) {
        self.t = t
        self.n = n
    }
}

public struct CounterAnchor: Codable, Equatable {
    public var stroke: String?
    public var ink: String?
    public var t: Double

    public init(stroke: String? = nil, ink: String? = nil, t: Double) {
        self.stroke = stroke
        self.ink = ink
        self.t = t
    }

    private enum CodingKeys: String, CodingKey {
        case stroke
        case ink
        case inkPath
        case t
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stroke = try container.decodeIfPresent(String.self, forKey: .stroke)
        self.ink = try container.decodeIfPresent(String.self, forKey: .ink)
        if self.ink == nil {
            self.ink = try container.decodeIfPresent(String.self, forKey: .inkPath)
        }
        self.t = try container.decode(Double.self, forKey: .t)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(stroke, forKey: .stroke)
        if stroke == nil {
            try container.encodeIfPresent(ink, forKey: .ink)
        }
        try container.encode(t, forKey: .t)
    }
}

public struct CounterEllipse: Codable, Equatable {
    public var at: CounterAnchor
    public var rx: Double
    public var ry: Double
    public var rotateDeg: Double
    public var offset: CounterOffset?

    public init(at: CounterAnchor, rx: Double, ry: Double, rotateDeg: Double, offset: CounterOffset? = nil) {
        self.at = at
        self.rx = rx
        self.ry = ry
        self.rotateDeg = rotateDeg
        self.offset = offset
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case at
        case rx
        case ry
        case rotateDeg
        case offset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.at = try container.decode(CounterAnchor.self, forKey: .at)
        self.rx = try container.decode(Double.self, forKey: .rx)
        self.ry = try container.decode(Double.self, forKey: .ry)
        self.rotateDeg = try container.decodeIfPresent(Double.self, forKey: .rotateDeg) ?? 0.0
        self.offset = try container.decodeIfPresent(CounterOffset.self, forKey: .offset)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("ellipse", forKey: .type)
        try container.encode(at, forKey: .at)
        try container.encode(rx, forKey: .rx)
        try container.encode(ry, forKey: .ry)
        if rotateDeg != 0.0 { try container.encode(rotateDeg, forKey: .rotateDeg) }
        try container.encodeIfPresent(offset, forKey: .offset)
    }
}

public enum CounterPrimitive: Codable, Equatable {
    case ink(InkPrimitive)
    case ellipse(CounterEllipse)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type.lowercased() {
        case "ellipse":
            self = .ellipse(try CounterEllipse(from: decoder))
        case "line", "cubic", "path", "heartline":
            self = .ink(try InkPrimitive(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown counter primitive type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .ellipse(let ellipse):
            try ellipse.encode(to: encoder)
        case .ink(let primitive):
            try primitive.encode(to: encoder)
        }
    }
}
