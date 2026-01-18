import Domain

public struct RailChain2Window: Equatable {
    public let side: RailSide
    public let runs: [RailRun2]
    public let metricLength: Double

    public init(side: RailSide, runs: [RailRun2], metricLength: Double) {
        self.side = side
        self.runs = runs
        self.metricLength = metricLength
    }
}

public func windowRailChain2(_ chain: RailChain2, gt0: Double, gt1: Double) -> RailChain2Window {
    let clamped0 = ScalarMath.clamp01(gt0)
    let clamped1 = ScalarMath.clamp01(gt1)
    let wrap = clamped1 < clamped0

    func inWindow(_ value: Double) -> Bool {
        if wrap {
            return value >= clamped0 || value <= clamped1
        }
        return value >= clamped0 && value <= clamped1
    }

    var windowRuns: [RailRun2] = []
    windowRuns.reserveCapacity(chain.runs.count)

    var metricLength = 0.0
    for run in chain.runs {
        let filteredSamples = run.samples.filter { sample in
            guard let gt = sample.chainGT else { return false }
            return inWindow(gt)
        }
        guard !filteredSamples.isEmpty else { continue }

        if filteredSamples.count > 1 {
            for i in 1..<filteredSamples.count {
                metricLength += (filteredSamples[i].p - filteredSamples[i - 1].p).length
            }
        }

        windowRuns.append(
            RailRun2(
                id: run.id,
                side: run.side,
                samples: filteredSamples,
                inkLength: run.inkLength,
                sortKey: run.sortKey
            )
        )
    }

    return RailChain2Window(side: chain.side, runs: windowRuns, metricLength: metricLength)
}
