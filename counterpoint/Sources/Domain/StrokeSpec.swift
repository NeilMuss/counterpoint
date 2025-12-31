import Foundation

public enum AngleMode: String, Codable {
    case absolute
    case tangentRelative
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
    public var path: BezierPath
    public var width: ParamTrack
    public var height: ParamTrack
    public var theta: ParamTrack
    public var angleMode: AngleMode
    public var sampling: SamplingSpec

    public init(
        path: BezierPath,
        width: ParamTrack,
        height: ParamTrack,
        theta: ParamTrack,
        angleMode: AngleMode,
        sampling: SamplingSpec
    ) {
        self.path = path
        self.width = width
        self.height = height
        self.theta = theta
        self.angleMode = angleMode
        self.sampling = sampling
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
    func outline(spec: StrokeSpec) -> PolygonSet
}

public protocol PolygonUnioning {
    func union(subjectRings: [Ring]) throws -> PolygonSet
}
