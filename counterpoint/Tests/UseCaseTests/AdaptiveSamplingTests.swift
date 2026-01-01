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
            sampling: SamplingSpec(),
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
