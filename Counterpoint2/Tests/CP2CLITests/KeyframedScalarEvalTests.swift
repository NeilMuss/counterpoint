import XCTest
@testable import cp2_cli

final class KeyframedScalarEvalTests: XCTestCase {
    func testKeyframedScalarEvalLinearInterpolation() {
        let scalar = KeyframedScalar(
            keyframes: [
                Keyframe(t: 0.0, value: 0.0),
                Keyframe(t: 1.0, value: 10.0)
            ]
        )
        XCTAssertEqual(scalar.eval(t: 0.0), 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(scalar.eval(t: 0.5), 5.0, accuracy: 1.0e-9)
        XCTAssertEqual(scalar.eval(t: 1.0), 10.0, accuracy: 1.0e-9)
    }
}
