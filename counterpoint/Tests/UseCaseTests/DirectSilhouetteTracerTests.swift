import XCTest
@testable import Domain
@testable import UseCases
@testable import Adapters

final class DirectSilhouetteTracerTests: XCTestCase {
    private let tolerance = 1.0e-6

    func testDirectStraightLineThetaZero() {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 33, y: 0),
                    p2: Point(x: 66, y: 0),
                    p3: Point(x: 100, y: 0)
                )
            ]),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )
        let samples = makeUseCase().generateSamples(for: spec)
        let result = DirectSilhouetteTracer.trace(samples: samples)
        XCTAssertEqual(result.outline.isEmpty, false)
        XCTAssertEqual(result.outline.count >= 4, true)
        let bounds = boundsOf(ring: result.outline)
        XCTAssertEqual(bounds.minX, -5.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxX, 105.0, accuracy: tolerance)
        XCTAssertEqual(bounds.minY, -10.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxY, 10.0, accuracy: tolerance)
    }

    func testDirectStraightLineThetaNinety() {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 33, y: 0),
                    p2: Point(x: 66, y: 0),
                    p3: Point(x: 100, y: 0)
                )
            ]),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(.pi / 2),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )
        let samples = makeUseCase().generateSamples(for: spec)
        let result = DirectSilhouetteTracer.trace(samples: samples)
        let bounds = boundsOf(ring: result.outline)
        XCTAssertEqual(bounds.minX, -10.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxX, 110.0, accuracy: tolerance)
        XCTAssertEqual(bounds.minY, -5.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxY, 5.0, accuracy: tolerance)
    }

    func testDirectTangentRelativeIsDeterministic() {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 30, y: 40),
                    p2: Point(x: 70, y: -40),
                    p3: Point(x: 100, y: 0)
                )
            ]),
            width: ParamTrack.constant(12),
            height: ParamTrack.constant(6),
            theta: ParamTrack.constant(0.2),
            angleMode: .tangentRelative,
            sampling: SamplingSpec()
        )
        let samples = makeUseCase().generateSamples(for: spec)
        let first = DirectSilhouetteTracer.trace(samples: samples).outline
        let second = DirectSilhouetteTracer.trace(samples: samples).outline
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
        XCTAssertFalse(first.contains { $0.x.isNaN || $0.y.isNaN })
    }

    func testDirectCornerRefineAddsSamplesDeterministic() {
        let samples = [
            makeSample(point: Point(x: 0, y: 0), tangentAngle: 0.0, t: 0.0, u: 0.0),
            makeSample(point: Point(x: 10, y: 0), tangentAngle: .pi / 2, t: 1.0, u: 1.0)
        ]
        let refined = DirectSilhouetteTracer.trace(samples: samples).outline
        let unrefined = DirectSilhouetteTracer.trace(
            samples: samples,
            options: DirectSilhouetteOptions(enableCornerRefine: false)
        ).outline
        XCTAssertGreaterThan(refined.count, unrefined.count)
        let refinedSecond = DirectSilhouetteTracer.trace(samples: samples).outline
        XCTAssertEqual(refined, refinedSecond)
        XCTAssertFalse(refined.contains { $0.x.isNaN || $0.y.isNaN })
    }

    func testRailRefineUsesSampleProviderForCurvedMidpoint() {
        let curve = CubicBezier(
            p0: Point(x: 0, y: 0),
            p1: Point(x: 0, y: 80),
            p2: Point(x: 100, y: 80),
            p3: Point(x: 100, y: 0)
        )

        func sampleAt(_ t: Double) -> Sample {
            let point = curve.point(at: t)
            let tangentAngle = curve.safeTangentAngle(at: t)
            return Sample(
                uGeom: t,
                uGrid: t,
                t: t,
                point: point,
                tangentAngle: tangentAngle,
                width: 0.0,
                widthLeft: 0.0,
                widthRight: 0.0,
                height: 0.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            )
        }

        let samples = [sampleAt(0.0), sampleAt(1.0)]
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: true, railRefineMaxDepth: 6, railRefineMinStep: 1.0e-6)
        let unrefined = DirectSilhouetteTracer.trace(samples: samples, railTolerance: 10.0, options: options)
        let refined = DirectSilhouetteTracer.trace(
            samples: samples,
            railTolerance: 10.0,
            options: options,
            sampleProvider: { sampleAt($0) }
        )
        XCTAssertEqual(unrefined.leftRail.count, 2)
        XCTAssertGreaterThan(refined.leftRail.count, 2)
    }

    func testRailsStitchBreakCreatesMultipleRuns() {
        let samples = [
            makeSample(point: Point(x: 0, y: 0), tangentAngle: 0.0, t: 0.0, u: 0.0),
            makeSample(point: Point(x: 1, y: 0), tangentAngle: 0.0, t: 0.1, u: 0.1),
            makeSample(point: Point(x: 100, y: 0), tangentAngle: 0.0, t: 0.2, u: 0.2),
            makeSample(point: Point(x: 101, y: 0), tangentAngle: 0.0, t: 0.3, u: 0.3)
        ]
        let result = DirectSilhouetteTracer.trace(samples: samples, railSplitThreshold: 5.0)
        XCTAssertGreaterThan(result.leftRailRuns.count, 1)
        XCTAssertGreaterThan(result.rightRailRuns.count, 1)
        XCTAssertNotNil(result.railChain)
        if let chain = result.railChain {
            XCTAssertEqual(chain.runs.count, result.leftRailRuns.count)
            for range in chain.ranges {
                XCTAssertLessThanOrEqual(range.gtStart, range.gtEnd)
            }
        }
    }

    func testRailChordRefineLimitsDeviation() {
        let curve = CubicBezier(
            p0: Point(x: 0, y: 0),
            p1: Point(x: 0, y: 120),
            p2: Point(x: 100, y: 120),
            p3: Point(x: 100, y: 0)
        )

        func sampleAt(_ t: Double) -> Sample {
            let point = curve.point(at: t)
            let tangentAngle = curve.safeTangentAngle(at: t)
            return Sample(
                uGeom: t,
                uGrid: t,
                t: t,
                point: point,
                tangentAngle: tangentAngle,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            )
        }

        let samples = [sampleAt(0.0), sampleAt(1.0)]
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: false, railRefineMaxDepth: 12, railRefineMinStep: 1.0e-4)
        let tolerance = 0.25
        let result = DirectSilhouetteTracer.trace(
            samples: samples,
            railChordTolerance: tolerance,
            options: options,
            sampleProvider: { sampleAt($0) }
        )
        XCTAssertGreaterThan(result.leftRailSamples.count, 2)
        let maxError = max(
            maxChordError(samples: result.leftRailSamples, sampleAt: sampleAt, side: .left),
            maxChordError(samples: result.rightRailSamples, sampleAt: sampleAt, side: .right)
        )
        XCTAssertLessThanOrEqual(maxError, tolerance * 1.05)
    }

    func testRailChordRefineLimitsSegmentLength() {
        let curve = CubicBezier(
            p0: Point(x: 0, y: 0),
            p1: Point(x: 100, y: 20),
            p2: Point(x: 200, y: 20),
            p3: Point(x: 300, y: 40)
        )

        func sampleAt(_ t: Double) -> Sample {
            let point = curve.point(at: t)
            let tangentAngle = curve.safeTangentAngle(at: t)
            return Sample(
                uGeom: t,
                uGrid: t,
                t: t,
                point: point,
                tangentAngle: tangentAngle,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            )
        }

        let samples = [sampleAt(0.0), sampleAt(1.0)]
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: false, railRefineMaxDepth: 12, railRefineMinStep: 1.0e-4)
        let tolerance = 0.25
        let maxLen = 5.0
        let maxTurn = 1.0
        let result = DirectSilhouetteTracer.trace(
            samples: samples,
            railChordTolerance: tolerance,
            railMaxSegmentLength: maxLen,
            railMaxTurnAngleDegrees: maxTurn,
            options: options,
            sampleProvider: { sampleAt($0) }
        )
        XCTAssertGreaterThan(result.leftRailSamples.count, 2)
        let maxError = max(
            maxChordError(samples: result.leftRailSamples, sampleAt: sampleAt, side: .left),
            maxChordError(samples: result.rightRailSamples, sampleAt: sampleAt, side: .right)
        )
        XCTAssertLessThanOrEqual(maxError, tolerance * 1.05)
        let maxSegment = max(
            maxSegmentLength(samples: result.leftRailSamples),
            maxSegmentLength(samples: result.rightRailSamples)
        )
        XCTAssertLessThanOrEqual(maxSegment, maxLen * 1.05)
        let maxTurnRemaining = max(
            maxTurnAngleDegrees(samples: result.leftRailSamples, sampleAt: sampleAt),
            maxTurnAngleDegrees(samples: result.rightRailSamples, sampleAt: sampleAt)
        )
        XCTAssertLessThanOrEqual(maxTurnRemaining, maxTurn * 1.05)

        let summary = DirectSilhouetteTracer.railRefinementSummaryForTest(
            samples: samples,
            tolerance: tolerance,
            maxSegmentLength: maxLen,
            maxTurnAngleDegrees: maxTurn,
            maxDepth: options.railRefineMaxDepth,
            minParamStep: options.railRefineMinStep,
            sampleProvider: { sampleAt($0) }
        )
        XCTAssertEqual(summary.insertedTotal, summary.insertedChordOnly + summary.insertedLengthOnly + summary.insertedBoth)
    }

    func testRailRefineIgnoresLargeMinStep() {
        let curve = CubicBezier(
            p0: Point(x: 0, y: 0),
            p1: Point(x: 0, y: 80),
            p2: Point(x: 100, y: 80),
            p3: Point(x: 100, y: 0)
        )

        func sampleAt(_ t: Double) -> Sample {
            let point = curve.point(at: t)
            let tangentAngle = curve.safeTangentAngle(at: t)
            return Sample(
                uGeom: t,
                uGrid: t,
                t: t,
                point: point,
                tangentAngle: tangentAngle,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            )
        }

        let samples = [sampleAt(0.0), sampleAt(1.0)]
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: false, railRefineMaxDepth: 8, railRefineMinStep: 0.5)
        let result = DirectSilhouetteTracer.trace(
            samples: samples,
            railChordTolerance: 0.25,
            railMaxSegmentLength: 2.0,
            railMaxTurnAngleDegrees: 2.0,
            options: options,
            sampleProvider: { sampleAt($0) }
        )
        XCTAssertGreaterThan(result.leftRailSamples.count, 2)
    }

    func testRailMaxSegmentDiagnosticUsesRailSamplesOnly() throws {
        let samples: [DirectSilhouetteTracer.RailSample] = [
            DirectSilhouetteTracer.RailSample(t: 0.0, point: Point(x: 0, y: 0), normal: Point(x: 0, y: 1)),
            DirectSilhouetteTracer.RailSample(t: 0.5, point: Point(x: 10, y: 0), normal: Point(x: 0, y: 1)),
            DirectSilhouetteTracer.RailSample(t: 1.0, point: Point(x: 11, y: 0), normal: Point(x: 0, y: 1))
        ]
        let diagnostic = DirectSilhouetteTracer.maxRailSegmentLengthForTest(samples: samples)
        XCTAssertEqual(diagnostic.length, 10.0, accuracy: 1.0e-6)
        let interval = try XCTUnwrap(diagnostic.interval)
        XCTAssertEqual(interval.0, 0.0, accuracy: 1.0e-6)
        XCTAssertEqual(interval.1, 0.5, accuracy: 1.0e-6)
    }

    func testRailSupportPrefersEdgeMidpointForNearlyHorizontalDirection() {
        let sample = Sample(
            uGeom: 0.0,
            uGrid: 0.0,
            t: 0.0,
            point: Point(x: 0, y: 0),
            tangentAngle: (.pi / 2.0) + 1.0e-7,
            width: 40.0,
            widthLeft: 20.0,
            widthRight: 20.0,
            height: 6.0,
            theta: 0.0,
            effectiveRotation: 0.0,
            alpha: 0.0
        )
        let left = DirectSilhouetteTracer.leftRailPoint(sample: sample)
        XCTAssertEqual(left.y, 0.0, accuracy: 1.0e-4)
    }

    func testRailSupportContinuityAvoidsOppositeCornerTeleport() {
        let sample0 = Sample(
            uGeom: 0.0,
            uGrid: 0.0,
            t: 0.0,
            point: Point(x: 0, y: 0),
            tangentAngle: -(.pi / 4.0),
            width: 100.0,
            widthLeft: 50.0,
            widthRight: 50.0,
            height: 6.0,
            theta: 0.0,
            effectiveRotation: 0.0,
            alpha: 0.0
        )
        let sample1 = Sample(
            uGeom: 1.0,
            uGrid: 1.0,
            t: 1.0,
            point: Point(x: 0, y: 0),
            tangentAngle: -(.pi / 4.0),
            width: 100.0,
            widthLeft: 50.0,
            widthRight: 50.0,
            height: 6.0,
            theta: 0.0,
            effectiveRotation: Double.pi,
            alpha: 0.0
        )
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: false)
        let result = DirectSilhouetteTracer.trace(
            samples: [sample0, sample1],
            railChordTolerance: 0.0,
            railMaxSegmentLength: 0.0,
            railMaxTurnAngleDegrees: 0.0,
            options: options
        )
        XCTAssertEqual(result.leftRail.count, 2)
        XCTAssertEqual(result.rightRail.count, 2)
        let leftSeg = (result.leftRail[1] - result.leftRail[0]).length
        let rightSeg = (result.rightRail[1] - result.rightRail[0]).length
        XCTAssertLessThan(leftSeg, 10.0)
        XCTAssertLessThan(rightSeg, 10.0)
    }

    func testRailSupportSideSignRemainsStable() {
        let angles: [Double] = [0.0, 0.3, 0.6, 0.9, 1.2]
        let samples = angles.enumerated().map { index, theta in
            Sample(
                uGeom: Double(index) / Double(angles.count - 1),
                uGrid: Double(index) / Double(angles.count - 1),
                t: Double(index) / Double(angles.count - 1),
                point: Point(x: 0, y: 0),
                tangentAngle: 0.0,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: theta,
                alpha: 0.0
            )
        }
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: false)
        let result = DirectSilhouetteTracer.trace(
            samples: samples,
            railChordTolerance: 0.0,
            railMaxSegmentLength: 0.0,
            railMaxTurnAngleDegrees: 0.0,
            options: options
        )
        let tangent = Point(x: 1.0, y: 0.0)
        func sideSign(_ point: Point) -> Double {
            let cross = tangent.x * point.y - tangent.y * point.x
            if abs(cross) <= 1.0e-6 { return 0.0 }
            return cross < 0.0 ? -1.0 : 1.0
        }
        let leftSigns = result.leftRail.map { sideSign($0) }
        let rightSigns = result.rightRail.map { sideSign($0) }
        let leftTarget = leftSigns.first ?? 0.0
        let rightTarget = rightSigns.first ?? 0.0
        XCTAssertNotEqual(leftTarget, 0.0)
        XCTAssertNotEqual(rightTarget, 0.0)
        for sign in leftSigns {
            XCTAssertEqual(sign, leftTarget)
        }
        for sign in rightSigns {
            XCTAssertEqual(sign, rightTarget)
        }
    }

    func testRailNormalsRemainConsistent() {
        let samples: [Sample] = [
            Sample(
                uGeom: 0.0,
                uGrid: 0.0,
                t: 0.0,
                point: Point(x: 0, y: 0),
                tangentAngle: 0.0,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            ),
            Sample(
                uGeom: 0.5,
                uGrid: 0.5,
                t: 0.5,
                point: Point(x: 10, y: 0),
                tangentAngle: Double.pi,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            ),
            Sample(
                uGeom: 1.0,
                uGrid: 1.0,
                t: 1.0,
                point: Point(x: 20, y: 0),
                tangentAngle: 0.0,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            )
        ]
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: false)
        let result = DirectSilhouetteTracer.trace(
            samples: samples,
            railChordTolerance: 0.0,
            railMaxSegmentLength: 0.0,
            railMaxTurnAngleDegrees: 0.0,
            options: options
        )
        for i in 1..<result.leftRailSamples.count {
            let prev = result.leftRailSamples[i - 1].normal
            let curr = result.leftRailSamples[i].normal
            XCTAssertGreaterThanOrEqual(prev.dot(curr), 0.0)
        }
    }

    func testRailSamplesAvoidLargeJumps() {
        let angles: [Double] = [0.0, 0.8, 1.6, 2.4, 3.2]
        let samples = angles.enumerated().map { index, theta in
            Sample(
                uGeom: Double(index) / Double(angles.count - 1),
                uGrid: Double(index) / Double(angles.count - 1),
                t: Double(index) / Double(angles.count - 1),
                point: Point(x: Double(index) * 5.0, y: 0),
                tangentAngle: 0.0,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: theta,
                alpha: 0.0
            )
        }
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: false)
        let result = DirectSilhouetteTracer.trace(
            samples: samples,
            railChordTolerance: 0.0,
            railMaxSegmentLength: 0.0,
            railMaxTurnAngleDegrees: 0.0,
            options: options
        )
        let maxLeft = maxSegmentLength(samples: result.leftRailSamples)
        let maxRight = maxSegmentLength(samples: result.rightRailSamples)
        XCTAssertLessThan(maxLeft, 10.0)
        XCTAssertLessThan(maxRight, 10.0)
    }

    func testRailRunSplittingSelectsDominantRun() {
        let samples: [Sample] = [
            Sample(
                uGeom: 0.0,
                uGrid: 0.0,
                t: 0.0,
                point: Point(x: 0, y: 0),
                tangentAngle: 0.0,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            ),
            Sample(
                uGeom: 0.5,
                uGrid: 0.5,
                t: 0.5,
                point: Point(x: 1, y: 0),
                tangentAngle: 0.0,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            ),
            Sample(
                uGeom: 1.0,
                uGrid: 1.0,
                t: 1.0,
                point: Point(x: 100, y: 0),
                tangentAngle: 0.0,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            )
        ]
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: false)
        let result = DirectSilhouetteTracer.trace(
            samples: samples,
            railSplitThreshold: 20.0,
            options: options
        )
        XCTAssertEqual(result.leftRailRuns.count, 2)
        XCTAssertEqual(result.rightRailRuns.count, 2)
        let maxLeft = maxSegmentLength(samples: result.leftRailSamples)
        let maxRight = maxSegmentLength(samples: result.rightRailSamples)
        XCTAssertLessThan(maxLeft, 20.0)
        XCTAssertLessThan(maxRight, 20.0)
    }

    func testRailRefineSkipsJumpSeams() {
        func sampleAt(_ t: Double) -> Sample {
            Sample(
                uGeom: t,
                uGrid: t,
                t: t,
                point: Point(x: t * 100.0, y: 0.0),
                tangentAngle: 0.0,
                width: 40.0,
                widthLeft: 20.0,
                widthRight: 20.0,
                height: 6.0,
                theta: 0.0,
                effectiveRotation: 0.0,
                alpha: 0.0
            )
        }
        let samples = [sampleAt(0.0), sampleAt(1.0)]
        let options = DirectSilhouetteOptions(enableCornerRefine: false, enableRailRefine: false, railRefineMaxDepth: 6, railRefineMinStep: 0.0)
        let summary = DirectSilhouetteTracer.railRefinementSummaryForTest(
            samples: samples,
            tolerance: 0.25,
            maxSegmentLength: 1.0,
            maxTurnAngleDegrees: 1.0,
            maxDepth: options.railRefineMaxDepth,
            minParamStep: options.railRefineMinStep,
            sampleProvider: { sampleAt($0) }
        )
        XCTAssertGreaterThan(summary.jumpSeamsSkipped, 0)
        XCTAssertEqual(summary.insertedTotal, summary.insertedChordOnly + summary.insertedLengthOnly + summary.insertedBoth)
    }

    func testRingMaxTurnDegrees() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 10, y: 0),
            Point(x: 10, y: 10),
            Point(x: 0, y: 10),
            Point(x: 0, y: 0)
        ]
        let diag = DirectSilhouetteTracer.ringMaxTurnDegrees(ring: ring)
        XCTAssertNotNil(diag.index)
        XCTAssertEqual(diag.degrees, 90.0, accuracy: tolerance)
    }

    func testSanitizeRingRemovesHairpin() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 0.0, y: 0.01),
            Point(x: 0, y: 0),
            Point(x: 10, y: 0),
            Point(x: 10, y: 10),
            Point(x: 0, y: 10),
            Point(x: 0, y: 0)
        ]
        let rawDiag = DirectSilhouetteTracer.ringMaxTurnDegrees(ring: ring)
        XCTAssertGreaterThan(rawDiag.degrees, 170.0)
        let cleaned = sanitizeRing(ring, eps: 1.0e-6, hairpinAngleDeg: 179.0, hairpinSpanTol: 0.01)
        let cleanedDiag = DirectSilhouetteTracer.ringMaxTurnDegrees(ring: cleaned)
        XCTAssertLessThan(cleanedDiag.degrees, 170.0)
    }

    private func makeUseCase() -> GenerateStrokeOutlineUseCase {
        GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )
    }

    private func makeSample(point: Point, tangentAngle: Double, t: Double, u: Double) -> Sample {
        Sample(
            uGeom: u,
            uGrid: u,
            t: t,
            point: point,
            tangentAngle: tangentAngle,
            width: 10.0,
            widthLeft: 5.0,
            widthRight: 5.0,
            height: 6.0,
            theta: 0.0,
            effectiveRotation: 0.0,
            alpha: 0.0
        )
    }

    private func boundsOf(ring: Ring) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for point in ring {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return (minX, maxX, minY, maxY)
    }

    private enum RailSide {
        case left
        case right
    }

    private func maxChordError(samples: [DirectSilhouetteTracer.RailSample], sampleAt: (Double) -> Sample, side: RailSide) -> Double {
        guard samples.count >= 2 else { return 0.0 }
        var maxError = 0.0
        for i in 0..<(samples.count - 1) {
            let a = samples[i]
            let b = samples[i + 1]
            let tm = 0.5 * (a.t + b.t)
            let midSample = sampleAt(tm)
            let midPoint = (side == .left) ? DirectSilhouetteTracer.leftRailPoint(sample: midSample) : DirectSilhouetteTracer.rightRailPoint(sample: midSample)
            let error = distancePointToSegment(point: midPoint, a: a.point, b: b.point)
            maxError = max(maxError, error)
        }
        return maxError
    }

    private func maxSegmentLength(samples: [DirectSilhouetteTracer.RailSample]) -> Double {
        guard samples.count >= 2 else { return 0.0 }
        var maxLen = 0.0
        for i in 0..<(samples.count - 1) {
            let length = (samples[i + 1].point - samples[i].point).length
            if length > maxLen { maxLen = length }
        }
        return maxLen
    }

    private func maxTurnAngleDegrees(samples: [DirectSilhouetteTracer.RailSample], sampleAt: (Double) -> Sample) -> Double {
        guard samples.count >= 2 else { return 0.0 }
        var maxTurn = 0.0
        for i in 0..<(samples.count - 1) {
            let a = sampleAt(samples[i].t)
            let b = sampleAt(samples[i + 1].t)
            let delta = angleDeltaRadians(a.tangentAngle, b.tangentAngle)
            let degrees = abs(delta) * 180.0 / Double.pi
            if degrees > maxTurn { maxTurn = degrees }
        }
        return maxTurn
    }

    private func angleDeltaRadians(_ a: Double, _ b: Double) -> Double {
        var delta = b - a
        let twoPi = 2.0 * Double.pi
        while delta > Double.pi { delta -= twoPi }
        while delta < -Double.pi { delta += twoPi }
        return delta
    }

    private func distancePointToSegment(point: Point, a: Point, b: Point) -> Double {
        let ab = b - a
        let ap = point - a
        let denom = ab.dot(ab)
        if denom <= 1.0e-12 {
            return ap.length
        }
        let t = max(0.0, min(1.0, ap.dot(ab) / denom))
        let proj = a + ab * t
        return (point - proj).length
    }
}
