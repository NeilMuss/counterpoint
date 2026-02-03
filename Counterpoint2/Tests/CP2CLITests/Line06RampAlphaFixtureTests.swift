import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class Line06RampAlphaFixtureTests: XCTestCase {
    func testRampAlphaKeyframeTimingAndEasing() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_06_ramp_alpha.v0.json")
        guard let stroke = spec.strokes?.first, let params = stroke.params else {
            XCTFail("missing stroke params")
            return
        }
        guard let widthLeft = params.widthLeft, let widthRight = params.widthRight else {
            XCTFail("missing widthLeft/widthRight keyframes")
            return
        }

        let leftAlpha = widthLeft.keyframes.count > 1 ? (widthLeft.keyframes[1].interpToNext?.alpha ?? 0.0) : 0.0
        let rightAlpha = widthRight.keyframes.count > 1 ? (widthRight.keyframes[1].interpToNext?.alpha ?? 0.0) : 0.0
        XCTAssertEqual(leftAlpha, -3.9, accuracy: 1.0e-6)
        XCTAssertEqual(rightAlpha, 3.9, accuracy: 1.0e-6)

        let options = CLIOptions()
        let provider = SpecParamProvider(params: params)
        let funcs = provider.makeParamFuncs(options: options, exampleName: spec.example, sweepWidth: 40.0)
        let leftMid = funcs.widthLeftAtT(0.5)
        let rightMid = funcs.widthRightAtT(0.5)
        XCTAssertEqual(leftMid, 20.0, accuracy: 1.0e-6)
        XCTAssertEqual(rightMid, 20.0, accuracy: 1.0e-6)

        let leftLate = funcs.widthLeftAtT(0.9)
        let rightLate = funcs.widthRightAtT(0.9)
        XCTAssertGreaterThan(leftLate, 30.0)
        XCTAssertGreaterThan(rightLate, 30.0)
        XCTAssertGreaterThan(Swift.abs(leftLate - rightLate), 1.0e-6)
    }
}
