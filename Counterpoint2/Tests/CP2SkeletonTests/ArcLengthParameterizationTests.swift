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

    func testUAtDistanceClampsAndIsMonotone() {
        let bezier = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(33, 0),
            p2: Vec2(66, 0),
            p3: Vec2(100, 0)
        )
        let path = SkeletonPath(segments: [bezier])
        let param = ArcLengthParameterization(path: path)

        XCTAssertEqual(param.totalLength, 100.0, accuracy: 1.0e-3)
        XCTAssertEqual(param.u(atDistance: 0.0), 0.0, accuracy: 1.0e-6)
        XCTAssertEqual(param.u(atDistance: param.totalLength), 1.0, accuracy: 1.0e-6)
        XCTAssertEqual(param.u(atDistance: param.totalLength * 0.5), 0.5, accuracy: 5.0e-2)

        let distances: [Double] = [0, 10, 25, 50, 75, 90, 100]
        var previous = -Double.greatestFiniteMagnitude
        for s in distances {
            let u = param.u(atDistance: s)
            XCTAssertGreaterThanOrEqual(u + 1.0e-12, previous)
            previous = u
        }
    }
}
