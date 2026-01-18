import Foundation

public struct SamplingPolicy: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case flattenTolerance
        case envelopeTolerance
        case railTolerance
        case railChordTolerance
        case railMaxSegmentLength
        case railMaxTurnAngleDegrees
        case maxSamples
        case maxRecursionDepth
        case minParamStep
        case rotationThresholdDegrees
        case turnThresholdDegrees
        case widthChangeMin
        case widthChangeFactor
    }
    public var flattenTolerance: Double
    public var envelopeTolerance: Double
    public var railTolerance: Double
    public var railChordTolerance: Double
    public var railMaxSegmentLength: Double
    public var railMaxTurnAngleDegrees: Double
    public var maxSamples: Int
    public var maxRecursionDepth: Int
    public var minParamStep: Double
    public var rotationThresholdDegrees: Double
    public var turnThresholdDegrees: Double
    public var widthChangeMin: Double
    public var widthChangeFactor: Double

    public init(
        flattenTolerance: Double,
        envelopeTolerance: Double,
        railTolerance: Double = 0.4,
        railChordTolerance: Double = 0.25,
        railMaxSegmentLength: Double = 1.0,
        railMaxTurnAngleDegrees: Double = 1.0,
        maxSamples: Int,
        maxRecursionDepth: Int,
        minParamStep: Double,
        rotationThresholdDegrees: Double = 2.5,
        turnThresholdDegrees: Double = 0.75,
        widthChangeMin: Double = 2.0,
        widthChangeFactor: Double = 0.04
    ) {
        self.flattenTolerance = flattenTolerance
        self.envelopeTolerance = envelopeTolerance
        self.railTolerance = railTolerance
        self.railChordTolerance = railChordTolerance
        self.railMaxSegmentLength = railMaxSegmentLength
        self.railMaxTurnAngleDegrees = railMaxTurnAngleDegrees
        self.maxSamples = maxSamples
        self.maxRecursionDepth = maxRecursionDepth
        self.minParamStep = minParamStep
        self.rotationThresholdDegrees = rotationThresholdDegrees
        self.turnThresholdDegrees = turnThresholdDegrees
        self.widthChangeMin = widthChangeMin
        self.widthChangeFactor = widthChangeFactor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flattenTolerance = try container.decode(Double.self, forKey: .flattenTolerance)
        envelopeTolerance = try container.decode(Double.self, forKey: .envelopeTolerance)
        railTolerance = try container.decodeIfPresent(Double.self, forKey: .railTolerance) ?? 0.4
        railChordTolerance = try container.decodeIfPresent(Double.self, forKey: .railChordTolerance) ?? 0.25
        railMaxSegmentLength = try container.decodeIfPresent(Double.self, forKey: .railMaxSegmentLength) ?? 1.0
        railMaxTurnAngleDegrees = try container.decodeIfPresent(Double.self, forKey: .railMaxTurnAngleDegrees) ?? 1.0
        maxSamples = try container.decode(Int.self, forKey: .maxSamples)
        maxRecursionDepth = try container.decode(Int.self, forKey: .maxRecursionDepth)
        minParamStep = try container.decode(Double.self, forKey: .minParamStep)
        rotationThresholdDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationThresholdDegrees) ?? 2.5
        turnThresholdDegrees = try container.decodeIfPresent(Double.self, forKey: .turnThresholdDegrees) ?? 0.75
        widthChangeMin = try container.decodeIfPresent(Double.self, forKey: .widthChangeMin) ?? 2.0
        widthChangeFactor = try container.decodeIfPresent(Double.self, forKey: .widthChangeFactor) ?? 0.04
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(flattenTolerance, forKey: .flattenTolerance)
        try container.encode(envelopeTolerance, forKey: .envelopeTolerance)
        try container.encode(railTolerance, forKey: .railTolerance)
        try container.encode(railChordTolerance, forKey: .railChordTolerance)
        try container.encode(railMaxSegmentLength, forKey: .railMaxSegmentLength)
        try container.encode(railMaxTurnAngleDegrees, forKey: .railMaxTurnAngleDegrees)
        try container.encode(maxSamples, forKey: .maxSamples)
        try container.encode(maxRecursionDepth, forKey: .maxRecursionDepth)
        try container.encode(minParamStep, forKey: .minParamStep)
        try container.encode(rotationThresholdDegrees, forKey: .rotationThresholdDegrees)
        try container.encode(turnThresholdDegrees, forKey: .turnThresholdDegrees)
        try container.encode(widthChangeMin, forKey: .widthChangeMin)
        try container.encode(widthChangeFactor, forKey: .widthChangeFactor)
    }

    public static var preview: SamplingPolicy {
        SamplingPolicy(
            flattenTolerance: 1.5,
            envelopeTolerance: 2.0,
            railTolerance: 0.5,
            railChordTolerance: 0.4,
            railMaxSegmentLength: 2.0,
            railMaxTurnAngleDegrees: 2.0,
            maxSamples: 80,
            maxRecursionDepth: 7,
            minParamStep: 0.01,
            rotationThresholdDegrees: 2.5,
            turnThresholdDegrees: 0.75,
            widthChangeMin: 2.0,
            widthChangeFactor: 0.04
        )
    }

    public static var final: SamplingPolicy {
        SamplingPolicy(
            flattenTolerance: 0.5,
            envelopeTolerance: 0.4,
            railTolerance: 0.3,
            railChordTolerance: 0.25,
            railMaxSegmentLength: 0.5,
            railMaxTurnAngleDegrees: 1.0,
            maxSamples: 300,
            maxRecursionDepth: 10,
            minParamStep: 0.002,
            rotationThresholdDegrees: 2.5,
            turnThresholdDegrees: 0.75,
            widthChangeMin: 2.0,
            widthChangeFactor: 0.04
        )
    }

    public static func fromSamplingSpec(_ spec: SamplingSpec) -> SamplingPolicy {
        SamplingPolicy(
            flattenTolerance: spec.flatnessTolerance,
            envelopeTolerance: max(0.1, spec.baseSpacing * 0.5),
            railTolerance: 0.4,
            railChordTolerance: 0.25,
            railMaxSegmentLength: 1.0,
            railMaxTurnAngleDegrees: 1.0,
            maxSamples: spec.maxSamples,
            maxRecursionDepth: 8,
            minParamStep: spec.minimumSpacing,
            rotationThresholdDegrees: spec.rotationThresholdDegrees,
            turnThresholdDegrees: 0.75,
            widthChangeMin: 2.0,
            widthChangeFactor: 0.04
        )
    }

    public var rotationThresholdRadians: Double {
        rotationThresholdDegrees * .pi / 180.0
    }
}
