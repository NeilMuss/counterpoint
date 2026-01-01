import Foundation

public enum AngleMode: String, Codable {
    case absolute
    case tangentRelative
}

public enum CapStyle: String, Codable {
    case butt
    case square
    case round
}

public enum JoinStyle: Codable, Equatable {
    case bevel
    case miter(miterLimit: Double)
    case round

    private enum CodingKeys: String, CodingKey {
        case type
        case miterLimit
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "miter":
                let limit = try container.decodeIfPresent(Double.self, forKey: .miterLimit) ?? 4.0
                self = .miter(miterLimit: limit)
            case "round":
                self = .round
            default:
                self = .bevel
            }
            return
        }
        let single = try decoder.singleValueContainer()
        let type = (try? single.decode(String.self)) ?? "bevel"
        switch type {
        case "miter":
            self = .miter(miterLimit: 4.0)
        case "round":
            self = .round
        default:
            self = .bevel
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bevel:
            try container.encode("bevel", forKey: .type)
        case .round:
            try container.encode("round", forKey: .type)
        case .miter(let limit):
            try container.encode("miter", forKey: .type)
            try container.encode(limit, forKey: .miterLimit)
        }
    }
}

public struct SamplingSpec: Codable, Equatable {
    public var baseSpacing: Double
    public var flatnessTolerance: Double
    public var rotationThresholdDegrees: Double
    public var minimumSpacing: Double

    public init(
        baseSpacing: Double = 2.0,
        flatnessTolerance: Double = 0.5,
        rotationThresholdDegrees: Double = 5.0,
        minimumSpacing: Double = 1.0e-4
    ) {
        self.baseSpacing = baseSpacing
        self.flatnessTolerance = flatnessTolerance
        self.rotationThresholdDegrees = rotationThresholdDegrees
        self.minimumSpacing = minimumSpacing
    }

    public var rotationThresholdRadians: Double {
        rotationThresholdDegrees * .pi / 180.0
    }
}

public struct StrokeSpec: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case path
        case width
        case height
        case theta
        case angleMode
        case capStyle
        case joinStyle
        case sampling
    }
    public var path: BezierPath
    public var width: ParamTrack
    public var height: ParamTrack
    public var theta: ParamTrack
    public var angleMode: AngleMode
    public var capStyle: CapStyle
    public var joinStyle: JoinStyle
    public var sampling: SamplingSpec

    public init(
        path: BezierPath,
        width: ParamTrack,
        height: ParamTrack,
        theta: ParamTrack,
        angleMode: AngleMode,
        capStyle: CapStyle = .butt,
        joinStyle: JoinStyle = .bevel,
        sampling: SamplingSpec
    ) {
        self.path = path
        self.width = width
        self.height = height
        self.theta = theta
        self.angleMode = angleMode
        self.capStyle = capStyle
        self.joinStyle = joinStyle
        self.sampling = sampling
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(BezierPath.self, forKey: .path)
        width = try container.decode(ParamTrack.self, forKey: .width)
        height = try container.decode(ParamTrack.self, forKey: .height)
        theta = try container.decode(ParamTrack.self, forKey: .theta)
        angleMode = try container.decode(AngleMode.self, forKey: .angleMode)
        capStyle = try container.decodeIfPresent(CapStyle.self, forKey: .capStyle) ?? .butt
        joinStyle = try container.decodeIfPresent(JoinStyle.self, forKey: .joinStyle) ?? .bevel
        sampling = try container.decode(SamplingSpec.self, forKey: .sampling)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(theta, forKey: .theta)
        try container.encode(angleMode, forKey: .angleMode)
        try container.encode(capStyle, forKey: .capStyle)
        try container.encode(joinStyle, forKey: .joinStyle)
        try container.encode(sampling, forKey: .sampling)
    }
}

public struct Sample: Codable, Equatable {
    public var t: Double
    public var point: Point
    public var tangentAngle: Double
    public var width: Double
    public var height: Double
    public var theta: Double
    public var effectiveRotation: Double

    public init(
        t: Double,
        point: Point,
        tangentAngle: Double,
        width: Double,
        height: Double,
        theta: Double,
        effectiveRotation: Double
    ) {
        self.t = t
        self.point = point
        self.tangentAngle = tangentAngle
        self.width = width
        self.height = height
        self.theta = theta
        self.effectiveRotation = effectiveRotation
    }
}

public protocol StrokeOutlining {
    func outline(spec: StrokeSpec) throws -> PolygonSet
}

public protocol PolygonUnioning {
    func union(subjectRings: [Ring]) throws -> PolygonSet
}
