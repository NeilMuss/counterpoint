import XCTest
import Domain
import UseCases
import Adapters
@testable import CounterpointCLI

final class DebugReferenceTests: XCTestCase {
    func testSVGIncludesDebugReferencePath() throws {
        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 30, y: 0),
                    p2: Point(x: 60, y: 0),
                    p3: Point(x: 90, y: 0)
                )
            ]),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(10),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(),
            debugReference: DebugReference(
                svgPathD: "M 0 0 L 20 0",
                transform: "translate(2,3)",
                opacity: 0.4
            )
        )

        let outline = try GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        ).generateOutline(for: spec)

        let svg = SVGPathBuilder().svgDocument(
            for: outline,
            size: nil,
            padding: 10.0,
            debugReference: spec.debugReference
        )

        XCTAssertTrue(svg.contains("id=\"debug-reference\""))
        XCTAssertTrue(svg.contains("d=\"M 0 0 L 20 0\""))
        XCTAssertTrue(svg.contains("transform=\"translate(2,3)\""))
    }
}
