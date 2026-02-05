import XCTest
import CP2Geometry

final class ResolveSelfOverlapTests: XCTestCase {
    func testResolveSelfOverlapBowTie() {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(2, 0),
            Vec2(0, 0)
        ]
        let result = resolveSelfOverlap(ring: ring, eps: 1.0e-6)
        XCTAssertTrue(result.success)
        XCTAssertGreaterThan(result.ring.count, 3)
        XCTAssertGreaterThan(result.faces, 0)
    }
}
