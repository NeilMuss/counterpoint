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
}
