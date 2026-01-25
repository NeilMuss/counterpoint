import XCTest
import CP2Geometry
@testable import cp2_cli

final class CompareViewRenderingTests: XCTestCase {
    func testReferenceGroupOrderAndOutlineStyle() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let refURL = tempDir.appendingPathComponent("cp2_ref_test.svg")
        let refSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <path d="M 0 0 L 10 0" />
</svg>
"""
        try refSVG.write(to: refURL, atomically: true, encoding: .utf8)

        let reference = ReferenceLayer(path: refURL.path, opacity: 0.25)
        let spec = CP2Spec(example: "line", render: nil, reference: reference, ink: nil)
        var options = CLIOptions()
        options.example = "line"

        let svg = try renderSVGString(options: options, spec: spec)
        guard
            let refFill = svg.range(of: "id=\"reference-fill\""),
            let ink = svg.range(of: "id=\"stroke-ink\""),
            let refOutline = svg.range(of: "id=\"reference-outline\""),
            let debug = svg.range(of: "id=\"debug-overlays\"")
        else {
            XCTFail("Missing expected SVG groups")
            return
        }

        XCTAssertLessThan(refFill.lowerBound, ink.lowerBound)
        XCTAssertLessThan(ink.lowerBound, refOutline.lowerBound)
        XCTAssertLessThan(refOutline.lowerBound, debug.lowerBound)
        XCTAssertTrue(svg.contains("id=\"reference-outline\""))
        XCTAssertTrue(svg.contains("fill:none;stroke:rgba(0,0,0,0.35);stroke-width:1;vector-effect:non-scaling-stroke"))
    }
}
