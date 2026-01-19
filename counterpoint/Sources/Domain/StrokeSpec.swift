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
        let type = (try? single.decode(String.self)) ?? "round"
        switch type {
        case "miter":
            self = .miter(miterLimit: 4.0)
        case "round":
            self = .round
        default:
            self = .round
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
    public enum Mode: String, Codable {
        case adaptive
        case keyframeGrid
    }

    public var mode: Mode
    public var baseSpacing: Double
    public var maxSpacing: Double?
    public var keyframeDensity: Int
    public var flatnessTolerance: Double
    public var rotationThresholdDegrees: Double
    public var minimumSpacing: Double
    public var maxSamples: Int

    private enum CodingKeys: String, CodingKey {
        case mode
        case baseSpacing
        case maxSpacing
        case keyframeDensity
        case flatnessTolerance
        case rotationThresholdDegrees
        case minimumSpacing
        case maxSamples
    }

    public init(
        mode: Mode = .adaptive,
        baseSpacing: Double = 2.0,
        maxSpacing: Double? = nil,
        keyframeDensity: Int = 1,
        flatnessTolerance: Double = 0.5,
        rotationThresholdDegrees: Double = 5.0,
        minimumSpacing: Double = 1.0e-4,
        maxSamples: Int = 256
    ) {
        self.mode = mode
        self.baseSpacing = baseSpacing
        self.maxSpacing = maxSpacing
        self.keyframeDensity = keyframeDensity
        self.flatnessTolerance = flatnessTolerance
        self.rotationThresholdDegrees = rotationThresholdDegrees
        self.minimumSpacing = minimumSpacing
        self.maxSamples = maxSamples
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .adaptive
        baseSpacing = try container.decodeIfPresent(Double.self, forKey: .baseSpacing) ?? 2.0
        maxSpacing = try container.decodeIfPresent(Double.self, forKey: .maxSpacing)
        keyframeDensity = try container.decodeIfPresent(Int.self, forKey: .keyframeDensity) ?? 1
        flatnessTolerance = try container.decodeIfPresent(Double.self, forKey: .flatnessTolerance) ?? 0.5
        rotationThresholdDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationThresholdDegrees) ?? 5.0
        minimumSpacing = try container.decodeIfPresent(Double.self, forKey: .minimumSpacing) ?? 1.0e-4
        maxSamples = try container.decodeIfPresent(Int.self, forKey: .maxSamples) ?? 256
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(baseSpacing, forKey: .baseSpacing)
        if let maxSpacing {
            try container.encode(maxSpacing, forKey: .maxSpacing)
        }
        try container.encode(keyframeDensity, forKey: .keyframeDensity)
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
        case offset
        case alpha
        case angleMode
        case relativeAngleOffset
        case capStyle
        case joinStyle
        case counterpointShape
        case sampling
        case samplingPolicy
        case debugReference
        case backgroundGlyph
        case output
    }
    public var path: BezierPath
    public var width: ParamTrack
    public var height: ParamTrack
    public var theta: ParamTrack
    public var offset: ParamTrack?
    public var alpha: ParamTrack?
    public var angleMode: AngleMode
    public var relativeAngleOffset: Double?
    public var capStyle: CapStyle
    public var joinStyle: JoinStyle
    public var counterpointShape: CounterpointShape
    public var sampling: SamplingSpec
    public var samplingPolicy: SamplingPolicy?
    public var debugReference: DebugReference?
    public var backgroundGlyph: BackgroundGlyph?
    public var output: OutputSpec?

    public init(
        path: BezierPath,
        width: ParamTrack,
        height: ParamTrack,
        theta: ParamTrack,
        offset: ParamTrack? = nil,
        alpha: ParamTrack? = nil,
        angleMode: AngleMode,
        relativeAngleOffset: Double? = nil,
        capStyle: CapStyle = .butt,
        joinStyle: JoinStyle = .round,
        counterpointShape: CounterpointShape = .rectangle,
        sampling: SamplingSpec,
        samplingPolicy: SamplingPolicy? = nil,
        debugReference: DebugReference? = nil,
        backgroundGlyph: BackgroundGlyph? = nil,
        output: OutputSpec? = nil
    ) {
        self.path = path
        self.width = width
        self.height = height
        self.theta = theta
        self.offset = offset
        self.alpha = alpha
        self.angleMode = angleMode
        self.relativeAngleOffset = relativeAngleOffset
        self.capStyle = capStyle
        self.joinStyle = joinStyle
        self.counterpointShape = counterpointShape
        self.sampling = sampling
        self.samplingPolicy = samplingPolicy
        self.debugReference = debugReference
        self.backgroundGlyph = backgroundGlyph
        self.output = output
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(BezierPath.self, forKey: .path)
        width = try container.decode(ParamTrack.self, forKey: .width)
        height = try container.decode(ParamTrack.self, forKey: .height)
        theta = try container.decode(ParamTrack.self, forKey: .theta)
        offset = try container.decodeIfPresent(ParamTrack.self, forKey: .offset)
        alpha = try container.decodeIfPresent(ParamTrack.self, forKey: .alpha)
        angleMode = try container.decode(AngleMode.self, forKey: .angleMode)
        relativeAngleOffset = try container.decodeIfPresent(Double.self, forKey: .relativeAngleOffset)
        capStyle = try container.decodeIfPresent(CapStyle.self, forKey: .capStyle) ?? .butt
        joinStyle = try container.decodeIfPresent(JoinStyle.self, forKey: .joinStyle) ?? .round
        counterpointShape = try container.decodeIfPresent(CounterpointShape.self, forKey: .counterpointShape) ?? .rectangle
        sampling = try container.decode(SamplingSpec.self, forKey: .sampling)
        samplingPolicy = try container.decodeIfPresent(SamplingPolicy.self, forKey: .samplingPolicy)
        debugReference = try container.decodeIfPresent(DebugReference.self, forKey: .debugReference)
        backgroundGlyph = try container.decodeIfPresent(BackgroundGlyph.self, forKey: .backgroundGlyph)
        output = try container.decodeIfPresent(OutputSpec.self, forKey: .output)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(theta, forKey: .theta)
        if let offset {
            try container.encode(offset, forKey: .offset)
        }
        if let alpha {
            try container.encode(alpha, forKey: .alpha)
        }
        try container.encode(angleMode, forKey: .angleMode)
        if let relativeAngleOffset {
            try container.encode(relativeAngleOffset, forKey: .relativeAngleOffset)
        }
        try container.encode(capStyle, forKey: .capStyle)
        try container.encode(joinStyle, forKey: .joinStyle)
        try container.encode(counterpointShape, forKey: .counterpointShape)
        try container.encode(sampling, forKey: .sampling)
        if let samplingPolicy {
            try container.encode(samplingPolicy, forKey: .samplingPolicy)
        }
        if let debugReference {
            try container.encode(debugReference, forKey: .debugReference)
        }
        if let backgroundGlyph {
            try container.encode(backgroundGlyph, forKey: .backgroundGlyph)
        }
        if let output {
            try container.encode(output, forKey: .output)
        }
    }
}

public struct Sample: Codable, Equatable {
    public var uGeom: Double
    public var uGrid: Double
    public var t: Double
    public var point: Point
    public var tangentAngle: Double
    public var width: Double
    public var height: Double
    public var theta: Double
    public var effectiveRotation: Double
    public var alpha: Double

    public init(
        uGeom: Double,
        uGrid: Double,
        t: Double,
        point: Point,
        tangentAngle: Double,
        width: Double,
        height: Double,
        theta: Double,
        effectiveRotation: Double,
        alpha: Double
    ) {
        self.uGeom = uGeom
        self.uGrid = uGrid
        self.t = t
        self.point = point
        self.tangentAngle = tangentAngle
        self.width = width
        self.height = height
        self.theta = theta
        self.effectiveRotation = effectiveRotation
        self.alpha = alpha
    }
}

public protocol StrokeOutlining {
    func outline(spec: StrokeSpec) throws -> PolygonSet
}

public protocol PolygonUnioning {
    func union(subjectRings: [Ring]) throws -> PolygonSet
}
