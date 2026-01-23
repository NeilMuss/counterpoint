import Foundation

public enum SampleAction: Sendable, Equatable {
    case accepted
    case subdivided
    case forcedStop   // hit maxDepth or maxSamples guardrails
}

public enum SampleReason: Sendable, Equatable {
    case forcedEndpoint
    case subdividePathFlatness(err: Double)
    case subdivideRailDeviation(err: Double)
    case subdivideParamChange(err: Double)
    case maxDepthHit
    case maxSamplesHit
}

public struct SampleErrors: Sendable, Equatable {
    public var flatnessErr: Double?
    public var railErr: Double?
    public var paramErr: Double?

    public init(flatnessErr: Double? = nil, railErr: Double? = nil, paramErr: Double? = nil) {
        self.flatnessErr = flatnessErr
        self.railErr = railErr
        self.paramErr = paramErr
    }
}

public struct SampleDecision: Sendable, Equatable {
    public let t0: Double
    public let t1: Double
    public let tm: Double
    public let depth: Int
    public let action: SampleAction
    public let reasons: [SampleReason]
    public let errors: SampleErrors

    public init(t0: Double, t1: Double, tm: Double, depth: Int,
                action: SampleAction, reasons: [SampleReason], errors: SampleErrors) {
        self.t0 = t0
        self.t1 = t1
        self.tm = tm
        self.depth = depth
        self.action = action
        self.reasons = reasons
        self.errors = errors
    }
}
