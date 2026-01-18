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
}
