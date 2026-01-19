import XCTest
@testable import Domain

final class BumpSmoothingTests: XCTestCase {
    func testSmoothingReducesCurvaturePreservesEndpointsAndGT() {
        let samples: [RailSample2] = [
            RailSample2(p: Point(x: 0, y: 0), n: Point(x: 0, y: 1), lt: 0.0, sourceGT: 0.0, chainGT: 0.0),
            RailSample2(p: Point(x: 1, y: 0), n: Point(x: 0, y: 1), lt: 0.25, sourceGT: 0.25, chainGT: 0.25),
            RailSample2(p: Point(x: 2, y: 2), n: Point(x: 0, y: 1), lt: 0.5, sourceGT: 0.5, chainGT: 0.5),
            RailSample2(p: Point(x: 3, y: 0), n: Point(x: 0, y: 1), lt: 0.75, sourceGT: 0.75, chainGT: 0.75),
            RailSample2(p: Point(x: 4, y: 0), n: Point(x: 0, y: 1), lt: 1.0, sourceGT: 1.0, chainGT: 1.0)
        ]
        let run = RailRun2(id: 0, side: .left, samples: samples, inkLength: 0.0, sortKey: 0.0)
        let chain = RailChain2(side: .left, runs: [run], edges: [], metricLength: 0.0)
        let window = BumpWindow(side: .left, gt0: 0.25, gt1: 0.75)
        let policy = BumpSmoothingPolicy(iterations: 2, strength: 0.5, preserveEndpoints: true, preserveGT: true)

        let windowPointsBefore = samples.filter { $0.chainGT != nil && $0.chainGT! >= 0.25 && $0.chainGT! <= 0.75 }.map { $0.p }
        let energyBefore = discreteCurvatureEnergy(points: windowPointsBefore)

        let smoothed = smoothRailChain(chain, window: window, policy: policy)
        let smoothedSamples = smoothed.runs[0].samples
        let windowPointsAfter = smoothedSamples.filter { $0.chainGT != nil && $0.chainGT! >= 0.25 && $0.chainGT! <= 0.75 }.map { $0.p }
        let energyAfter = discreteCurvatureEnergy(points: windowPointsAfter)

        XCTAssertLessThan(energyAfter, energyBefore)

        XCTAssertEqual(smoothedSamples[1].p, samples[1].p)
        XCTAssertEqual(smoothedSamples[3].p, samples[3].p)
        XCTAssertEqual(smoothedSamples[0].p, samples[0].p)
        XCTAssertEqual(smoothedSamples[4].p, samples[4].p)

        for i in 0..<samples.count {
            XCTAssertEqual(smoothedSamples[i].chainGT, samples[i].chainGT)
        }
    }
}
