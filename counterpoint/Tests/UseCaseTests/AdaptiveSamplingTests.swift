import XCTest
@testable import Domain
@testable import UseCases
@testable import Adapters

final class AdaptiveSamplingTests: XCTestCase {
    func testPreviewProducesFewSamplesOnStraightLine() throws {
        let spec = StrokeSpec(
            path: straightPath(),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(baseSpacing: 1000.0, maxSpacing: 1000.0),
            samplingPolicy: .preview
        )
        let useCase = makeUseCase()
        let samples = useCase.generateSamples(for: spec)
        XCTAssertLessThanOrEqual(samples.count, 4)
    }

    func testFinalProducesMoreSamplesThanPreviewOnSCurve() throws {
        let base = StrokeSpec(
            path: sCurvePath(),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0.2),
            angleMode: .tangentRelative,
            sampling: SamplingSpec(),
            samplingPolicy: .preview
        )
        let previewSamples = makeUseCase().generateSamples(for: base)
        let finalSpec = StrokeSpec(
            path: base.path,
            width: base.width,
            height: base.height,
            theta: base.theta,
            angleMode: base.angleMode,
            capStyle: base.capStyle,
            joinStyle: base.joinStyle,
            sampling: base.sampling,
            samplingPolicy: .final
        )
        let finalSamples = makeUseCase().generateSamples(for: finalSpec)
        XCTAssertLessThan(previewSamples.count, finalSamples.count)
    }

    func testRapidThetaChangeForcesRefinement() throws {
        let theta = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 0.0),
            Keyframe(t: 0.9, value: 0.0),
            Keyframe(t: 1.0, value: .pi)
        ])
        let spec = StrokeSpec(
            path: straightPath(),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: theta,
            angleMode: .absolute,
            sampling: SamplingSpec(),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 1.0,
                envelopeTolerance: 0.25,
                maxSamples: 64,
                maxRecursionDepth: 8,
                minParamStep: 0.01
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        let tailSamples = samples.filter { $0.t > 0.9 }
        XCTAssertGreaterThanOrEqual(tailSamples.count, 2)
    }

    func testPreviewUsesFewerSamplesThanFinalOnTeardropDemo() throws {
        var spec = try loadFixture(named: "teardrop-demo")
        let useCase = makeUseCase()

        spec.samplingPolicy = .preview
        if case .ellipse = spec.counterpointShape {
            spec.counterpointShape = .ellipse(segments: 24)
        }
        let previewSamples = useCase.generateSamples(for: spec)

        spec.samplingPolicy = .final
        if case .ellipse = spec.counterpointShape {
            spec.counterpointShape = .ellipse(segments: 64)
        }
        let finalSamples = useCase.generateSamples(for: spec)

        XCTAssertLessThan(previewSamples.count, finalSamples.count)
    }

    func testKeyframesUseArclengthProgress() throws {
        let width = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 5.0),
            Keyframe(t: 0.02, value: 80.0),
            Keyframe(t: 1.0, value: 80.0)
        ])
        let spec = StrokeSpec(
            path: longStemWithCurl(),
            width: width,
            height: ParamTrack.constant(10),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 0.5,
                envelopeTolerance: 0.25,
                maxSamples: 200,
                maxRecursionDepth: 8,
                minParamStep: 0.002
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        let uValues = samples.map { $0.uGeom }
        XCTAssertTrue(uValues.contains { abs($0 - 0.5) < 0.05 })

        let points = samples.map { $0.point }
        var lengths: [Double] = [0.0]
        var total = 0.0
        for i in 1..<points.count {
            total += (points[i] - points[i - 1]).length
            lengths.append(total)
        }
        let midTarget = total * 0.5
        let midIndex = lengths.enumerated().min(by: { abs($0.element - midTarget) < abs($1.element - midTarget) })?.offset ?? 0
        XCTAssertEqual(samples[midIndex].t, 0.5, accuracy: 0.15)

        let earlyIndex = samples.firstIndex(where: { $0.t >= 0.02 }) ?? 0
        XCTAssertGreaterThan(samples[earlyIndex].width, 60.0)
    }

    func testSpacingAddsSamplesNearEarlyProgress() {
        let spec = StrokeSpec(
            path: longStemWithCurl(),
            width: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 190),
                Keyframe(t: 0.02, value: 40),
                Keyframe(t: 1.0, value: 40)
            ]),
            height: ParamTrack.constant(10),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(baseSpacing: 4.0),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 0.5,
                envelopeTolerance: 0.25,
                maxSamples: 200,
                maxRecursionDepth: 8,
                minParamStep: 0.002
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        var maxDistance = 0.0
        for i in 1..<samples.count {
            maxDistance = max(maxDistance, (samples[i].point - samples[i - 1].point).length)
        }
        XCTAssertLessThanOrEqual(maxDistance, 4.0 + 1.0e-6)
        XCTAssertTrue(samples.contains { $0.t >= 0.015 && $0.t <= 0.03 })
    }

    func testAlphaInterpolatesAlongProgress() {
        let spec = StrokeSpec(
            path: straightPath(),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            alpha: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 0.0),
                Keyframe(t: 1.0, value: 1.0)
            ]),
            angleMode: .absolute,
            sampling: SamplingSpec(baseSpacing: 5.0),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 0.5,
                envelopeTolerance: 0.25,
                maxSamples: 64,
                maxRecursionDepth: 6,
                minParamStep: 0.01
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        let q1 = samples.min { abs($0.t - 0.25) < abs($1.t - 0.25) }
        let q3 = samples.min { abs($0.t - 0.75) < abs($1.t - 0.75) }
        XCTAssertEqual(q1?.alpha ?? 0.0, 0.25, accuracy: 0.1)
        XCTAssertEqual(q3?.alpha ?? 0.0, 0.75, accuracy: 0.1)
    }

    func testAlphaPulseProducesNonZeroSamples() {
        let spec = StrokeSpec(
            path: longStemWithCurl(),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            alpha: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 0.0),
                Keyframe(t: 0.012, value: 0.65),
                Keyframe(t: 0.018, value: 0.65),
                Keyframe(t: 0.02, value: 0.0),
                Keyframe(t: 1.0, value: 0.0)
            ]),
            angleMode: .absolute,
            sampling: SamplingSpec(
                mode: .keyframeGrid,
                baseSpacing: 1000.0,
                maxSpacing: 1000.0,
                keyframeDensity: 2,
                rotationThresholdDegrees: 180.0
            ),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 0.5,
                envelopeTolerance: 0.25,
                maxSamples: 200,
                maxRecursionDepth: 8,
                minParamStep: 0.002
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        XCTAssertGreaterThan(samples.map { $0.alpha }.max() ?? 0.0, 0.1)
    }

    func testAlphaDoesNotShiftWidthKeyframeTiming() {
        let spec = StrokeSpec(
            path: longStemWithCurl(),
            width: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 190),
                Keyframe(t: 0.02, value: 40),
                Keyframe(t: 1.0, value: 40)
            ]),
            height: ParamTrack.constant(10),
            theta: ParamTrack.constant(0),
            alpha: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 0.0),
                Keyframe(t: 0.012, value: 0.65),
                Keyframe(t: 0.018, value: 0.65),
                Keyframe(t: 0.02, value: 0.0),
                Keyframe(t: 1.0, value: 0.0)
            ]),
            angleMode: .absolute,
            sampling: SamplingSpec(baseSpacing: 8.0),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 0.5,
                envelopeTolerance: 0.25,
                maxSamples: 200,
                maxRecursionDepth: 8,
                minParamStep: 0.002
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        let early = samples.filter { $0.t < 0.02 }
        let minEarlyWidth = early.map { $0.width }.min() ?? 0.0
        XCTAssertGreaterThan(minEarlyWidth, 40.0 + 1.0e-6)
        let firstLow = samples.first { $0.width <= 40.0 + 1.0e-6 }
        XCTAssertGreaterThanOrEqual(firstLow?.t ?? 0.0, 0.02 - 1.0e-3)
    }

    func testKeyframeGridIncludesKeyframeTimes() {
        let spec = StrokeSpec(
            path: straightPath(),
            width: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 10),
                Keyframe(t: 0.5, value: 12),
                Keyframe(t: 1.0, value: 10)
            ]),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(
                mode: .keyframeGrid,
                baseSpacing: 1000.0,
                maxSpacing: 1000.0,
                keyframeDensity: 1,
                rotationThresholdDegrees: 180.0
            ),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 1.0,
                envelopeTolerance: 1.0,
                maxSamples: 64,
                maxRecursionDepth: 4,
                minParamStep: 0.01
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        XCTAssertTrue(samples.contains { abs($0.t - 0.5) < 1.0e-3 })
    }

    func testKeyframeGridProducesFewerSamplesThanAdaptive() {
        let baseSampling = SamplingSpec(
            baseSpacing: 1000.0,
            maxSpacing: 1000.0,
            rotationThresholdDegrees: 10.0
        )
        let adaptiveSpec = StrokeSpec(
            path: sCurvePath(),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(
                mode: .adaptive,
                baseSpacing: baseSampling.baseSpacing,
                maxSpacing: baseSampling.maxSpacing,
                rotationThresholdDegrees: baseSampling.rotationThresholdDegrees
            ),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 0.25,
                envelopeTolerance: 0.01,
                maxSamples: 256,
                maxRecursionDepth: 10,
                minParamStep: 0.001
            )
        )
        let gridSpec = StrokeSpec(
            path: adaptiveSpec.path,
            width: adaptiveSpec.width,
            height: adaptiveSpec.height,
            theta: adaptiveSpec.theta,
            angleMode: adaptiveSpec.angleMode,
            sampling: SamplingSpec(
                mode: .keyframeGrid,
                baseSpacing: baseSampling.baseSpacing,
                maxSpacing: baseSampling.maxSpacing,
                keyframeDensity: 1,
                rotationThresholdDegrees: 180.0
            ),
            samplingPolicy: adaptiveSpec.samplingPolicy
        )
        let adaptiveSamples = makeUseCase().generateSamples(for: adaptiveSpec)
        let gridSamples = makeUseCase().generateSamples(for: gridSpec)
        XCTAssertGreaterThanOrEqual(adaptiveSamples.count, gridSamples.count)
    }

    func testKeyframeGridOrderingMonotone() {
        let spec = StrokeSpec(
            path: longStemWithCurl(),
            width: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 8),
                Keyframe(t: 0.5, value: 12),
                Keyframe(t: 1.0, value: 6)
            ]),
            height: ParamTrack.constant(12),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(
                mode: .keyframeGrid,
                baseSpacing: 12.0,
                maxSpacing: 12.0,
                keyframeDensity: 2,
                rotationThresholdDegrees: 180.0
            ),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 0.5,
                envelopeTolerance: 0.25,
                maxSamples: 256,
                maxRecursionDepth: 8,
                minParamStep: 0.002
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        for i in 1..<samples.count {
            XCTAssertGreaterThanOrEqual(samples[i].uGeom + 1.0e-9, samples[i - 1].uGeom)
        }
    }

    func testKeyframeGridSkipsConstantIntervals() {
        let spec = StrokeSpec(
            path: straightPath(),
            width: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 10),
                Keyframe(t: 1.0, value: 10)
            ]),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(
                mode: .keyframeGrid,
                baseSpacing: 1000.0,
                maxSpacing: 1000.0,
                keyframeDensity: 4,
                rotationThresholdDegrees: 180.0
            ),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 1.0,
                envelopeTolerance: 1.0,
                maxSamples: 64,
                maxRecursionDepth: 4,
                minParamStep: 0.01
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.first?.t ?? -1.0, 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(samples.last?.t ?? -1.0, 1.0, accuracy: 1.0e-9)
    }

    func testAlphaDoesNotBackstepYInStraightSegment() {
        let path = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 0, y: 30),
                p2: Point(x: 0, y: 70),
                p3: Point(x: 0, y: 100)
            )
        ])
        let spec = StrokeSpec(
            path: path,
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            alpha: ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: 0.0),
                Keyframe(t: 0.05, value: 0.8),
                Keyframe(t: 0.1, value: 0.0),
                Keyframe(t: 1.0, value: 0.0)
            ]),
            angleMode: .absolute,
            sampling: SamplingSpec(
                mode: .keyframeGrid,
                baseSpacing: 10.0,
                maxSpacing: 10.0,
                keyframeDensity: 2,
                rotationThresholdDegrees: 180.0
            ),
            samplingPolicy: SamplingPolicy(
                flattenTolerance: 0.5,
                envelopeTolerance: 0.25,
                maxSamples: 128,
                maxRecursionDepth: 6,
                minParamStep: 0.005
            )
        )
        let samples = makeUseCase().generateSamples(for: spec)
        for i in 1..<samples.count {
            XCTAssertGreaterThanOrEqual(samples[i].point.y + 1.0e-9, samples[i - 1].point.y)
        }
    }

    private func makeUseCase() -> GenerateStrokeOutlineUseCase {
        GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )
    }

    private func straightPath() -> BezierPath {
        BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 20, y: 0),
                p2: Point(x: 40, y: 0),
                p3: Point(x: 60, y: 0)
            )
        ])
    }

    private func sCurvePath() -> BezierPath {
        BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 15, y: 40),
                p2: Point(x: 45, y: -40),
                p3: Point(x: 60, y: 0)
            )
        ])
    }

    private func longStemWithCurl() -> BezierPath {
        BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 0, y: 60),
                p2: Point(x: 0, y: 140),
                p3: Point(x: 0, y: 200)
            ),
            CubicBezier(
                p0: Point(x: 0, y: 200),
                p1: Point(x: 30, y: 210),
                p2: Point(x: 40, y: 170),
                p3: Point(x: 20, y: 150)
            )
        ])
    }

    private func loadFixture(named name: String) throws -> StrokeSpec {
        let fileURL = URL(fileURLWithPath: #file)
        var dir = fileURL.deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("Fixtures/specs/\(name).json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                let data = try Data(contentsOf: candidate)
                return try JSONDecoder().decode(StrokeSpec.self, from: data)
            }
            dir.deleteLastPathComponent()
        }
        throw NSError(domain: "AdaptiveSamplingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found."])
    }
}
