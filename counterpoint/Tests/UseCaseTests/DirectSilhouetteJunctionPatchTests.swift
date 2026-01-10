import XCTest
@testable import Domain
@testable import UseCases
@testable import Adapters

final class DirectSilhouetteJunctionPatchTests: XCTestCase {
    func testJunctionPatchProducedDeterministically() {
        let first = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 0, y: 0),
                p2: Point(x: 20, y: 0),
                p3: Point(x: 20, y: 0)
            )
        ])
        let second = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 20, y: 0),
                p1: Point(x: 20, y: 0),
                p2: Point(x: 20, y: 20),
                p3: Point(x: 20, y: 20)
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
        let concatenated = useCase.generateConcatenatedSamplesWithJunctions(for: spec, paths: [first, second])
        XCTAssertEqual(concatenated.junctionPairs.count, 1)
        let junctions = concatenated.junctionPairs.enumerated().compactMap { index, pair -> DirectSilhouetteTracer.JunctionContext? in
            guard pair.0 >= 0, pair.1 >= 0,
                  pair.0 < concatenated.samples.count,
                  pair.1 < concatenated.samples.count else { return nil }
            let prev = pair.0 > 0 ? concatenated.samples[pair.0 - 1] : nil
            let next = pair.1 + 1 < concatenated.samples.count ? concatenated.samples[pair.1 + 1] : nil
            return DirectSilhouetteTracer.JunctionContext(
                joinIndex: index,
                prev: prev,
                a: concatenated.samples[pair.0],
                b: concatenated.samples[pair.1],
                next: next
            )
        }
        let result = DirectSilhouetteTracer.trace(samples: concatenated.samples, junctions: junctions)
        XCTAssertFalse(result.outline.isEmpty)
        XCTAssertEqual(result.junctionPatches.count, 1)
        XCTAssertGreaterThanOrEqual(result.junctionPatches[0].count, 3)
        let secondResult = DirectSilhouetteTracer.trace(samples: concatenated.samples, junctions: junctions)
        XCTAssertEqual(result.junctionPatches, secondResult.junctionPatches)
    }
}
