import XCTest
import CP2Geometry
import CP2Skeleton

final class SweepTraceTests: XCTestCase {
    func testStraightLineSweepProducesClosedRing() {
        let bezier = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(0, 33),
            p2: Vec2(0, 66),
            p3: Vec2(0, 100)
        )
        let path = SkeletonPath(segments: [bezier])
        let soup = boundarySoup(
            path: path,
            width: 20,
            height: 10,
            effectiveAngle: 0,
            sampleCount: 32
        )
        let rings = traceLoops(segments: soup, eps: 1.0e-6)
        XCTAssertEqual(rings.count, 1)
        guard let ring = rings.first else { return }
        XCTAssertTrue(Epsilon.approxEqual(ring.first!, ring.last!))
        XCTAssertTrue(abs(signedArea(ring)) > 1.0e-6)
    }
}
