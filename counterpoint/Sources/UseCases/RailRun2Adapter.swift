import Domain

private let railRunBreakThreshold: Double = 200.0

public func adaptRailsToRailRuns2(side: RailSide, samples: [PathDomain.Sample]) -> [RailRun2] {
    guard !samples.isEmpty else { return [] }

    var runs: [RailRun2] = []
    runs.reserveCapacity(2)

    var currentSamples: [RailSample2] = []
    currentSamples.reserveCapacity(samples.count)
    var currentInkLength = 0.0
    var runId = 0

    func finalizeRun() {
        guard !currentSamples.isEmpty else { return }
        let sortKey = currentSamples.first?.sourceGT ?? 0.0
        runs.append(
            RailRun2(
                id: runId,
                side: side,
                samples: currentSamples,
                inkLength: currentInkLength,
                sortKey: sortKey
            )
        )
        runId += 1
        currentSamples = []
        currentInkLength = 0.0
    }

    var previousPoint: Point?
    for sample in samples {
        let point = sample.point
        if let prev = previousPoint {
            let step = (point - prev).length
            if step > railRunBreakThreshold {
                finalizeRun()
            } else {
                currentInkLength += step
            }
        }
        currentSamples.append(
            RailSample2(
                p: point,
                n: sample.unitTangent.leftNormal(),
                lt: sample.s,
                sourceGT: sample.gt,
                chainGT: nil
            )
        )
        previousPoint = point
    }

    finalizeRun()
    return runs
}
