import Foundation

public struct SamplingPolicy: Codable, Equatable {
    public var flattenTolerance: Double
    public var envelopeTolerance: Double
    public var maxSamples: Int
    public var maxRecursionDepth: Int
    public var minParamStep: Double

    public init(
        flattenTolerance: Double,
        envelopeTolerance: Double,
        maxSamples: Int,
        maxRecursionDepth: Int,
        minParamStep: Double
    ) {
        self.flattenTolerance = flattenTolerance
        self.envelopeTolerance = envelopeTolerance
        self.maxSamples = maxSamples
        self.maxRecursionDepth = maxRecursionDepth
        self.minParamStep = minParamStep
    }

    public static var preview: SamplingPolicy {
        SamplingPolicy(
            flattenTolerance: 1.5,
            envelopeTolerance: 2.0,
            maxSamples: 80,
            maxRecursionDepth: 7,
            minParamStep: 0.01
        )
    }

    public static var final: SamplingPolicy {
        SamplingPolicy(
            flattenTolerance: 0.5,
            envelopeTolerance: 0.4,
            maxSamples: 300,
            maxRecursionDepth: 10,
            minParamStep: 0.002
        )
    }

    public static func fromSamplingSpec(_ spec: SamplingSpec) -> SamplingPolicy {
        SamplingPolicy(
            flattenTolerance: spec.flatnessTolerance,
            envelopeTolerance: max(0.1, spec.baseSpacing * 0.5),
            maxSamples: spec.maxSamples,
            maxRecursionDepth: 8,
            minParamStep: spec.minimumSpacing
        )
    }
}
