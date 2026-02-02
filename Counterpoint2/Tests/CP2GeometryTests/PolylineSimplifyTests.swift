import XCTest
import CP2Geometry

final class PolylineSimplifyTests: XCTestCase {
    func testSimplifyRemovesCollinearPoint() {
        let points = [Vec2(0, 0), Vec2(1, 0), Vec2(2, 0), Vec2(2, 1)]
        let result = simplifyOpenPolylineForCorners(points, epsLen: 1.0e-6, epsAngleRad: 1.0e-6)
        XCTAssertEqual(result.points.count, 3)
        XCTAssertEqual(result.points[0], Vec2(0, 0))
        XCTAssertEqual(result.points[1], Vec2(2, 0))
        XCTAssertEqual(result.points[2], Vec2(2, 1))
        XCTAssertGreaterThan(result.removedCount, 0)
    }
}
