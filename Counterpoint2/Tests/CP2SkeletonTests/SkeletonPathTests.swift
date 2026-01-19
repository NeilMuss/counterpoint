import XCTest
import CP2Geometry
import CP2Skeleton

final class SkeletonPathTests: XCTestCase {
    func testMultiCubicStoresAllSegments() {
        let a = CubicBezier2(p0: Vec2(0, 0), p1: Vec2(1, 0), p2: Vec2(2, 0), p3: Vec2(3, 0))
        let b = CubicBezier2(p0: Vec2(3, 0), p1: Vec2(3, 1), p2: Vec2(3, 2), p3: Vec2(3, 3))
        let path = SkeletonPath(segments: [a, b])
        XCTAssertEqual(path.segments.count, 2)
        XCTAssertEqual(path.segments[0], a)
        XCTAssertEqual(path.segments[1], b)
    }

    func testSingleCubicConvenienceInitCreatesOneSegment() {
        let a = CubicBezier2(p0: Vec2(0, 0), p1: Vec2(1, 0), p2: Vec2(2, 0), p3: Vec2(3, 0))
        let path = SkeletonPath(a)
        XCTAssertEqual(path.segments.count, 1)
        XCTAssertEqual(path.segments[0], a)
    }
}
