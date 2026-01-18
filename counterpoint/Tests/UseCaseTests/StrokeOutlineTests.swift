import XCTest
@testable import Domain
@testable import UseCases
@testable import Adapters

final class StrokeOutlineTests: XCTestCase {
    private let tolerance = 0.75

    func testStraightLineAbsoluteZeroBoundingBox() throws {
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

        let outline = try makeUseCase().generateOutline(for: spec)
        let bounds = boundsOf(polygons: outline)

        XCTAssertEqual(bounds.minX, -5.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxX, 105.0, accuracy: tolerance)
        XCTAssertEqual(bounds.minY, -10.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxY, 10.0, accuracy: tolerance)
    }

    func testStraightLineAbsoluteNinetyDegreesBoundingBox() throws {
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

        let outline = try makeUseCase().generateOutline(for: spec)
        let bounds = boundsOf(polygons: outline)

        XCTAssertEqual(bounds.minX, -10.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxX, 110.0, accuracy: tolerance)
        XCTAssertEqual(bounds.minY, -5.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxY, 5.0, accuracy: tolerance)
    }

    func testLShapeProducesClosedNonEmptyRings() throws {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 33, y: 0),
                    p2: Point(x: 66, y: 0),
                    p3: Point(x: 100, y: 0)
                ),
                CubicBezier(
                    p0: Point(x: 100, y: 0),
                    p1: Point(x: 100, y: 33),
                    p2: Point(x: 100, y: 66),
                    p3: Point(x: 100, y: 100)
                )
            ]),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let outline = try makeUseCase().generateOutline(for: spec)
        XCTAssertFalse(outline.isEmpty)

        for polygon in outline {
            XCTAssertGreaterThan(polygon.outer.count, 3)
            XCTAssertEqual(polygon.outer.first, polygon.outer.last)
            for point in polygon.outer {
                XCTAssertTrue(point.x.isFinite)
                XCTAssertTrue(point.y.isFinite)
            }
        }

        let bounds = boundsOf(polygons: outline)
        XCTAssertLessThanOrEqual(bounds.minX, -5.0 + tolerance)
        XCTAssertGreaterThanOrEqual(bounds.maxX, 105.0 - tolerance)
        XCTAssertLessThanOrEqual(bounds.minY, -10.0 + tolerance)
        XCTAssertGreaterThanOrEqual(bounds.maxY, 110.0 - tolerance)
    }

    func testTangentRelativeEffectiveRotationMatchesTangentPlusTheta() {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 25, y: 50),
                    p2: Point(x: 75, y: -50),
                    p3: Point(x: 100, y: 0)
                )
            ]),
            width: ParamTrack.constant(12),
            height: ParamTrack.constant(18),
            theta: ParamTrack.constant(0.3),
            angleMode: .tangentRelative,
            sampling: SamplingSpec()
        )

        let samples = makeUseCase().generateSamples(for: spec)
        let probeIndices = [0, samples.count / 2, max(0, samples.count - 1)]
        for index in probeIndices {
            let sample = samples[index]
            let expected = sample.tangentAngle + sample.theta
            let delta = AngleMath.angularDifference(sample.effectiveRotation, expected)
            XCTAssertLessThan(abs(delta), 0.05)
        }
    }

    func testTangentRelativePhaseDefaultsAndPhaseNinetyAffectsBounds() throws {
        let path = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 0, y: 0),
                p2: Point(x: 0, y: 100),
                p3: Point(x: 0, y: 100)
            )
        ])

        let baseSpec = StrokeSpec(
            path: path,
            width: ParamTrack.constant(40),
            widthLeft: ParamTrack.constant(20),
            widthRight: ParamTrack.constant(20),
            height: ParamTrack.constant(6),
            theta: ParamTrack.constant(0),
            angleMode: .tangentRelative,
            sampling: SamplingSpec()
        )

        let outlineDefault = try makeUseCase().generateOutline(for: baseSpec)
        let boundsDefault = boundsOf(polygons: outlineDefault)
        XCTAssertEqual(boundsDefault.maxX - boundsDefault.minX, 6.0, accuracy: 1.0)

        var phaseSpec = baseSpec
        phaseSpec.tangentPhaseDegrees = 90.0
        let outlinePhase = try makeUseCase().generateOutline(for: phaseSpec)
        let boundsPhase = boundsOf(polygons: outlinePhase)
        XCTAssertEqual(boundsPhase.maxX - boundsPhase.minX, 40.0, accuracy: 1.0)

        let samples = makeUseCase().generateSamples(for: phaseSpec)
        if let first = samples.first {
            let expected = Double.pi
            XCTAssertLessThan(abs(AngleMath.angularDifference(first.effectiveRotation, expected)), 1.0e-3)
        }
    }

    func testAsymmetricWidthShiftsBoundsWithoutOffset() throws {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 33, y: 0),
                    p2: Point(x: 66, y: 0),
                    p3: Point(x: 100, y: 0)
                )
            ]),
            width: ParamTrack.constant(40),
            widthLeft: ParamTrack.constant(10),
            widthRight: ParamTrack.constant(30),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let outline = try makeUseCase().generateOutline(for: spec)
        let bounds = boundsOf(polygons: outline)

        XCTAssertEqual(bounds.minX, -10.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxX, 130.0, accuracy: tolerance)
        XCTAssertEqual(bounds.minY, -10.0, accuracy: tolerance)
        XCTAssertEqual(bounds.maxY, 10.0, accuracy: tolerance)
    }

    func testSymmetricFallbackMatchesExplicitHalves() throws {
        let base = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 25, y: 0),
                    p2: Point(x: 75, y: 0),
                    p3: Point(x: 100, y: 0)
                )
            ]),
            width: ParamTrack.constant(20),
            height: ParamTrack.constant(12),
            theta: ParamTrack.constant(0.1),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let explicit = StrokeSpec(
            path: base.path,
            width: base.width,
            widthLeft: ParamTrack.constant(10),
            widthRight: ParamTrack.constant(10),
            height: base.height,
            theta: base.theta,
            angleMode: base.angleMode,
            sampling: base.sampling
        )

        let outlineA = try makeUseCase().generateOutline(for: base)
        let outlineB = try makeUseCase().generateOutline(for: explicit)

        XCTAssertEqual(outlineA, outlineB)
    }

    func testWidthVariationExpandsBounds() throws {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 33, y: 0),
                    p2: Point(x: 66, y: 0),
                    p3: Point(x: 100, y: 0)
                )
            ]),
            width: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 10),
                Keyframe(t: 1.0, value: 30)
            ]),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let outline = try makeUseCase().generateOutline(for: spec)
        let bounds = boundsOf(polygons: outline)

        XCTAssertLessThanOrEqual(bounds.minX, -5.0 + tolerance)
        XCTAssertGreaterThanOrEqual(bounds.maxX, 115.0 - tolerance)
    }

    func testRawCoordinateModeKeepsStartPoint() {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 165, y: 20),
                    p1: Point(x: 200, y: 20),
                    p2: Point(x: 260, y: 20),
                    p3: Point(x: 300, y: 20)
                )
            ]),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(),
            output: OutputSpec(coordinateMode: .raw)
        )

        let samples = makeUseCase().generateSamples(for: spec)
        let first = samples.first?.point ?? Point(x: 0, y: 0)
        XCTAssertEqual(first.x, 165, accuracy: 1.0e-6)
        XCTAssertEqual(first.y, 20, accuracy: 1.0e-6)
    }

    func testLaneOffsetUsesTangentRightNormal() {
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
            height: ParamTrack.constant(10),
            theta: ParamTrack.constant(0),
            offset: ParamTrack.constant(10),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let samples = makeUseCase().generateSamples(for: spec)
        let probeIndices = [0, samples.count / 2, max(0, samples.count - 1)]
        for index in probeIndices {
            let sample = samples[index]
            XCTAssertEqual(sample.point.y, -10.0, accuracy: 1.0e-6)
        }
    }

    func testLaneOffsetContinuityOnTangentReversal() {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 33, y: 0),
                    p2: Point(x: 66, y: 0),
                    p3: Point(x: 100, y: 0)
                ),
                CubicBezier(
                    p0: Point(x: 100, y: 0),
                    p1: Point(x: 66, y: 0),
                    p2: Point(x: 33, y: 0),
                    p3: Point(x: 0, y: 0)
                )
            ]),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(10),
            theta: ParamTrack.constant(0),
            offset: ParamTrack.constant(10),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let samples = makeUseCase().generateSamples(for: spec)
        for sample in samples {
            XCTAssertEqual(sample.point.y, -10.0, accuracy: 1.0e-6)
        }
    }

    func testThetaEvalFollowsKeyframes() {
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
            theta: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 0.0),
                Keyframe(t: 1.0, value: 0.0)
            ]),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let samples = makeUseCase().generateSamples(for: spec)
        for sample in samples {
            XCTAssertEqual(sample.theta, 0.0, accuracy: 1.0e-6)
        }
    }

    func testTangentRelativeUsesSafeTangentAtDegenerateEndpoints() throws {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 0, y: 0),
                    p2: Point(x: 0, y: 100),
                    p3: Point(x: 0, y: 100)
                )
            ]),
            width: ParamTrack.constant(40),
            widthLeft: ParamTrack.constant(20),
            widthRight: ParamTrack.constant(20),
            height: ParamTrack.constant(6),
            theta: ParamTrack.constant(0),
            angleMode: .tangentRelative,
            sampling: SamplingSpec()
        )

        let samples = makeUseCase().generateSamples(for: spec)
        guard let first = samples.first, let last = samples.last else {
            XCTFail("Missing samples for degenerate tangent test.")
            return
        }
        let expected = Double.pi / 2.0
        XCTAssertLessThan(abs(AngleMath.angularDifference(first.tangentAngle, expected)), 1.0e-3)
        XCTAssertLessThan(abs(AngleMath.angularDifference(last.tangentAngle, expected)), 1.0e-3)
        XCTAssertLessThan(abs(AngleMath.angularDifference(first.effectiveRotation, expected)), 1.0e-3)
        XCTAssertLessThan(abs(AngleMath.angularDifference(last.effectiveRotation, expected)), 1.0e-3)

        let outline = try makeUseCase().generateOutline(for: spec)
        let bounds = boundsOf(polygons: outline)
        XCTAssertEqual(bounds.maxX - bounds.minX, 6.0, accuracy: 1.0)
    }

    func testRailsOutlineRefinesOnCurve() throws {
        let basePolicy = SamplingPolicy(
            flattenTolerance: 0.5,
            envelopeTolerance: 0.3,
            railTolerance: 0.0,
            maxSamples: 64,
            maxRecursionDepth: 6,
            minParamStep: 0.01
        )
        let refinedPolicy = SamplingPolicy(
            flattenTolerance: 0.5,
            envelopeTolerance: 0.3,
            railTolerance: 0.3,
            maxSamples: 64,
            maxRecursionDepth: 6,
            minParamStep: 0.01
        )
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 20, y: 60),
                    p2: Point(x: 60, y: -60),
                    p3: Point(x: 80, y: 0)
                )
            ]),
            width: ParamTrack.constant(20),
            height: ParamTrack.constant(6),
            theta: ParamTrack.constant(0),
            angleMode: .tangentRelative,
            sampling: SamplingSpec(),
            samplingPolicy: basePolicy
        )
        let useCase = makeUseCase()
        var unrefinedSpec = spec
        unrefinedSpec.output = OutputSpec(coordinateMode: .normalized, outlineMethod: .rails)
        let unrefinedOutline = try useCase.generateOutline(for: unrefinedSpec)

        var refinedSpec = spec
        refinedSpec.output = OutputSpec(coordinateMode: .normalized, outlineMethod: .rails)
        refinedSpec.samplingPolicy = refinedPolicy
        let refinedOutline = try useCase.generateOutline(for: refinedSpec)

        let unrefinedVertices = vertexCount(polygons: unrefinedOutline)
        let refinedVertices = vertexCount(polygons: refinedOutline)
        XCTAssertGreaterThanOrEqual(refinedVertices, unrefinedVertices)
    }

    private func makeUseCase() -> GenerateStrokeOutlineUseCase {
        GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )
    }

    private func zigzagCount(polygons: Domain.PolygonSet, angleThresholdDeg: Double, edgeMax: Double) -> Int {
        var count = 0
        let threshold = angleThresholdDeg * .pi / 180.0
        for polygon in polygons {
            var points = polygon.outer
            if points.count < 4 { continue }
            if points.first == points.last {
                points.removeLast()
            }
            let n = points.count
            guard n >= 3 else { continue }
            for i in 0..<n {
                let prev = points[(i - 1 + n) % n]
                let cur = points[i]
                let next = points[(i + 1) % n]
                let v1 = cur - prev
                let v2 = next - cur
                let l1 = v1.length
                let l2 = v2.length
                if l1 == 0.0 || l2 == 0.0 { continue }
                let dot = max(-1.0, min(1.0, v1.dot(v2) / (l1 * l2)))
                let angle = acos(dot)
                if angle >= threshold, min(l1, l2) <= edgeMax {
                    count += 1
                }
            }
        }
        return count
    }

    private func vertexCount(polygons: Domain.PolygonSet) -> Int {
        polygons.reduce(0) { $0 + $1.outer.count + $1.holes.reduce(0) { $0 + $1.count } }
    }

    private func boundsOf(polygons: Domain.PolygonSet) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for polygon in polygons {
            for point in polygon.outer {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            for hole in polygon.holes {
                for point in hole {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
        }

        return (minX, maxX, minY, maxY)
    }
}
