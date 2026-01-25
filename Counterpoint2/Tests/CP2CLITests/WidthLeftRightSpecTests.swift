import XCTest
@testable import cp2_cli

final class WidthLeftRightSpecTests: XCTestCase {
    func testSpecWidthLeftRightOverridesLegacyWidth() {
        let params = StrokeParams(
            angleMode: .relative,
            theta: nil,
            width: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 40.0), Keyframe(t: 1.0, value: 40.0)]),
            widthLeft: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 10.0), Keyframe(t: 1.0, value: 50.0)]),
            widthRight: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 30.0), Keyframe(t: 1.0, value: 30.0)]),
            offset: nil,
            alpha: nil
        )
        let provider = SpecParamProvider(params: params)
        let funcs = provider.makeParamFuncs(options: CLIOptions(), exampleName: nil, sweepWidth: 20.0)

        let wL0 = funcs.widthLeftAtT(0.0)
        let wR0 = funcs.widthRightAtT(0.0)
        let wL1 = funcs.widthLeftAtT(1.0)
        let wR1 = funcs.widthRightAtT(1.0)
        XCTAssertEqual(wL0, 10.0, accuracy: 1.0e-9)
        XCTAssertEqual(wR0, 30.0, accuracy: 1.0e-9)
        XCTAssertEqual(wL1, 50.0, accuracy: 1.0e-9)
        XCTAssertEqual(wR1, 30.0, accuracy: 1.0e-9)
        XCTAssertEqual(funcs.widthAtT(0.0), 40.0, accuracy: 1.0e-9)
        XCTAssertEqual(funcs.widthAtT(1.0), 80.0, accuracy: 1.0e-9)
    }
}
