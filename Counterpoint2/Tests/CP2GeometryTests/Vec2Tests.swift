import XCTest
import CP2Geometry

final class Vec2Tests: XCTestCase {
    func testVec2Arithmetic() {
        let a = Vec2(1, 2)
        let b = Vec2(3, 4)
        XCTAssertEqual(a + b, Vec2(4, 6))
        XCTAssertEqual(b - a, Vec2(2, 2))
        XCTAssertEqual(a * 2, Vec2(2, 4))
        XCTAssertEqual(2 * b, Vec2(6, 8))
        XCTAssertEqual(a.dot(b), 11)
    }

    func testNormalizedZeroVector() {
        let v = Vec2(0, 0)
        XCTAssertEqual(v.normalized(), Vec2(0, 0))
    }

    func testAABBExpansionAndSize() {
        var box = AABB.empty
        box.expand(by: Vec2(1, 2))
        box.expand(by: Vec2(-3, 5))
        XCTAssertEqual(box.min, Vec2(-3, 2))
        XCTAssertEqual(box.max, Vec2(1, 5))
        XCTAssertEqual(box.width, 4)
        XCTAssertEqual(box.height, 3)
    }

    func testApproxEqualAndSnapKey() {
        XCTAssertTrue(Epsilon.approxEqual(1.0, 1.0 + 5.0e-10))
        XCTAssertFalse(Epsilon.approxEqual(1.0, 1.0 + 1.0e-4, eps: 1.0e-6))

        let a = Vec2(1.0000001, -2.0000001)
        let b = Vec2(1.0000002, -2.0000002)
        XCTAssertTrue(Epsilon.approxEqual(a, b))

        let key = Epsilon.snapKey(Vec2(1.25, -2.5), eps: 0.5)
        XCTAssertEqual(key.x, 3)
        XCTAssertEqual(key.y, -5)
    }
}
