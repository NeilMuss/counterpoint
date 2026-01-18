import XCTest
@testable import Domain
@testable import UseCases

final class RailChain2WindowingTests: XCTestCase {
    func testWindowRailChain2SelectsLaterRuns() {
        let path = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 33, y: 0),
                p2: Point(x: 66, y: 0),
                p3: Point(x: 100, y: 0)
            ),
            CubicBezier(
                p0: Point(x: 1000, y: 0),
                p1: Point(x: 1033, y: 0),
                p2: Point(x: 1066, y: 0),
                p3: Point(x: 1100, y: 0)
            )
        ])
        let domain = PathDomain(path: path, samplesPerSegment: 8)
        let samples = domain.samples
        XCTAssertFalse(samples.isEmpty)

        let runs = adaptRailsToRailRuns2(side: .left, samples: samples)
        XCTAssertGreaterThanOrEqual(runs.count, 2)

        let chain = buildRailChain2(side: .left, runs: runs)
        let window = windowRailChain2(chain, gt0: 0.60, gt1: 0.90)

        XCTAssertFalse(window.runs.isEmpty)
        XCTAssertTrue(window.runs.contains { $0.id != runs.first?.id })

        let allWindowSamples = window.runs.flatMap { $0.samples }
        XCTAssertFalse(allWindowSamples.isEmpty)
        for i in 1..<allWindowSamples.count {
            XCTAssertGreaterThanOrEqual(allWindowSamples[i].chainGT ?? -1.0, allWindowSamples[i - 1].chainGT ?? -2.0)
        }
    }
}
