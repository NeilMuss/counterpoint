import XCTest
@testable import Domain
@testable import UseCases

final class RailChain2BuilderTests: XCTestCase {
    func testSingleRailRunProducesRailChain2WithInkMetric() {
        let path = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 40, y: 80),
                p2: Point(x: 60, y: 80),
                p3: Point(x: 100, y: 0)
            )
        ])
        let domain = PathDomain(path: path, samplesPerSegment: 12)
        let samples = domain.samples
        XCTAssertFalse(samples.isEmpty)

        let runs = adaptRailsToRailRuns2(side: .left, samples: samples)
        XCTAssertEqual(runs.count, 1)

        let chain = buildRailChain2(side: .left, runs: runs)
        XCTAssertEqual(chain.runs.count, 1)
        XCTAssertFalse(chain.edges.isEmpty)
        XCTAssertGreaterThan(chain.metricLength, 0.0)

        for edge in chain.edges {
            XCTAssertEqual(edge.kind, .ink)
            XCTAssertTrue(edge.contributesToMetric)
        }

        let chainSamples = chain.runs[0].samples
        XCTAssertFalse(chainSamples.isEmpty)

        for i in 0..<chainSamples.count {
            let sample = chainSamples[i]
            XCTAssertNotNil(sample.chainGT)
            XCTAssertGreaterThanOrEqual(sample.chainGT ?? -1.0, 0.0)
            XCTAssertLessThanOrEqual(sample.chainGT ?? 2.0, 1.0)
            if i > 0 {
                XCTAssertGreaterThanOrEqual(sample.chainGT ?? -1.0, chainSamples[i - 1].chainGT ?? -2.0)
            }
        }
        XCTAssertEqual(chainSamples.first?.chainGT ?? -1.0, 0.0, accuracy: 1.0e-6)
        XCTAssertEqual(chainSamples.last?.chainGT ?? -1.0, 1.0, accuracy: 1.0e-6)
    }
}
