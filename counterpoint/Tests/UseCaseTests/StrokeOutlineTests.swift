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

    private func makeUseCase() -> GenerateStrokeOutlineUseCase {
        GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )
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
