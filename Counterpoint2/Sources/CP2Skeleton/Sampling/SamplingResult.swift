import Foundation

public struct SamplingStats: Sendable, Equatable {
    public var acceptedSegments: Int = 0
    public var subdividedSegments: Int = 0
    public var forcedStops: Int = 0
    public var maxDepthReached: Int = 0

    // “worst offender” tracking
    public var worstFlatnessErr: Double = 0
    public var worstRailErr: Double = 0
    public var worstParamErr: Double = 0

    public init() {}
}

public struct SamplingResult: Sendable, Equatable {
    public let ts: [Double]
    public let trace: [SampleDecision]
    public let stats: SamplingStats

    public init(ts: [Double], trace: [SampleDecision], stats: SamplingStats) {
        self.ts = ts
        self.trace = trace
        self.stats = stats
    }
}
