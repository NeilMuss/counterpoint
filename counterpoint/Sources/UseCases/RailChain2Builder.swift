import Domain

public func buildRailChain2(side: RailSide, runs: [RailRun2]) -> RailChain2 {
    var edges: [ChainEdge2] = []
    edges.reserveCapacity(runs.reduce(0) { $0 + max(0, $1.samples.count - 1) })

    var metricLength = 0.0
    for run in runs {
        guard run.samples.count > 1 else { continue }
        for i in 1..<run.samples.count {
            let a = run.samples[i - 1].p
            let b = run.samples[i].p
            let length = (b - a).length
            metricLength += length
            edges.append(
                ChainEdge2(
                    kind: .ink,
                    a: a,
                    b: b,
                    fromRun: run.id,
                    toRun: run.id,
                    length: length,
                    contributesToMetric: true
                )
            )
        }
    }

    let denom = metricLength > 0.0 ? metricLength : 1.0
    var running = 0.0
    var updatedRuns: [RailRun2] = []
    updatedRuns.reserveCapacity(runs.count)

    for run in runs {
        guard !run.samples.isEmpty else {
            updatedRuns.append(run)
            continue
        }

        var updatedSamples: [RailSample2] = []
        updatedSamples.reserveCapacity(run.samples.count)

        for i in 0..<run.samples.count {
            let sample = run.samples[i]
            let gt = min(1.0, max(0.0, running / denom))
            updatedSamples.append(
                RailSample2(
                    p: sample.p,
                    n: sample.n,
                    lt: sample.lt,
                    sourceGT: sample.sourceGT,
                    chainGT: gt
                )
            )

            if i + 1 < run.samples.count {
                let nextPoint = run.samples[i + 1].p
                running += (nextPoint - sample.p).length
            }
        }

        updatedRuns.append(RailRun2(id: run.id, side: run.side, samples: updatedSamples, inkLength: run.inkLength, sortKey: run.sortKey))
    }

    if metricLength > 0.0, let lastIndex = updatedRuns.indices.last {
        var run = updatedRuns[lastIndex]
        if !run.samples.isEmpty {
            var samples = run.samples
            let lastSample = samples[samples.count - 1]
            samples[samples.count - 1] = RailSample2(
                p: lastSample.p,
                n: lastSample.n,
                lt: lastSample.lt,
                sourceGT: lastSample.sourceGT,
                chainGT: 1.0
            )
            run = RailRun2(id: run.id, side: run.side, samples: samples, inkLength: run.inkLength, sortKey: run.sortKey)
            updatedRuns[lastIndex] = run
        }
    }

    if updatedRuns.count > 1 {
        for i in 0..<(updatedRuns.count - 1) {
            guard let a = updatedRuns[i].samples.last?.p,
                  let b = updatedRuns[i + 1].samples.first?.p else {
                continue
            }
            edges.append(
                ChainEdge2(
                    kind: .connector,
                    a: a,
                    b: b,
                    fromRun: updatedRuns[i].id,
                    toRun: updatedRuns[i + 1].id,
                    length: (b - a).length,
                    contributesToMetric: false
                )
            )
        }
    }

    return RailChain2(side: side, runs: updatedRuns, edges: edges, metricLength: metricLength)
}
