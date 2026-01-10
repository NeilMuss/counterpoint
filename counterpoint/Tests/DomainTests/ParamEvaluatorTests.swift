import XCTest
@testable import Domain

final class ParamEvaluatorTests: XCTestCase {
    func testAngleUnwrapShortestPathAcrossPi() {
        let evaluator = DefaultParamEvaluator()
        let track = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 170.0 * .pi / 180.0),
            Keyframe(t: 1.0, value: -170.0 * .pi / 180.0)
        ])

        let mid = evaluator.evaluateAngle(track, at: 0.5)
        let expected = Double.pi
        XCTAssertLessThan(abs(AngleMath.angularDifference(mid, expected)), 0.05)
    }

    func testAlphaZeroIsLinear() {
        let evaluator = DefaultParamEvaluator()
        let track = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 0.0, interpolationToNext: Interpolation(alpha: 0.0)),
            Keyframe(t: 1.0, value: 100.0)
        ])
        let mid = evaluator.evaluate(track, at: 0.5)
        XCTAssertEqual(mid, 50.0, accuracy: 1.0e-9)
    }

    func testAlphaPositiveBiasesTowardStart() {
        let evaluator = DefaultParamEvaluator()
        let track = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 0.0, interpolationToNext: Interpolation(alpha: 2.0)),
            Keyframe(t: 1.0, value: 100.0)
        ])
        let mid = evaluator.evaluate(track, at: 0.5)
        XCTAssertLessThan(mid, 20.0)
    }

    func testAlphaNegativeBiasesTowardEnd() {
        let evaluator = DefaultParamEvaluator()
        let track = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 0.0, interpolationToNext: Interpolation(alpha: -2.0)),
            Keyframe(t: 1.0, value: 100.0)
        ])
        let mid = evaluator.evaluate(track, at: 0.5)
        XCTAssertGreaterThan(mid, 80.0)
    }

    func testAlphaExtremeNearRoundBehavior() {
        let evaluator = DefaultParamEvaluator()
        let lateTrack = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 0.0, interpolationToNext: Interpolation(alpha: 4.0)),
            Keyframe(t: 1.0, value: 100.0)
        ])
        let earlyTrack = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 0.0, interpolationToNext: Interpolation(alpha: -4.0)),
            Keyframe(t: 1.0, value: 100.0)
        ])
        XCTAssertLessThan(evaluator.evaluate(lateTrack, at: 0.5), 5.0)
        XCTAssertGreaterThan(evaluator.evaluate(earlyTrack, at: 0.5), 95.0)
    }

    func testAlphaDeterministic() {
        let evaluator = DefaultParamEvaluator()
        let track = ParamTrack(keyframes: [
            Keyframe(t: 0.0, value: 0.0, interpolationToNext: Interpolation(alpha: 3.0)),
            Keyframe(t: 1.0, value: 100.0)
        ])
        XCTAssertEqual(evaluator.evaluate(track, at: 0.5), evaluator.evaluate(track, at: 0.5), accuracy: 1.0e-12)
    }

    func testBiasCurveMidpointIsNonLinearForNonzeroAlpha() {
        let biased = DefaultParamEvaluator.biasCurveValue(0.5, bias: -0.8)
        XCTAssertGreaterThan(abs(biased - 0.5), 0.05)
    }
}
