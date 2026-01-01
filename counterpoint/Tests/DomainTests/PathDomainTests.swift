import XCTest
@testable import Domain

final class PathDomainTests: XCTestCase {
    func testMonotonicityAndLength() {
        let path = multiSegmentPath()
        let domain = PathDomain(path: path, samplesPerSegment: 20)
        XCTAssertGreaterThan(domain.totalLength, 0.0)
        XCTAssertFalse(domain.samples.isEmpty)
        XCTAssertEqual(domain.samples.first?.s ?? -1, 0.0, accuracy: 1.0e-6)
        XCTAssertEqual(domain.samples.last?.s ?? -1, 1.0, accuracy: 1.0e-6)

        for i in 1..<domain.samples.count {
            XCTAssertGreaterThanOrEqual(domain.samples[i].cumulativeLength, domain.samples[i - 1].cumulativeLength)
            XCTAssertGreaterThanOrEqual(domain.samples[i].s, domain.samples[i - 1].s)
        }
    }

    func testContinuityAcrossJoin() {
        let path = multiSegmentPath()
        let domain = PathDomain(path: path, samplesPerSegment: 30)
        let sJoin = domain.s(forSegment: 1, t: 0.0)
        let field = ParamField.linearDegrees(startDeg: 10.0, endDeg: 75.0)

        let before = field.evaluate(ScalarMath.clamp01(sJoin - 1.0e-3))
        let after = field.evaluate(ScalarMath.clamp01(sJoin + 1.0e-3))
        XCTAssertLessThan(abs(after - before), 0.2)
    }

    func testAngleModeSanityOnStraightPath() {
        let path = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 33, y: 0),
                p2: Point(x: 66, y: 0),
                p3: Point(x: 100, y: 0)
            )
        ])
        let domain = PathDomain(path: path, samplesPerSegment: 10)
        let sample = domain.evalAtS(0.5, path: path)
        let angle = 30.0

        let absoluteDir = AngleMath.directionVector(unitTangent: sample.unitTangent, angleDegrees: angle, mode: .absolute)
        XCTAssertEqual(absoluteDir.x, cos(angle * .pi / 180.0), accuracy: 1.0e-6)
        XCTAssertEqual(absoluteDir.y, sin(angle * .pi / 180.0), accuracy: 1.0e-6)

        let relativeDir = AngleMath.directionVector(unitTangent: sample.unitTangent, angleDegrees: angle, mode: .tangentRelative)
        XCTAssertEqual(relativeDir.x, cos(angle * .pi / 180.0), accuracy: 1.0e-6)
        XCTAssertEqual(relativeDir.y, sin(angle * .pi / 180.0), accuracy: 1.0e-6)
    }

    func testDeterminism() {
        let path = multiSegmentPath()
        let domainA = PathDomain(path: path, samplesPerSegment: 24)
        let domainB = PathDomain(path: path, samplesPerSegment: 24)

        XCTAssertEqual(domainA.samples.count, domainB.samples.count)
        let firstA = domainA.samples.first
        let firstB = domainB.samples.first
        let lastA = domainA.samples.last
        let lastB = domainB.samples.last

        XCTAssertEqual(firstA?.t ?? -1, firstB?.t ?? -2, accuracy: 1.0e-9)
        XCTAssertEqual(lastA?.t ?? -1, lastB?.t ?? -2, accuracy: 1.0e-9)
        XCTAssertEqual(firstA?.point.x ?? -1, firstB?.point.x ?? -2, accuracy: 1.0e-9)
        XCTAssertEqual(lastA?.point.y ?? -1, lastB?.point.y ?? -2, accuracy: 1.0e-9)
    }

    private func multiSegmentPath() -> BezierPath {
        BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 40, y: 80),
                p2: Point(x: 60, y: 80),
                p3: Point(x: 100, y: 0)
            ),
            CubicBezier(
                p0: Point(x: 100, y: 0),
                p1: Point(x: 140, y: -80),
                p2: Point(x: 160, y: -80),
                p3: Point(x: 200, y: 0)
            ),
            CubicBezier(
                p0: Point(x: 200, y: 0),
                p1: Point(x: 240, y: 80),
                p2: Point(x: 260, y: 80),
                p3: Point(x: 300, y: 0)
            )
        ])
    }
}
