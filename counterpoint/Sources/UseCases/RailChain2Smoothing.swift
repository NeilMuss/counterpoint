import Domain

public func smoothRailChainWindow(
    _ window: RailChain2Window,
    iterations: Int,
    lambda: Double
) -> RailChain2Window {
    guard iterations > 0, lambda > 0 else { return window }
    let clampedLambda = min(max(lambda, 0.0), 1.0)
    var runs = window.runs

    for _ in 0..<iterations {
        runs = runs.map { run in
            let samples = run.samples
            guard samples.count >= 3 else { return run }

            var updated = samples
            for index in 1..<(samples.count - 1) {
                let prev = samples[index - 1].p
                let current = samples[index].p
                let next = samples[index + 1].p
                let blended = current * (1.0 - clampedLambda) + (prev + next) * (clampedLambda * 0.5)
                var updatedSample = updated[index]
                updatedSample = RailSample2(
                    p: blended,
                    n: updatedSample.n,
                    lt: updatedSample.lt,
                    sourceGT: updatedSample.sourceGT,
                    chainGT: updatedSample.chainGT
                )
                updated[index] = updatedSample
            }
            return RailRun2(id: run.id, side: run.side, samples: updated, inkLength: run.inkLength, sortKey: run.sortKey)
        }
    }

    return RailChain2Window(side: window.side, runs: runs, metricLength: window.metricLength)
}
