import XCTest
import CP2Geometry
import CP2Skeleton

final class SoupNeighborhoodTests: XCTestCase {
    func testCollisionReportDetectsMultiplePositionsForKey() {
        let eps = 1.0
        let segments = [
            Segment2(Vec2(0.0, 0.0), Vec2(1.0, 0.0), source: .railLeft),
            Segment2(Vec2(0.4, 0.4), Vec2(1.0, 0.0), source: .railRight)
        ]
        let report = computeSoupNeighborhood(
            segments: segments,
            eps: eps,
            center: Vec2(0.0, 0.0),
            radius: 2.0
        )
        XCTAssertTrue(report.collisions.contains { $0.key == Epsilon.snapKey(Vec2(0.0, 0.0), eps: eps) })
    }
}
