import XCTest
import CP2Geometry

final class SegmentPlanarizerTests: XCTestCase {
    func testPlanarizerSplitsBowTie() {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(2, 0),
            Vec2(0, 0)
        ]
        let result = SegmentPlanarizer.planarize(ring: ring, eps: 1.0e-6)
        XCTAssertGreaterThan(result.intersections.count, 0)
        XCTAssertGreaterThan(result.edges.count, ring.count - 1)
        XCTAssertGreaterThan(result.vertices.count, 0)
        XCTAssertEqual(result.stats.droppedZeroLength, 0)
        let result2 = SegmentPlanarizer.planarize(ring: ring, eps: 1.0e-6)
        XCTAssertEqual(result, result2)
    }
}
