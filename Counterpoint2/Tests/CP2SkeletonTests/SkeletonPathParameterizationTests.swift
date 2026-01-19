import XCTest
import CP2Geometry
import CP2Skeleton

final class SkeletonPathParameterizationTests: XCTestCase {
    func testPositionEndpointsAndMidpointMapping() {
        let a = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(0, 33),
            p2: Vec2(0, 66),
            p3: Vec2(0, 100)
        )
        let b = CubicBezier2(
            p0: Vec2(0, 100),
            p1: Vec2(0, 133),
            p2: Vec2(0, 166),
            p3: Vec2(0, 200)
        )
        let path = SkeletonPath(segments: [a, b])
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 128)

        XCTAssertTrue(Epsilon.approxEqual(param.position(globalT: 0), a.p0, eps: 1.0e-6))
        XCTAssertTrue(Epsilon.approxEqual(param.position(globalT: 1), b.p3, eps: 1.0e-6))

        let mid = param.map(globalT: 0.5)
        XCTAssertTrue(mid.segmentIndex == 0 || mid.segmentIndex == 1)
        XCTAssertTrue(mid.localU >= 0.0 && mid.localU <= 1.0)

        let nearJoin = param.position(globalT: 0.5)
        XCTAssertTrue(abs(nearJoin.y - 100.0) < 5.0)
    }

    func testDeterminism() {
        let a = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(10, 0),
            p2: Vec2(20, 0),
            p3: Vec2(30, 0)
        )
        let b = CubicBezier2(
            p0: Vec2(30, 0),
            p1: Vec2(40, 0),
            p2: Vec2(50, 0),
            p3: Vec2(60, 0)
        )
        let path = SkeletonPath(segments: [a, b])
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 64)

        let first = param.map(globalT: 0.73)
        let second = param.map(globalT: 0.73)
        XCTAssertEqual(first.segmentIndex, second.segmentIndex)
        XCTAssertEqual(first.localU, second.localU, accuracy: 1.0e-9)

        let posA = param.position(globalT: 0.73)
        let posB = param.position(globalT: 0.73)
        XCTAssertEqual(posA.x, posB.x, accuracy: 1.0e-9)
        XCTAssertEqual(posA.y, posB.y, accuracy: 1.0e-9)

        let tanA = param.tangent(globalT: 0.73)
        let tanB = param.tangent(globalT: 0.73)
        XCTAssertEqual(tanA.x, tanB.x, accuracy: 1.0e-9)
        XCTAssertEqual(tanA.y, tanB.y, accuracy: 1.0e-9)
    }
}
