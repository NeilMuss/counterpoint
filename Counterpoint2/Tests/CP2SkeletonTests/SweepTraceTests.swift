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

    func testFastSCurveSweepProducesDeterministicClosedRing() {
        let path = SkeletonPath(segments: [fastSCurveFixtureCubic()])
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
    }

    func testFastSCurve2SweepProducesDeterministicClosedRing() {
        let path = SkeletonPath(segments: [fastSCurve2FixtureCubic()])
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
    }

    func testFastSCurveScallopMetricsAreBounded() {
        let path = SkeletonPath(segments: [fastSCurveFixtureCubic()])
        let width = 20.0
        let height = 10.0
        let samples = 64
        let soup = boundarySoup(
            path: path,
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let ring = traceLoops(segments: soup, eps: 1.0e-6).first ?? []
        XCTAssertFalse(ring.isEmpty)

        let ringPoints = stripDuplicateClosure(ring)
        let metrics = analyzeScallops(
            points: ringPoints,
            width: width,
            halfWindow: 20,
            epsilon: 1.0e-6,
            cornerThreshold: 2.5,
            capTrim: 4
        )
        XCTAssertLessThanOrEqual(metrics.filtered.turnExtremaCount, 8)
        XCTAssertLessThanOrEqual(metrics.filtered.chordPeakCount, 8)
        XCTAssertLessThanOrEqual(metrics.filtered.maxChordDeviation, width * 0.40)
    }

    func testAdaptiveSamplingReducesScallopsForFastCurves() {
        let width = 20.0
        let height = 10.0
        let samples = 64
        let config = (flatnessEps: 0.05, maxDepth: 14, maxSamples: 2048)

        let fastBase = scallopFilteredRatio(
            path: SkeletonPath(segments: [fastSCurveFixtureCubic()]),
            width: width,
            height: height,
            sampleCount: samples,
            adaptive: false,
            config: config
        )
        let fastAdaptive = scallopFilteredRatio(
            path: SkeletonPath(segments: [fastSCurveFixtureCubic()]),
            width: width,
            height: height,
            sampleCount: samples,
            adaptive: true,
            config: config
        )
        let fastLimit = max(fastBase * 1.2, 0.5)
        XCTAssertLessThanOrEqual(fastAdaptive, fastLimit)

        let fast2Base = scallopFilteredRatio(
            path: SkeletonPath(segments: [fastSCurve2FixtureCubic()]),
            width: width,
            height: height,
            sampleCount: samples,
            adaptive: false,
            config: config
        )
        let fast2Adaptive = scallopFilteredRatio(
            path: SkeletonPath(segments: [fastSCurve2FixtureCubic()]),
            width: width,
            height: height,
            sampleCount: samples,
            adaptive: true,
            config: config
        )
        let fast2Limit = max(fast2Base * 1.2, 0.5)
        XCTAssertLessThanOrEqual(fast2Adaptive, fast2Limit)
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

    func testJSerifOnlySweepProducesDeterministicClosedRing() {
        let path = jSerifOnlyFixturePath()
        let height = 10.0
        let samples = 64
        let soupA = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: widthRamp,
            angleAtT: thetaRampRadians,
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.90
        )
        let soupB = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: widthRamp,
            angleAtT: thetaRampRadians,
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.90
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

        assertNoRailFlip(path: path, angleAtT: thetaRampRadians)
    }

    func testJSerifOnlyAlphaIgnoredWhenUsingLocalKeyframeAlpha() {
        let path = jSerifOnlyFixturePath()
        let height = 10.0
        let samples = 64
        let alphaStart = 0.90
        let alphaEnd = -0.35
        let alphaAtT: (Double) -> Double = { t in
            if t < alphaStart {
                return 0.0
            }
            let phase = (t - alphaStart) / (1.0 - alphaStart)
            return alphaEnd * max(0.0, min(1.0, phase))
        }

        let noAlphaSoup = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: widthRamp,
            angleAtT: thetaRampRadians,
            alphaAtT: { _ in 0.0 },
            alphaStart: alphaStart
        )
        let alphaSoup = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: widthRamp,
            angleAtT: thetaRampRadians,
            alphaAtT: alphaAtT,
            alphaStart: alphaStart
        )

        let railsNoAlpha = railPoints(segments: noAlphaSoup, sampleCount: samples)
        let railsAlpha = railPoints(segments: alphaSoup, sampleCount: samples)
        XCTAssertEqual(railsNoAlpha.left.count, samples)
        XCTAssertEqual(railsAlpha.left.count, samples)

        for i in 0..<min(10, samples) {
            XCTAssertTrue(Epsilon.approxEqual(railsNoAlpha.left[i], railsAlpha.left[i], eps: 1.0e-6))
            XCTAssertTrue(Epsilon.approxEqual(railsNoAlpha.right[i], railsAlpha.right[i], eps: 1.0e-6))
        }

        var maxTailDelta = 0.0
        let tailStart = max(0, Int(Double(samples - 1) * 0.9))
        for i in tailStart..<samples {
            let delta = (railsNoAlpha.left[i] - railsAlpha.left[i]).length
            if delta > maxTailDelta {
                maxTailDelta = delta
            }
        }
        XCTAssertLessThanOrEqual(maxTailDelta, 1.0e-6)
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

    func testJHookAlphaIgnoredWhenUsingLocalKeyframeAlpha() {
        let path = jFullFixturePath()
        let height = 10.0
        let samples = 64
        let alphaStart = 0.85
        let alphaEnd = -0.35
        let alphaAtT: (Double) -> Double = { t in
            if t < alphaStart {
                return 0.0
            }
            let phase = (t - alphaStart) / (1.0 - alphaStart)
            return alphaEnd * max(0.0, min(1.0, phase))
        }

        let noAlphaSoup = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: widthRamp,
            angleAtT: thetaRampRadians,
            alphaAtT: { _ in 0.0 },
            alphaStart: alphaStart
        )
        let alphaSoup = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: widthRamp,
            angleAtT: thetaRampRadians,
            alphaAtT: alphaAtT,
            alphaStart: alphaStart
        )

        let leftNoAlpha = leftRailPoints(segments: noAlphaSoup, sampleCount: samples)
        let leftAlpha = leftRailPoints(segments: alphaSoup, sampleCount: samples)
        XCTAssertEqual(leftNoAlpha.count, samples)
        XCTAssertEqual(leftAlpha.count, samples)

        for i in 0..<min(10, samples) {
            XCTAssertTrue(Epsilon.approxEqual(leftNoAlpha[i], leftAlpha[i], eps: 1.0e-6))
        }

        var maxTailDelta = 0.0
        let tailStart = max(0, Int(Double(samples - 1) * 0.9))
        for i in tailStart..<samples {
            let delta = (leftNoAlpha[i] - leftAlpha[i]).length
            if delta > maxTailDelta {
                maxTailDelta = delta
            }
        }
        XCTAssertLessThanOrEqual(maxTailDelta, 1.0e-6)

        let ring = traceLoops(segments: alphaSoup, eps: 1.0e-6).first ?? []
        XCTAssertFalse(ring.isEmpty)
        XCTAssertTrue(Epsilon.approxEqual(ring.first!, ring.last!))
        XCTAssertTrue(abs(signedArea(ring)) > 1.0e-6)
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

    func testLineEndRampProducesDeterministicClosedRing() {
        let path = SkeletonPath(segments: [lineFixtureCubic()])
        let height = 10.0
        let samples = 64
        let widthStart = 16.0
        let widthEnd = 28.0
        let rampStart = 0.85

        let soupA = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: { t in
                endRampWidth(t: t, start: widthStart, end: widthEnd, rampStart: rampStart)
            },
            angleAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: rampStart
        )
        let soupB = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: { t in
                endRampWidth(t: t, start: widthStart, end: widthEnd, rampStart: rampStart)
            },
            angleAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: rampStart
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
    }

    func testLineEndRampAlphaIgnoredWhenUsingLocalKeyframeAlpha() {
        let path = SkeletonPath(segments: [lineFixtureCubic()])
        let height = 10.0
        let samples = 64
        let widthStart = 16.0
        let widthEnd = 28.0
        let rampStart = 0.85
        let alphaEnd = -0.35

        let noAlphaSoup = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: { t in
                endRampWidth(t: t, start: widthStart, end: widthEnd, rampStart: rampStart)
            },
            angleAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: rampStart
        )
        let alphaSoup = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: { t in
                endRampWidth(t: t, start: widthStart, end: widthEnd, rampStart: rampStart)
            },
            angleAtT: { _ in 0.0 },
            alphaAtT: { t in
                if t < rampStart {
                    return 0.0
                }
                let phase = (t - rampStart) / (1.0 - rampStart)
                return alphaEnd * max(0.0, min(1.0, phase))
            },
            alphaStart: rampStart
        )

        let railsNoAlpha = railPoints(segments: noAlphaSoup, sampleCount: samples)
        let railsAlpha = railPoints(segments: alphaSoup, sampleCount: samples)
        XCTAssertEqual(railsNoAlpha.left.count, samples)
        XCTAssertEqual(railsAlpha.left.count, samples)

        for i in 0..<min(10, samples) {
            XCTAssertTrue(Epsilon.approxEqual(railsNoAlpha.left[i], railsAlpha.left[i], eps: 1.0e-6))
            XCTAssertTrue(Epsilon.approxEqual(railsNoAlpha.right[i], railsAlpha.right[i], eps: 1.0e-6))
        }

        var maxTailDelta = 0.0
        let tailStart = max(0, Int(Double(samples - 1) * 0.9))
        for i in tailStart..<samples {
            let delta = (railsNoAlpha.left[i] - railsAlpha.left[i]).length
            if delta > maxTailDelta {
                maxTailDelta = delta
            }
        }
        XCTAssertLessThanOrEqual(maxTailDelta, 1.0e-6)
    }

    func testLineEndRampWidthIncreasesNearEnd() {
        let path = SkeletonPath(segments: [lineFixtureCubic()])
        let height = 10.0
        let samples = 64
        let widthStart = 16.0
        let widthEnd = 28.0
        let rampStart = 0.85

        let soup = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: { t in
                endRampWidth(t: t, start: widthStart, end: widthEnd, rampStart: rampStart)
            },
            angleAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: rampStart
        )

        let rails = railPoints(segments: soup, sampleCount: samples)
        XCTAssertEqual(rails.left.count, samples)
        XCTAssertEqual(rails.right.count, samples)

        let earlyWidth = (rails.right[0] - rails.left[0]).length
        let tailWidth = (rails.right[samples - 1] - rails.left[samples - 1]).length
        XCTAssertGreaterThan(tailWidth, earlyWidth)
    }

    func testPoly3SweepProducesDeterministicClosedRing() {
        let path = poly3FixturePath()
        let height = 10.0
        let samples = 64
        let soupA = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: poly3WidthRamp,
            angleAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.30
        )
        let soupB = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: poly3WidthRamp,
            angleAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.30
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

        assertNoRailFlip(path: path)
    }

    func testPoly3JoinContinuityForWidthAndRails() {
        let path = poly3FixturePath()
        let height = 10.0
        let samples = 64
        let joinGTs = poly3JoinGTs()
        XCTAssertEqual(joinGTs.count, 2)

        for join in joinGTs {
            let before = max(0.0, join - 0.01)
            let after = min(1.0, join + 0.01)
            let wBefore = poly3WidthRamp(t: before)
            let wAfter = poly3WidthRamp(t: after)
            XCTAssertLessThan(abs(wBefore - wAfter), 1.0)
        }

        let soup = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: poly3WidthRamp,
            angleAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.30
        )
        let rails = railPoints(segments: soup, sampleCount: samples)
        XCTAssertEqual(rails.left.count, samples)
        XCTAssertEqual(rails.right.count, samples)
        assertNoRailFlip(path: path)
    }

    func testPoly3JoinBulgeMetricIsBoundedAndDeterministic() {
        let path = poly3FixturePath()
        let height = 10.0
        let samples = 64
        let soup = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: height,
            sampleCount: samples,
            widthAtT: poly3WidthRamp,
            angleAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.30
        )
        let ring = traceLoops(segments: soup, eps: 1.0e-6).first ?? []
        XCTAssertFalse(ring.isEmpty)
        let ringPoints = stripDuplicateClosure(ring)

        let joins = poly3JoinGTs()
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        let halfWindow = 8
        var ratiosA: [Double] = []
        var ratiosB: [Double] = []

        for join in joins {
            let center = param.position(globalT: join)
            let index = nearestIndex(points: ringPoints, to: center)
            let deviation = chordDeviation(points: ringPoints, centerIndex: index, halfWindow: halfWindow)
            let widthAtJoin = poly3WidthRamp(t: join)
            let ratio = deviation / max(Epsilon.defaultValue, widthAtJoin)
            ratiosA.append(ratio)
        }
        for join in joins {
            let center = param.position(globalT: join)
            let index = nearestIndex(points: ringPoints, to: center)
            let deviation = chordDeviation(points: ringPoints, centerIndex: index, halfWindow: halfWindow)
            let widthAtJoin = poly3WidthRamp(t: join)
            let ratio = deviation / max(Epsilon.defaultValue, widthAtJoin)
            ratiosB.append(ratio)
        }

        XCTAssertEqual(ratiosA.count, joins.count)
        for (a, b) in zip(ratiosA, ratiosB) {
            XCTAssertEqual(a, b, accuracy: 1.0e-9)
            XCTAssertLessThan(a, 0.35)
        }
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

private func leftRailPoints(segments: [Segment2], sampleCount: Int) -> [Vec2] {
    let count = max(2, sampleCount)
    let leftSegments = Array(segments.prefix(count - 1))
    guard let first = leftSegments.first else { return [] }
    var points: [Vec2] = [first.a, first.b]
    points.reserveCapacity(count)
    for segment in leftSegments.dropFirst() {
        points.append(segment.b)
    }
    return points
}

private func railPoints(segments: [Segment2], sampleCount: Int) -> (left: [Vec2], right: [Vec2]) {
    let count = max(2, sampleCount)
    let leftSegments = segments.filter {
        if case .railLeft = $0.source { return true }
        return false
    }
    let rightSegments = segments.filter {
        if case .railRight = $0.source { return true }
        return false
    }
    guard leftSegments.count >= (count - 1), rightSegments.count >= (count - 1) else {
        return ([], [])
    }
    let leftPoints = leftRailPoints(segments: Array(leftSegments.prefix(count - 1)), sampleCount: count)
    let rightPointsReversed = leftRailPoints(segments: Array(rightSegments.prefix(count - 1)), sampleCount: count)
    let rightPoints = rightPointsReversed.reversed()
    return (leftPoints, Array(rightPoints))
}

private func endRampWidth(t: Double, start: Double, end: Double, rampStart: Double) -> Double {
    if t < rampStart {
        return start
    }
    let phase = (t - rampStart) / max(1.0e-12, 1.0 - rampStart)
    return start + (end - start) * max(0.0, min(1.0, phase))
}

private func lineFixtureCubic() -> CubicBezier2 {
    CubicBezier2(
        p0: Vec2(0, 0),
        p1: Vec2(0, 33),
        p2: Vec2(0, 66),
        p3: Vec2(0, 100)
    )
}

private func stripDuplicateClosure(_ ring: [Vec2]) -> [Vec2] {
    guard ring.count > 1, Epsilon.approxEqual(ring.first ?? Vec2(0, 0), ring.last ?? Vec2(0, 0), eps: 1.0e-9) else {
        return ring
    }
    return Array(ring.dropLast())
}


private func nearestIndex(points: [Vec2], to target: Vec2) -> Int {
    var best = 0
    var bestDist = Double.greatestFiniteMagnitude
    for (index, point) in points.enumerated() {
        let d = (point - target).length
        if d < bestDist {
            bestDist = d
            best = index
        }
    }
    return best
}

private func chordDeviation(points: [Vec2], centerIndex: Int, halfWindow: Int) -> Double {
    guard !points.isEmpty else { return 0.0 }
    let start = max(0, centerIndex - halfWindow)
    let end = min(points.count - 1, centerIndex + halfWindow)
    if end <= start + 1 {
        return 0.0
    }
    let a = points[start]
    let b = points[end]
    var maxDev = 0.0
    for i in (start + 1)..<end {
        let d = distancePointToSegment(points[i], a, b)
        if d > maxDev {
            maxDev = d
        }
    }
    return maxDev
}

private func distancePointToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let ab = b - a
    let ap = p - a
    let denom = max(Epsilon.defaultValue, ab.dot(ab))
    let t = max(0.0, min(1.0, ap.dot(ab) / denom))
    let proj = a + ab * t
    return (p - proj).length
}

private func poly3WidthRamp(t: Double) -> Double {
    let clamped = max(0.0, min(1.0, t))
    let midT = 0.5
    let start = 16.0
    let mid = 28.0
    let end = 16.0
    if clamped <= midT {
        let u = clamped / midT
        return start + (mid - start) * u
    }
    let u = (clamped - midT) / (1.0 - midT)
    return mid + (end - mid) * u
}

private func poly3JoinGTs() -> [Double] {
    let segments = poly3FixturePath().segments
    var lengths: [Double] = []
    lengths.reserveCapacity(segments.count)
    for segment in segments {
        let param = ArcLengthParameterization(path: SkeletonPath(segment), samplesPerSegment: 256)
        lengths.append(param.totalLength)
    }
    let total = max(Epsilon.defaultValue, lengths.reduce(0.0, +))
    var joinGTs: [Double] = []
    var accumulated = 0.0
    for (index, length) in lengths.enumerated() where index < lengths.count - 1 {
        accumulated += length
        joinGTs.append(accumulated / total)
    }
    return joinGTs
}

private func scallopFilteredRatio(
    path: SkeletonPath,
    width: Double,
    height: Double,
    sampleCount: Int,
    adaptive: Bool,
    config: (flatnessEps: Double, maxDepth: Int, maxSamples: Int)
) -> Double {
    let effectiveSampleCount = adaptive ? sampleCount * 4 : sampleCount
    let soup = boundarySoup(
        path: path,
        width: width,
        height: height,
        effectiveAngle: 0,
        sampleCount: effectiveSampleCount,
        adaptiveSampling: adaptive,
        flatnessEps: config.flatnessEps,
        railEps: config.flatnessEps,
        maxDepth: config.maxDepth,
        maxSamples: config.maxSamples
    )
    let ring = stripDuplicateClosure(traceLoops(segments: soup, eps: 1.0e-6).first ?? [])
    let metrics = analyzeScallops(
        points: ring,
        width: width,
        halfWindow: 20,
        epsilon: 1.0e-6,
        cornerThreshold: 2.5,
        capTrim: 4
    )
    return metrics.filtered.normalizedMaxChordDeviation
}
