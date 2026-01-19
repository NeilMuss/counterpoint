import XCTest
@testable import Domain
@testable import UseCases
@testable import Adapters

final class SilhouetteOutlineTests: XCTestCase {
    func testSilhouetteOutlineClosedAndDeterministic() throws {
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

        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )

        let outlineA = try useCase.generateOutline(for: spec, includeBridges: true, outlineMode: .silhouette)
        let outlineB = try useCase.generateOutline(for: spec, includeBridges: true, outlineMode: .silhouette)

        XCTAssertFalse(outlineA.isEmpty)
        for polygon in outlineA {
            XCTAssertEqual(polygon.outer.first, polygon.outer.last)
        }
        XCTAssertEqual(outlineA, outlineB)
    }
}
