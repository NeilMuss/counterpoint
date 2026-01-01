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

public enum CounterpointShape: Codable, Equatable {
    case rectangle
    case ellipse(segments: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case segments
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "ellipse":
                let segments = try container.decodeIfPresent(Int.self, forKey: .segments) ?? 24
                self = .ellipse(segments: segments)
            default:
                self = .rectangle
            }
            return
        }
        let single = try decoder.singleValueContainer()
        let type = (try? single.decode(String.self)) ?? "rectangle"
        switch type {
        case "ellipse":
            self = .ellipse(segments: 24)
        default:
            self = .rectangle
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rectangle:
            try container.encode("rectangle", forKey: .type)
        case .ellipse(let segments):
            try container.encode("ellipse", forKey: .type)
            try container.encode(segments, forKey: .segments)
        }
    }
}

public struct SamplingSpec: Codable, Equatable {
    public var baseSpacing: Double
    public var flatnessTolerance: Double
    public var rotationThresholdDegrees: Double
    public var minimumSpacing: Double
    public var maxSamples: Int

    private enum CodingKeys: String, CodingKey {
        case baseSpacing
        case flatnessTolerance
        case rotationThresholdDegrees
        case minimumSpacing
        case maxSamples
    }

    public init(
        baseSpacing: Double = 2.0,
        flatnessTolerance: Double = 0.5,
        rotationThresholdDegrees: Double = 5.0,
        minimumSpacing: Double = 1.0e-4,
        maxSamples: Int = 256
    ) {
        self.baseSpacing = baseSpacing
        self.flatnessTolerance = flatnessTolerance
        self.rotationThresholdDegrees = rotationThresholdDegrees
        self.minimumSpacing = minimumSpacing
        self.maxSamples = maxSamples
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseSpacing = try container.decodeIfPresent(Double.self, forKey: .baseSpacing) ?? 2.0
        flatnessTolerance = try container.decodeIfPresent(Double.self, forKey: .flatnessTolerance) ?? 0.5
        rotationThresholdDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationThresholdDegrees) ?? 5.0
        minimumSpacing = try container.decodeIfPresent(Double.self, forKey: .minimumSpacing) ?? 1.0e-4
        maxSamples = try container.decodeIfPresent(Int.self, forKey: .maxSamples) ?? 256
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseSpacing, forKey: .baseSpacing)
        try container.encode(flatnessTolerance, forKey: .flatnessTolerance)
        try container.encode(rotationThresholdDegrees, forKey: .rotationThresholdDegrees)
        try container.encode(minimumSpacing, forKey: .minimumSpacing)
        try container.encode(maxSamples, forKey: .maxSamples)
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
        case counterpointShape
        case sampling
        case samplingPolicy
    }
    public var path: BezierPath
    public var width: ParamTrack
    public var height: ParamTrack
    public var theta: ParamTrack
    public var angleMode: AngleMode
    public var capStyle: CapStyle
    public var joinStyle: JoinStyle
    public var counterpointShape: CounterpointShape
    public var sampling: SamplingSpec
    public var samplingPolicy: SamplingPolicy?

    public init(
        path: BezierPath,
        width: ParamTrack,
        height: ParamTrack,
        theta: ParamTrack,
        angleMode: AngleMode,
        capStyle: CapStyle = .butt,
        joinStyle: JoinStyle = .bevel,
        counterpointShape: CounterpointShape = .rectangle,
        sampling: SamplingSpec,
        samplingPolicy: SamplingPolicy? = nil
    ) {
        self.path = path
        self.width = width
        self.height = height
        self.theta = theta
        self.angleMode = angleMode
        self.capStyle = capStyle
        self.joinStyle = joinStyle
        self.counterpointShape = counterpointShape
        self.sampling = sampling
        self.samplingPolicy = samplingPolicy
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
        counterpointShape = try container.decodeIfPresent(CounterpointShape.self, forKey: .counterpointShape) ?? .rectangle
        sampling = try container.decode(SamplingSpec.self, forKey: .sampling)
        samplingPolicy = try container.decodeIfPresent(SamplingPolicy.self, forKey: .samplingPolicy)
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
        try container.encode(counterpointShape, forKey: .counterpointShape)
        try container.encode(sampling, forKey: .sampling)
        if let samplingPolicy {
            try container.encode(samplingPolicy, forKey: .samplingPolicy)
        }
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
