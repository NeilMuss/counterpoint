import XCTest
import CP2Geometry
import CP2Skeleton

final class ArcLengthParameterizationTests: XCTestCase {
    func testTotalLengthStableForLine() {
        let bezier = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(0, 33),
            p2: Vec2(0, 66),
            p3: Vec2(0, 100)
        )
        let path = SkeletonPath(segments: [bezier])
        let a = ArcLengthParameterization(path: path)
        let b = ArcLengthParameterization(path: path)
        XCTAssertTrue(a.totalLength > 0)
        XCTAssertEqual(a.totalLength, b.totalLength, accuracy: 1.0e-6)
    }
}
