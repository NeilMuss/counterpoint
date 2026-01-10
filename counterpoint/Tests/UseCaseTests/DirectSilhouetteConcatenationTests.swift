import XCTest
@testable import Domain
@testable import UseCases
@testable import Adapters

final class DirectSilhouetteConcatenationTests: XCTestCase {
    func testConcatenatedSamplesUseGlobalProgress() {
        let first = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 0, y: 0),
                p2: Point(x: 10, y: 0),
                p3: Point(x: 10, y: 0)
            )
        ])
        let second = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 10, y: 0),
                p1: Point(x: 10, y: 0),
                p2: Point(x: 10, y: 10),
                p3: Point(x: 10, y: 10)
            )
        ])
        let spec = StrokeSpec(
            path: first,
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(6),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )
        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )
        let samples = useCase.generateConcatenatedSamples(for: spec, paths: [first, second])
        XCTAssertGreaterThan(samples.count, 1)
        XCTAssertEqual(samples.first?.t ?? 1.0, 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(samples.last?.t ?? 0.0, 1.0, accuracy: 1.0e-9)
        for index in 1..<samples.count {
            XCTAssertGreaterThanOrEqual(samples[index].t, samples[index - 1].t)
        }
        let outline = DirectSilhouetteTracer.trace(samples: samples).outline
        XCTAssertFalse(outline.isEmpty)
        XCTAssertFalse(outline.contains { $0.x.isNaN || $0.y.isNaN })
    }
}
