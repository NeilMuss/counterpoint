import XCTest
import CP2Geometry
@testable import cp2_cli

final class PenStampsOverlayTests: XCTestCase {
    func testPenStampsOverlayEmitsExpectedStampCount() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
        var options = parseArgs([
            "--view", "penStamps",
            "--debug-pen-stamps-samples", "0", "63",
            "--debug-pen-stamps-sample-step", "16"
        ])
        options.example = spec.example
        options.penShape = .rectCorners

        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("<g id=\"debug-pen-stamps\">"))

        let expectedCount = 1 + (63 - 0) / 16
        let stampCount = svg.components(separatedBy: "class=\"pen-stamp\"").count - 1
        XCTAssertEqual(stampCount, expectedCount)
    }
}
