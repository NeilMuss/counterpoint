import CP2Geometry
import CP2Skeleton
import XCTest

final class SamplingWhyDotsTests: XCTestCase {
    func testSamplingWhyDotsClassifiesReasonsAndSeverity() {
        let decisions = [
            SampleDecision(
                t0: 0.0,
                t1: 1.0,
                tm: 0.5,
                depth: 1,
                action: .subdivided,
                reasons: [.subdividePathFlatness(err: 0.2)],
                errors: SampleErrors(flatnessErr: 0.2)
            ),
            SampleDecision(
                t0: 0.0,
                t1: 0.5,
                tm: 0.25,
                depth: 2,
                action: .forcedStop,
                reasons: [.maxDepthHit],
                errors: SampleErrors()
            )
        ]

        let result = SamplingResult(ts: [0.0, 1.0], trace: decisions, stats: SamplingStats())
        let dots = samplingWhyDots(
            result: result,
            flatnessEps: 0.1,
            railEps: 0.1,
            positionAtS: { Vec2($0, 0.0) }
        )

        XCTAssertEqual(dots.count, 2)
        XCTAssertEqual(dots[0].reason, .flatness)
        XCTAssertGreaterThan(dots[0].severity, 1.0)
        XCTAssertEqual(dots[0].position.x, 0.5, accuracy: 1.0e-9)

        XCTAssertEqual(dots[1].reason, .forcedStop)
        XCTAssertGreaterThan(dots[1].severity, 0.0)
        XCTAssertEqual(dots[1].position.x, 0.25, accuracy: 1.0e-9)
    }
}
