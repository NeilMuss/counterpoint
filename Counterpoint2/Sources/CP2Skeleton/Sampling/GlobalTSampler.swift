import Foundation
import CP2Geometry

public struct GlobalTSampler {
    public typealias PositionAtT = @Sendable (Double) -> Vec2
    public typealias ParamsAtT = @Sendable (Double) -> StrokeParamsSample?

    public struct StrokeParamsSample: Sendable, Equatable {
        public let width: Double
        public let theta: Double
        public let offset: Double
        public init(width: Double, theta: Double, offset: Double) {
            self.width = width
            self.theta = theta
            self.offset = offset
        }
    }

    public init() {}

    /// Primary entry point.
    /// - positionAt: global-t -> skeleton position
    /// - railProbe: optional; if nil, rail deviation rule is disabled
    /// - paramsAt: optional; if nil, param-change rule is disabled
    public func sampleGlobalT(
        config: SamplingConfig,
        positionAt: PositionAtT,
        railProbe: (any RailProbe)? = nil,
        paramsAt: ParamsAtT? = nil
    ) -> SamplingResult {

        switch config.mode {
        case .fixed(let count):
            let ts = fixedSamples(count: count, tEps: config.tEps)
            let stats = SamplingStats()
            // Trace optional in fixed mode; keep it empty for now.
            return SamplingResult(ts: ts, trace: [], stats: stats)

        case .adaptive:
            return adaptiveSamples(config: config, positionAt: positionAt, railProbe: railProbe, paramsAt: paramsAt)
        }
    }

    // MARK: - Fixed

    private func fixedSamples(count: Int, tEps: Double) -> [Double] {
        let n = max(2, count)
        if n == 2 { return [0.0, 1.0] }
        return (0..<n).map { Double($0) / Double(n - 1) }
    }

    // MARK: - Adaptive (skeleton)

    private func adaptiveSamples(
        config: SamplingConfig,
        positionAt: PositionAtT,
        railProbe: (any RailProbe)?,
        paramsAt: ParamsAtT?
    ) -> SamplingResult {

        // Implementation comes next step: deterministic recursion,
        // accumulating ts and trace and stats.

        // For now: placeholder minimal valid result.
        let ts = [0.0, 1.0]
        let trace: [SampleDecision] = [
            SampleDecision(
                t0: 0, t1: 1, tm: 0.5, depth: 0,
                action: .accepted,
                reasons: [.forcedEndpoint],
                errors: SampleErrors()
            )
        ]
        var stats = SamplingStats()
        stats.acceptedSegments = 1
        return SamplingResult(ts: ts, trace: trace, stats: stats)
    }
}
