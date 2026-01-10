import XCTest
@testable import Domain
@testable import UseCases

final class DirectSilhouetteAlphaEasingTests: XCTestCase {
    func testAlphaEasingMovesLeftRailMidpoint() {
        let widthTrack = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 180.0),
            Keyframe(t: 0.05, value: 180.0, interpolationToNext: Interpolation(alpha: 0.85)),
            Keyframe(t: 0.16, value: 90.0),
            Keyframe(t: 1.0, value: 90.0)
        ])
        let evaluator = DefaultParamEvaluator()
        let t0 = 0.05
        let t1 = 0.16
        let tm = (t0 + t1) * 0.5

        let sample0 = makeSample(t: t0, widthTrack: widthTrack, evaluator: evaluator)
        let sample1 = makeSample(t: t1, widthTrack: widthTrack, evaluator: evaluator)
        let sampleMid = makeSample(t: tm, widthTrack: widthTrack, evaluator: evaluator)

        let l0 = DirectSilhouetteTracer.leftRailPoint(sample: sample0)
        let l1 = DirectSilhouetteTracer.leftRailPoint(sample: sample1)
        let lm = DirectSilhouetteTracer.leftRailPoint(sample: sampleMid)
        let llin = Point(
            x: ScalarMath.lerp(l0.x, l1.x, 0.5),
            y: ScalarMath.lerp(l0.y, l1.y, 0.5)
        )

        let epsilon = max(0.25, 0.002 * sample0.width)
        let distance = (lm - llin).length
        XCTAssertGreaterThan(distance, epsilon)
    }

    func testAlphaZeroKeepsLeftRailCollinear() {
        let widthTrack = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 180.0),
            Keyframe(t: 0.05, value: 180.0, interpolationToNext: Interpolation(alpha: 0.0)),
            Keyframe(t: 0.16, value: 90.0),
            Keyframe(t: 1.0, value: 90.0)
        ])
        let evaluator = DefaultParamEvaluator()
        let t0 = 0.05
        let t1 = 0.16
        let tm = (t0 + t1) * 0.5

        let sample0 = makeSample(t: t0, widthTrack: widthTrack, evaluator: evaluator)
        let sample1 = makeSample(t: t1, widthTrack: widthTrack, evaluator: evaluator)
        let sampleMid = makeSample(t: tm, widthTrack: widthTrack, evaluator: evaluator)

        let l0 = DirectSilhouetteTracer.leftRailPoint(sample: sample0)
        let l1 = DirectSilhouetteTracer.leftRailPoint(sample: sample1)
        let lm = DirectSilhouetteTracer.leftRailPoint(sample: sampleMid)
        let llin = Point(
            x: ScalarMath.lerp(l0.x, l1.x, 0.5),
            y: ScalarMath.lerp(l0.y, l1.y, 0.5)
        )

        let distance = (lm - llin).length
        XCTAssertLessThanOrEqual(distance, 1.0e-6)
    }

    func testRailDeviationNonZeroWithAlpha() {
        let widthTrack = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 180.0),
            Keyframe(t: 0.05, value: 180.0, interpolationToNext: Interpolation(alpha: 0.85)),
            Keyframe(t: 0.16, value: 90.0),
            Keyframe(t: 1.0, value: 90.0)
        ])
        let evaluator = DefaultParamEvaluator()
        let t0 = 0.05
        let t1 = 0.16

        let sample0 = makeSample(t: t0, widthTrack: widthTrack, evaluator: evaluator)
        let sample1 = makeSample(t: t1, widthTrack: widthTrack, evaluator: evaluator)
        let provider: DirectSilhouetteTracer.DirectSilhouetteParamProvider = { t, _ in
            let width = evaluator.evaluate(widthTrack, at: t)
            let height = 6.0
            let theta = 0.0
            let effectiveRotation = theta
            return (width, height, theta, effectiveRotation, 0.0)
        }

        let deviation = DirectSilhouetteTracer.railDeviationForTest(a: sample0, b: sample1, paramsProvider: provider, epsilon: 1.0e-9)
        XCTAssertGreaterThan(deviation, 1.0e-3)
    }

    func testRailDeviationZeroWithLinearAlpha() {
        let widthTrack = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 180.0),
            Keyframe(t: 0.05, value: 180.0, interpolationToNext: Interpolation(alpha: 0.0)),
            Keyframe(t: 0.16, value: 90.0),
            Keyframe(t: 1.0, value: 90.0)
        ])
        let evaluator = DefaultParamEvaluator()
        let t0 = 0.05
        let t1 = 0.16

        let sample0 = makeSample(t: t0, widthTrack: widthTrack, evaluator: evaluator)
        let sample1 = makeSample(t: t1, widthTrack: widthTrack, evaluator: evaluator)
        let provider: DirectSilhouetteTracer.DirectSilhouetteParamProvider = { t, _ in
            let width = evaluator.evaluate(widthTrack, at: t)
            let height = 6.0
            let theta = 0.0
            let effectiveRotation = theta
            return (width, height, theta, effectiveRotation, 0.0)
        }

        let deviation = DirectSilhouetteTracer.railDeviationForTest(a: sample0, b: sample1, paramsProvider: provider, epsilon: 1.0e-9)
        XCTAssertLessThanOrEqual(deviation, 1.0e-6)
    }

    private func makeSample(t: Double, widthTrack: ParamTrack, evaluator: DefaultParamEvaluator) -> Sample {
        let width = evaluator.evaluate(widthTrack, at: t)
        let height = 6.0
        let point = Point(x: 0.0, y: 100.0 * t)
        let tangentAngle = Double.pi * 0.5
        return Sample(
            uGeom: t,
            uGrid: t,
            t: t,
            point: point,
            tangentAngle: tangentAngle,
            width: width,
            height: height,
            theta: 0.0,
            effectiveRotation: 0.0,
            alpha: 0.0
        )
    }
}
