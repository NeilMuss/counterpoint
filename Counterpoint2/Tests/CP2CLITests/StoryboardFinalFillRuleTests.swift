import XCTest
import CP2Geometry
@testable import cp2_cli

final class StoryboardFinalFillRuleTests: XCTestCase {
    func testStoryboardFinalSilhouetteUsesNonzeroFillRule() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/e.v0.json")
        var options = CLIOptions()
        options.example = "e"

        let cels = try renderStoryboardCels(
            options: options,
            spec: spec,
            stages: [.final],
            contextMode: .none
        )
        guard let svg = cels.first?.svg else {
            XCTFail("Expected a storyboard SVG for final stage")
            return
        }
        guard let groupRange = svg.range(of: "id=\"final-silhouette\"") else {
            XCTFail("Expected final-silhouette group in storyboard SVG")
            return
        }
        let tail = svg[groupRange.lowerBound...]
        guard let pathStart = tail.range(of: "<path ") else {
            XCTFail("Expected path element in final-silhouette group")
            return
        }
        guard let pathEnd = tail.range(of: "/>", range: pathStart.upperBound..<tail.endIndex) else {
            XCTFail("Expected path element to be self-closing")
            return
        }
        let pathTag = String(tail[pathStart.lowerBound..<pathEnd.upperBound])
        XCTAssertFalse(pathTag.contains("fill-rule=\"evenodd\""))
        XCTAssertTrue(pathTag.contains("fill-rule=\"nonzero\"") || !pathTag.contains("fill-rule"))
    }
}
