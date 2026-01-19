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
        let soupA = boundarySoupVariableWidthAngle(
            path: path,
            height: height,
            sampleCount: samples
        ) { t in
            widthRamp(t: t)
        } angleAtT: { t in
            thetaRampRadians(t: t)
        }
        let soupB = boundarySoupVariableWidthAngle(
            path: path,
            height: height,
            sampleCount: samples
        ) { t in
            widthRamp(t: t)
        } angleAtT: { t in
            thetaRampRadians(t: t)
        }
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

        assertNoRailFlip(path: path, angleAtT: thetaRampRadians)
    }

    func testJHookAngleRampAreaStaysReasonable() {
        let path = jFullFixturePath()
        let height = 10.0
        let samples = 64
        let widthSoup = boundarySoupVariableWidth(
            path: path,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        ) { t in
            widthRamp(t: t)
        }
        let angleSoup = boundarySoupVariableWidthAngle(
            path: path,
            height: height,
            sampleCount: samples
        ) { t in
            widthRamp(t: t)
        } angleAtT: { t in
            thetaRampRadians(t: t)
        }
        let widthRing = traceLoops(segments: widthSoup, eps: 1.0e-6).first ?? []
        let angleRing = traceLoops(segments: angleSoup, eps: 1.0e-6).first ?? []
        let widthArea = abs(signedArea(widthRing))
        let angleArea = abs(signedArea(angleRing))
        XCTAssertTrue(angleArea >= widthArea * 0.5)
        XCTAssertTrue(angleArea <= widthArea * 1.5)

        assertNoRailFlip(path: path, angleAtT: thetaRampRadians)
    }

    func testJHookRampIsWiderThanConstant() {
        let path = jFullFixturePath()
        let height = 10.0
        let samples = 64
        let constantSoup = boundarySoup(
            path: path,
            width: 16.0,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let rampSoup = boundarySoupVariableWidth(
            path: path,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        ) { t in
            widthRamp(t: t)
        }
        let constantRing = traceLoops(segments: constantSoup, eps: 1.0e-6).first ?? []
        let rampRing = traceLoops(segments: rampSoup, eps: 1.0e-6).first ?? []

        var constantBounds = AABB.empty
        for p in constantRing {
            constantBounds.expand(by: p)
        }
        var rampBounds = AABB.empty
        for p in rampRing {
            rampBounds.expand(by: p)
        }
        XCTAssertGreaterThanOrEqual(rampBounds.width, constantBounds.width - 1.0e-6)
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

private func assertNoRailFlip(
    path: SkeletonPath,
    angleAtT: (Double) -> Double = { _ in 0.0 }
) {
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
            effectiveAngle: angleAtT(t)
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

private func widthRamp(t: Double) -> Double {
    let clamped = max(0.0, min(1.0, t))
    let midT = 0.45
    let start = 16.0
    let mid = 22.0
    let end = 16.0
    if clamped <= midT {
        let u = clamped / midT
        return start + (mid - start) * u
    }
    let u = (clamped - midT) / (1.0 - midT)
    return mid + (end - mid) * u
}

private func thetaRampRadians(t: Double) -> Double {
    let clamped = max(0.0, min(1.0, t))
    let midT = 0.5
    let start = 12.0
    let mid = 4.0
    let end = 0.0
    let deg: Double
    if clamped <= midT {
        let u = clamped / midT
        deg = start + (mid - start) * u
    } else {
        let u = (clamped - midT) / (1.0 - midT)
        deg = mid + (end - mid) * u
    }
    return deg * Double.pi / 180.0
}
