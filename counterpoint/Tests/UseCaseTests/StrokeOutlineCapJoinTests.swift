import XCTest
@testable import Domain
@testable import UseCases
@testable import Adapters

final class StrokeOutlineCapJoinTests: XCTestCase {
    func testCapStylesExpandBounds() throws {
        let baseSpec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 33, y: 0),
                    p2: Point(x: 66, y: 0),
                    p3: Point(x: 100, y: 0)
                )
            ]),
            width: ParamTrack.constant(4),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let useCase = makeUseCase()
        let butt = try useCase.generateOutline(for: baseSpec)
        let round = try useCase.generateOutline(for: StrokeSpec(
            path: baseSpec.path,
            width: baseSpec.width,
            height: baseSpec.height,
            theta: baseSpec.theta,
            angleMode: baseSpec.angleMode,
            capStyle: CapStylePair(.round),
            joinStyle: .bevel,
            sampling: baseSpec.sampling
        ))
        let square = try useCase.generateOutline(for: StrokeSpec(
            path: baseSpec.path,
            width: baseSpec.width,
            height: baseSpec.height,
            theta: baseSpec.theta,
            angleMode: baseSpec.angleMode,
            capStyle: CapStylePair(.square),
            joinStyle: .bevel,
            sampling: baseSpec.sampling
        ))

        let buttBounds = bounds(of: butt)
        let roundBounds = bounds(of: round)
        let squareBounds = bounds(of: square)

        XCTAssertLessThan(buttBounds.maxX, roundBounds.maxX)
        XCTAssertLessThan(roundBounds.maxX, squareBounds.maxX)
    }

    func testJoinStylesExpandCornerBounds() throws {
        let path = BezierPath(segments: [
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
        ])

        let base = StrokeSpec(
            path: path,
            width: ParamTrack.constant(4),
            height: ParamTrack.constant(20),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let useCase = makeUseCase()
        let bevel = try useCase.generateOutline(for: base)
        let miter = try useCase.generateOutline(for: StrokeSpec(
            path: base.path,
            width: base.width,
            height: base.height,
            theta: base.theta,
            angleMode: base.angleMode,
            capStyle: CapStylePair(.butt),
            joinStyle: .miter(miterLimit: 10.0),
            sampling: base.sampling
        ))
        let round = try useCase.generateOutline(for: StrokeSpec(
            path: base.path,
            width: base.width,
            height: base.height,
            theta: base.theta,
            angleMode: base.angleMode,
            capStyle: CapStylePair(.butt),
            joinStyle: .round,
            sampling: base.sampling
        ))

        let bevelBounds = bounds(of: bevel)
        let miterBounds = bounds(of: miter)
        let roundBounds = bounds(of: round)

        XCTAssertLessThanOrEqual(bevelBounds.maxX, miterBounds.maxX)
        XCTAssertLessThanOrEqual(bevelBounds.maxY, miterBounds.maxY)
        XCTAssertLessThanOrEqual(bevelBounds.maxX, roundBounds.maxX)
        XCTAssertLessThanOrEqual(bevelBounds.maxY, roundBounds.maxY)
    }

    func testCircleCapUsesWidthRadius() throws {
        let baseSpec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 33, y: 0),
                    p2: Point(x: 66, y: 0),
                    p3: Point(x: 100, y: 0)
                )
            ]),
            width: ParamTrack.constant(20),
            widthLeft: ParamTrack.constant(10),
            widthRight: ParamTrack.constant(10),
            height: ParamTrack.constant(40),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        let useCase = makeUseCase()
        let butt = try useCase.generateOutline(for: baseSpec)
        let circle = try useCase.generateOutline(for: StrokeSpec(
            path: baseSpec.path,
            width: baseSpec.width,
            widthLeft: baseSpec.widthLeft,
            widthRight: baseSpec.widthRight,
            height: baseSpec.height,
            theta: baseSpec.theta,
            angleMode: baseSpec.angleMode,
            capStyle: CapStylePair(start: .butt, end: .circle),
            joinStyle: .bevel,
            sampling: baseSpec.sampling
        ))
        let round = try useCase.generateOutline(for: StrokeSpec(
            path: baseSpec.path,
            width: baseSpec.width,
            widthLeft: baseSpec.widthLeft,
            widthRight: baseSpec.widthRight,
            height: baseSpec.height,
            theta: baseSpec.theta,
            angleMode: baseSpec.angleMode,
            capStyle: CapStylePair(start: .butt, end: .round),
            joinStyle: .bevel,
            sampling: baseSpec.sampling
        ))

        XCTAssertEqual(circle.count, butt.count + 1)
        XCTAssertEqual(round.count, butt.count + 1)
    }

    private func makeUseCase() -> GenerateStrokeOutlineUseCase {
        GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )
    }

    private func bounds(of polygons: PolygonSet) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
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
        }

        return (minX, maxX, minY, maxY)
    }
}
