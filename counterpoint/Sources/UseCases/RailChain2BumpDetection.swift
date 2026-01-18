import Foundation
import Domain

public struct RailChainBump: Equatable {
    public let side: RailSide
    public let runID: Int
    public let sampleIndex: Int
    public let position: Vec2
    public let chainGT: Double
    public let curvatureMagnitude: Double

    public init(
        side: RailSide,
        runID: Int,
        sampleIndex: Int,
        position: Vec2,
        chainGT: Double,
        curvatureMagnitude: Double
    ) {
        self.side = side
        self.runID = runID
        self.sampleIndex = sampleIndex
        self.position = position
        self.chainGT = chainGT
        self.curvatureMagnitude = curvatureMagnitude
    }
}

public func detectRailChainBump(_ window: RailChain2Window, side: RailSide) -> RailChainBump? {
    var best: RailChainBump?
    var bestMagnitude = -Double.greatestFiniteMagnitude

    for run in window.runs where run.side == side {
        guard run.samples.count > 2 else { continue }
        for i in 1..<(run.samples.count - 1) {
            let p0 = run.samples[i - 1].p
            let p1 = run.samples[i].p
            let p2 = run.samples[i + 1].p

            let v0 = p1 - p0
            let v1 = p2 - p1
            let len0 = v0.length
            let len1 = v1.length
            if len0 <= 1.0e-9 || len1 <= 1.0e-9 { continue }

            let dot = max(-1.0, min(1.0, v0.dot(v1) / (len0 * len1)))
            let angle = acos(dot)
            let magnitude = abs(angle)

            if magnitude > bestMagnitude, let gt = run.samples[i].chainGT {
                bestMagnitude = magnitude
                best = RailChainBump(
                    side: side,
                    runID: run.id,
                    sampleIndex: i,
                    position: p1,
                    chainGT: gt,
                    curvatureMagnitude: magnitude
                )
            }
        }
    }

    return best
}
