import XCTest
import CP2Geometry
import CP2Skeleton

final class CubicBezier2Tests: XCTestCase {
    func testEvaluateEndpoints() {
        let bezier = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(1, 0),
            p2: Vec2(2, 0),
            p3: Vec2(3, 0)
        )
        XCTAssertEqual(bezier.evaluate(0), Vec2(0, 0))
        XCTAssertEqual(bezier.evaluate(1), Vec2(3, 0))
    }

    func testDerivativeAndTangentOnLine() {
        let bezier = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(1, 0),
            p2: Vec2(2, 0),
            p3: Vec2(3, 0)
        )
        let d = bezier.derivative(0.5)
        XCTAssertTrue(d.length > 0)
        let t = bezier.tangent(0.5)
        XCTAssertTrue(Epsilon.approxEqual(t, Vec2(1, 0), eps: 1.0e-6))
    }
}
