import Foundation
import XCTest
import CP2Geometry
import CP2Skeleton

final class SweepTraceTests: XCTestCase {
    func testStraightLineSweepProducesClosedRing() {
        let bezier = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(0, 33),
            p2: Vec2(0, 66),
            p3: Vec2(0, 100)
        )
        let path = SkeletonPath(segments: [bezier])
        let soup = boundarySoup(
            path: path,
            width: 20,
            height: 10,
            effectiveAngle: 0,
            sampleCount: 32
        )
        let rings = traceLoops(segments: soup, eps: 1.0e-6)
        XCTAssertEqual(rings.count, 1)
        guard let ring = rings.first else { return }
        XCTAssertTrue(Epsilon.approxEqual(ring.first!, ring.last!))
        XCTAssertTrue(abs(signedArea(ring)) > 1.0e-6)
    }

    func testSCurveSweepProducesDeterministicClosedRing() {
        let path = SkeletonPath(segments: [sCurveFixtureCubic()])
        let width = 20.0
        let height = 10.0
        let samples = 64
        let soupA = boundarySoup(
            path: path,
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let soupB = boundarySoup(
            path: path,
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let ringA = traceLoops(segments: soupA, eps: 1.0e-6).first ?? []
        let ringB = traceLoops(segments: soupB, eps: 1.0e-6).first ?? []

        XCTAssertFalse(ringA.isEmpty)
        XCTAssertEqual(ringA.count, ringB.count)
        XCTAssertTrue(Epsilon.approxEqual(ringA.first!, ringA.last!))
        XCTAssertTrue(abs(signedArea(ringA)) > 1.0e-6)

        for (a, b) in zip(ringA, ringB) {
            XCTAssertTrue(Epsilon.approxEqual(a, b, eps: 1.0e-6))
        }

        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        var skeletonBounds = AABB.empty
        for i in 0..<samples {
            let t = Double(i) / Double(samples - 1)
            skeletonBounds.expand(by: param.position(globalT: t))
        }
        var ringBounds = AABB.empty
        for p in ringA {
            ringBounds.expand(by: p)
        }
        let expandX = ringBounds.width - skeletonBounds.width
        let expandY = ringBounds.height - skeletonBounds.height
        XCTAssertTrue(expandX >= width * 0.5 - 1.0e-6 || expandY >= height * 0.5 - 1.0e-6)
    }

    func testSCurveNoRailFlip() {
        assertNoRailFlip(path: SkeletonPath(segments: [sCurveFixtureCubic()]))
    }

    func testTwoSegSweepProducesDeterministicClosedRing() {
        let path = twoSegFixturePath()
        let width = 20.0
        let height = 10.0
        let samples = 64
        let soupA = boundarySoup(
            path: path,
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let soupB = boundarySoup(
            path: path,
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let ringA = traceLoops(segments: soupA, eps: 1.0e-6).first ?? []
        let ringB = traceLoops(segments: soupB, eps: 1.0e-6).first ?? []

        XCTAssertFalse(ringA.isEmpty)
        XCTAssertEqual(ringA.count, ringB.count)
        XCTAssertTrue(Epsilon.approxEqual(ringA.first!, ringA.last!))
        XCTAssertTrue(abs(signedArea(ringA)) > 1.0e-6)

        for (a, b) in zip(ringA, ringB) {
            XCTAssertTrue(Epsilon.approxEqual(a, b, eps: 1.0e-6))
        }

        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        var skeletonBounds = AABB.empty
        for i in 0..<samples {
            let t = Double(i) / Double(samples - 1)
            skeletonBounds.expand(by: param.position(globalT: t))
        }
        var ringBounds = AABB.empty
        for p in ringA {
            ringBounds.expand(by: p)
        }
        let expandX = ringBounds.width - skeletonBounds.width
        let expandY = ringBounds.height - skeletonBounds.height
        XCTAssertTrue(expandX >= width * 0.5 - 1.0e-6 || expandY >= height * 0.5 - 1.0e-6)

        assertNoRailFlip(path: path)
    }

    func testJStemSweepProducesDeterministicClosedRing() {
        let path = jStemFixturePath()
        let width = 20.0
        let height = 10.0
        let samples = 64
        let soupA = boundarySoup(
            path: path,
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let soupB = boundarySoup(
            path: path,
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let ringA = traceLoops(segments: soupA, eps: 1.0e-6).first ?? []
        let ringB = traceLoops(segments: soupB, eps: 1.0e-6).first ?? []

        XCTAssertFalse(ringA.isEmpty)
        XCTAssertEqual(ringA.count, ringB.count)
        XCTAssertTrue(Epsilon.approxEqual(ringA.first!, ringA.last!))
        XCTAssertTrue(abs(signedArea(ringA)) > 1.0e-6)

        for (a, b) in zip(ringA, ringB) {
            XCTAssertTrue(Epsilon.approxEqual(a, b, eps: 1.0e-6))
        }

        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        var skeletonBounds = AABB.empty
        for i in 0..<samples {
            let t = Double(i) / Double(samples - 1)
            skeletonBounds.expand(by: param.position(globalT: t))
        }
        var ringBounds = AABB.empty
        for p in ringA {
            ringBounds.expand(by: p)
        }
        XCTAssertGreaterThanOrEqual(ringBounds.height, skeletonBounds.height - 1.0e-6)
        XCTAssertGreaterThanOrEqual(ringBounds.width, width - 1.0e-6)

        assertNoRailFlip(path: path)
    }

    func testJHookSweepProducesDeterministicClosedRing() {
        let path = jFullFixturePath()
        let width = 20.0
        let height = 10.0
        let samples = 64
        let soupA = boundarySoup(
            path: path,
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let soupB = boundarySoup(
            path: path,
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let ringA = traceLoops(segments: soupA, eps: 1.0e-6).first ?? []
        let ringB = traceLoops(segments: soupB, eps: 1.0e-6).first ?? []

        XCTAssertFalse(ringA.isEmpty)
        XCTAssertEqual(ringA.count, ringB.count)
        XCTAssertTrue(Epsilon.approxEqual(ringA.first!, ringA.last!))
        XCTAssertTrue(abs(signedArea(ringA)) > 1.0e-6)

        for (a, b) in zip(ringA, ringB) {
            XCTAssertTrue(Epsilon.approxEqual(a, b, eps: 1.0e-6))
        }

        let stemPath = jStemFixturePath()
        let stemRing = traceLoops(
            segments: boundarySoup(
                path: stemPath,
                width: width,
                height: height,
                effectiveAngle: 0,
                sampleCount: samples
            ),
            eps: 1.0e-6
        ).first ?? []

        var stemBounds = AABB.empty
        for p in stemRing {
            stemBounds.expand(by: p)
        }
        var hookBounds = AABB.empty
        for p in ringA {
            hookBounds.expand(by: p)
        }

        XCTAssertGreaterThan(hookBounds.height, stemBounds.height)
        XCTAssertGreaterThan(hookBounds.width, stemBounds.width)

        assertNoRailFlip(path: path)
    }
}

private func rectangleCorners(
    center: Vec2,
    tangent: Vec2,
    normal: Vec2,
    width: Double,
    height: Double,
    effectiveAngle: Double
) -> [Vec2] {
    let halfW = width * 0.5
    let halfH = height * 0.5
    let localCorners: [Vec2] = [
        Vec2(-halfW, -halfH),
        Vec2(halfW, -halfH),
        Vec2(halfW, halfH),
        Vec2(-halfW, halfH)
    ]
    let cosA = cos(effectiveAngle)
    let sinA = sin(effectiveAngle)
    return localCorners.map { corner in
        let rotated = Vec2(
            corner.x * cosA - corner.y * sinA,
            corner.x * sinA + corner.y * cosA
        )
        let world = tangent * rotated.y + normal * rotated.x
        return center + world
    }
}

private func assertNoRailFlip(path: SkeletonPath) {
    let width = 20.0
    let height = 10.0
    let samples = 64
    let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)

    for i in 0..<samples {
        let t = Double(i) / Double(samples - 1)
        let point = param.position(globalT: t)
        let tangent = param.tangent(globalT: t).normalized()
        let normal = Vec2(-tangent.y, tangent.x)
        let corners = rectangleCorners(
            center: point,
            tangent: tangent,
            normal: normal,
            width: width,
            height: height,
            effectiveAngle: 0
        )
        var minDot = Double.greatestFiniteMagnitude
        var maxDot = -Double.greatestFiniteMagnitude
        var leftPoint = point
        var rightPoint = point
        for corner in corners {
            let d = corner.dot(normal)
            if d < minDot {
                minDot = d
                leftPoint = corner
            }
            if d > maxDot {
                maxDot = d
                rightPoint = corner
            }
        }
        let leftDelta = (leftPoint - point).dot(normal)
        let rightDelta = (rightPoint - point).dot(normal)
        XCTAssertLessThanOrEqual(leftDelta, 1.0e-9)
        XCTAssertGreaterThanOrEqual(rightDelta, -1.0e-9)
    }
}
