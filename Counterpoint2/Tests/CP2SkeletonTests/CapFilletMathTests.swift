import XCTest
import CP2Geometry
import CP2Skeleton

final class CapFilletMathTests: XCTestCase {
    func testRightAngleFilletMath() {
        let a = Vec2(0, 0)
        let b = Vec2(10, 0)
        let c = Vec2(10, 10)
        let result = filletCorner(a: a, b: b, c: c, radius: 2.0)
        guard case .success(let splice) = result else {
            XCTFail("Expected fillet success")
            return
        }
        XCTAssertTrue(approxEqual(splice.p, Vec2(8, 0), eps: 1.0e-6))
        XCTAssertTrue(approxEqual(splice.q, Vec2(10, 2), eps: 1.0e-6))
        let startTangent = (splice.bridge.p1 - splice.bridge.p0).normalized()
        let endTangent = (splice.bridge.p3 - splice.bridge.p2).normalized()
        XCTAssertGreaterThan(startTangent.dot(Vec2(1, 0)), 0.99)
        XCTAssertGreaterThan(endTangent.dot(Vec2(0, 1)), 0.99)
    }

    func testRadiusTooLargeRejects() {
        let a = Vec2(0, 0)
        let b = Vec2(10, 0)
        let c = Vec2(10, 10)
        let result = filletCorner(a: a, b: b, c: c, radius: 100.0)
        XCTAssertEqual(result, .failure(.radiusTooLarge))
    }

    func testDeterministicFilletOutput() {
        let a = Vec2(0, 0)
        let b = Vec2(10, 0)
        let c = Vec2(10, 10)
        let first = filletCorner(a: a, b: b, c: c, radius: 3.0)
        let second = filletCorner(a: a, b: b, c: c, radius: 3.0)
        XCTAssertEqual(first, second)
    }
}

private func approxEqual(_ a: Vec2, _ b: Vec2, eps: Double) -> Bool {
    abs(a.x - b.x) <= eps && abs(a.y - b.y) <= eps
}
