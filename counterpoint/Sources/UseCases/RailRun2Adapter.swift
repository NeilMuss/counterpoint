import Domain

public func adaptRailsToRailRuns2(side: RailSide, samples: [PathDomain.Sample]) -> [RailRun2] {
    guard !samples.isEmpty else { return [] }

    var railSamples: [RailSample2] = []
    railSamples.reserveCapacity(samples.count)

    for sample in samples {
        railSamples.append(
            RailSample2(
                p: sample.point,
                n: sample.unitTangent.leftNormal(),
                lt: sample.s,
                sourceGT: sample.gt,
                chainGT: nil
            )
        )
    }

    var inkLength = 0.0
    if samples.count > 1 {
        for i in 1..<samples.count {
            inkLength += (samples[i].point - samples[i - 1].point).length
        }
    }

    let sortKey = samples.first?.gt ?? 0.0
    let run = RailRun2(id: 0, side: side, samples: railSamples, inkLength: inkLength, sortKey: sortKey)
    return [run]
}
