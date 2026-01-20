import XCTest
import CP2Geometry
@testable import cp2_cli

final class InkSpecRenderingTests: XCTestCase {
    func testInkStemLineAffectsCenterlineSVG() {
        let ink = Ink(stem: InkLine(type: "line", p0: Vec2(200, 900), p1: Vec2(250, 300)))
        let spec = CP2Spec(example: nil, render: nil, reference: nil, ink: ink)
        var options = CLIOptions()
        options.debugCenterline = true
        options.example = nil
        let svg = renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("M 200.0000 900.0000"))
        XCTAssertTrue(svg.contains("L 250.0000 300.0000"))
    }
}
