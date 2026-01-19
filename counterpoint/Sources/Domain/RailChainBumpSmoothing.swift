public func smoothRailChain(
    _ chain: RailChain2,
    window: BumpWindow,
    policy: BumpSmoothingPolicy
) -> RailChain2 {
    guard policy.iterations > 0, policy.strength > 0.0 else { return chain }

    var updatedRuns: [RailRun2] = []
    updatedRuns.reserveCapacity(chain.runs.count)

    for run in chain.runs {
        guard run.side == window.side else {
            updatedRuns.append(run)
            continue
        }
        let count = run.samples.count
        guard count >= 3 else {
            updatedRuns.append(run)
            continue
        }
        let inWindow = run.samples.map { sample in
            guard let gt = sample.chainGT else { return false }
            return gtInWindow(gt: gt, gt0: window.gt0, gt1: window.gt1)
        }
        var fixed = Array(repeating: false, count: count)
        if policy.preserveEndpoints {
            var index = 0
            while index < count {
                if inWindow[index] {
                    let start = index
                    while index + 1 < count, inWindow[index + 1] {
                        index += 1
                    }
                    let end = index
                    fixed[start] = true
                    fixed[end] = true
                }
                index += 1
            }
        }

        var positions = run.samples.map { $0.p }
        for _ in 0..<policy.iterations {
            var next = positions
            for i in 1..<(count - 1) {
                guard inWindow[i], !fixed[i] else { continue }
                let blended = positions[i] * (1.0 - policy.strength)
                    + (positions[i - 1] + positions[i + 1]) * (policy.strength * 0.5)
                next[i] = blended
            }
            positions = next
        }

        let updatedSamples = zip(run.samples, positions).map { sample, pos in
            RailSample2(
                p: pos,
                n: sample.n,
                lt: sample.lt,
                sourceGT: sample.sourceGT,
                chainGT: sample.chainGT
            )
        }
        updatedRuns.append(
            RailRun2(
                id: run.id,
                side: run.side,
                samples: updatedSamples,
                inkLength: run.inkLength,
                sortKey: run.sortKey
            )
        )
    }

    return RailChain2(side: chain.side, runs: updatedRuns, edges: chain.edges, metricLength: chain.metricLength)
}

public func discreteCurvatureEnergy(points: [Point]) -> Double {
    guard points.count >= 3 else { return 0.0 }
    var energy = 0.0
    for i in 1..<(points.count - 1) {
        let prev = points[i - 1]
        let curr = points[i]
        let next = points[i + 1]
        let second = Point(x: prev.x - 2.0 * curr.x + next.x, y: prev.y - 2.0 * curr.y + next.y)
        energy += second.x * second.x + second.y * second.y
    }
    return energy
}

private func gtInWindow(gt: Double, gt0: Double, gt1: Double) -> Bool {
    if gt0 <= gt1 {
        return gt >= gt0 && gt <= gt1
    }
    return gt >= gt0 || gt <= gt1
}
