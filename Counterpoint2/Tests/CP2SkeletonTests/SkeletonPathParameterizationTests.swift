import XCTest
import CP2Geometry
import CP2Skeleton

final class SkeletonPathParameterizationTests: XCTestCase {
    func testPositionMatchesArcLengthForLine() {
        let line = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(0, 33),
            p2: Vec2(0, 66),
            p3: Vec2(0, 100)
        )
        let path = SkeletonPath(segments: [line])
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)

        XCTAssertEqual(param.position(globalT: 0.0).y, 0.0, accuracy: 1.0e-6)
        XCTAssertEqual(param.position(globalT: 1.0).y, 100.0, accuracy: 1.0e-6)
        XCTAssertEqual(param.position(globalT: 0.25).y, 25.0, accuracy: 1.0e-1)
        XCTAssertEqual(param.position(globalT: 0.5).y, 50.0, accuracy: 1.0e-1)
        XCTAssertEqual(param.position(globalT: 0.75).y, 75.0, accuracy: 1.0e-1)
    }

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

    func testHigherSampleCountImprovesMidpointAccuracy() {
        let a = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(0, 33),
            p2: Vec2(0, 66),
            p3: Vec2(0, 100)
        )
        let path = SkeletonPath(segments: [a])
        let coarse = SkeletonPathParameterization(path: path, samplesPerSegment: 64)
        let fine = SkeletonPathParameterization(path: path, samplesPerSegment: 256)

        let expectedY = 50.0
        let coarseY = coarse.position(globalT: 0.5).y
        let fineY = fine.position(globalT: 0.5).y
        let coarseError = abs(coarseY - expectedY)
        let fineError = abs(fineY - expectedY)

        XCTAssertLessThanOrEqual(fineError, coarseError + 1.0e-9)
    }

    func testUnequalSegmentLengthsMapByArcLength() {
        let a = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(0, 30),
            p2: Vec2(0, 60),
            p3: Vec2(0, 90)
        )
        let b = CubicBezier2(
            p0: Vec2(0, 90),
            p1: Vec2(0, 93),
            p2: Vec2(0, 97),
            p3: Vec2(0, 100)
        )
        let path = SkeletonPath(segments: [a, b])
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)

        let y089 = param.position(globalT: 0.89).y
        let y090 = param.position(globalT: 0.90).y
        let y091 = param.position(globalT: 0.91).y
        XCTAssertLessThan(y089, 89.8)
        XCTAssertEqual(y090, 90.0, accuracy: 0.5)
        XCTAssertGreaterThan(y091, 90.2)

        XCTAssertEqual(param.map(globalT: 0.89).segmentIndex, 0)
        XCTAssertEqual(param.map(globalT: 0.91).segmentIndex, 1)

        let first = param.map(globalT: 0.91)
        let second = param.map(globalT: 0.91)
        XCTAssertEqual(first.segmentIndex, second.segmentIndex)
        XCTAssertEqual(first.localU, second.localU, accuracy: 1.0e-12)
    }
}
