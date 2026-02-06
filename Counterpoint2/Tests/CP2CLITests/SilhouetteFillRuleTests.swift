import XCTest
import CP2Geometry
@testable import cp2_cli

final class SilhouetteFillRuleTests: XCTestCase {
    func testSilhouetteUsesNonzeroFillRule() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/e.v0.json")
        var options = CLIOptions()
        options.example = "e"
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("fill-rule=\"nonzero\""))
        XCTAssertFalse(svg.contains("fill-rule=\"evenodd\""))
    }
}
