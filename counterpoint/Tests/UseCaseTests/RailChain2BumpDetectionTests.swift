import XCTest
@testable import Domain
@testable import UseCases

final class RailChain2BumpDetectionTests: XCTestCase {
    func testDetectsBumpInWindowedRailChain() {
        let path = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 25, y: 0),
                p2: Point(x: 75, y: 0),
                p3: Point(x: 100, y: 0)
            ),
            CubicBezier(
                p0: Point(x: 1000, y: 0),
                p1: Point(x: 1030, y: 120),
                p2: Point(x: 1070, y: -120),
                p3: Point(x: 1200, y: 0)
            )
        ])
        let domain = PathDomain(path: path, samplesPerSegment: 12)
        let samples = domain.samples
        XCTAssertFalse(samples.isEmpty)

        let runs = adaptRailsToRailRuns2(side: .left, samples: samples)
        XCTAssertGreaterThanOrEqual(runs.count, 2)

        let chain = buildRailChain2(side: .left, runs: runs)
        let window = windowRailChain2(chain, gt0: 0.60, gt1: 0.90)

        let bump = detectRailChainBump(window, side: .left)
        XCTAssertNotNil(bump)

        guard let result = bump else { return }
        XCTAssertGreaterThanOrEqual(result.chainGT, 0.60)
        XCTAssertLessThanOrEqual(result.chainGT, 0.90)
        XCTAssertGreaterThan(result.curvatureMagnitude, 0.0)

        let bounds = boundsOfWindow(window)
        XCTAssertGreaterThanOrEqual(result.position.x, bounds.minX - 1.0e-9)
        XCTAssertLessThanOrEqual(result.position.x, bounds.maxX + 1.0e-9)
        XCTAssertGreaterThanOrEqual(result.position.y, bounds.minY - 1.0e-9)
        XCTAssertLessThanOrEqual(result.position.y, bounds.maxY + 1.0e-9)

        let repeatResult = detectRailChainBump(window, side: .left)
        XCTAssertNotNil(repeatResult)
        XCTAssertEqual(result.chainGT, repeatResult?.chainGT ?? -1.0, accuracy: 1.0e-9)
    }

    private func boundsOfWindow(_ window: RailChain2Window) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for run in window.runs {
            for sample in run.samples {
                let p = sample.p
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
        }
        return (minX, minY, maxX, maxY)
    }
}
