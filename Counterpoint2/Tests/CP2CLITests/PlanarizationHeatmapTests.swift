import XCTest
import CP2Geometry
import CP2ResolveOverlap
import CP2Domain
@testable import cp2_cli

final class PlanarizationHeatmapTests: XCTestCase {
    func testHeatmapDetectsHighDegreeIntersection() {
        let segments: [(Vec2, Vec2)] = [
            (Vec2(0, 0), Vec2(10, 0)),
            (Vec2(5, -5), Vec2(5, 5))
        ]
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let planar = SegmentPlanarizer.planarize(segments: segments, policy: policy, sourceRingId: ArtifactID("heatmapTest"), includeDebug: false)
        let heatmap = buildPlanarizationHeatmap(artifact: planar.artifact)
        XCTAssertNotNil(heatmap)
        guard let heatmap else { return }
        XCTAssertGreaterThanOrEqual(heatmap.maxDegree, 4)
        let highDegreeCount = heatmap.degrees.filter { $0 >= 4 }.count
        XCTAssertGreaterThanOrEqual(highDegreeCount, 1)
    }

    func testHeatmapOverlayEmitsGroupAndGradientColors() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
        var options = parseArgs(["--view", "planarizationHeatmap"])
        options.example = spec.example
        options.penShape = .rectCorners
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("debug-planarization-heatmap"))
        XCTAssertTrue(svg.contains("<circle"))
        let colors = extractFillColors(svg: svg)
        XCTAssertFalse(colors.isEmpty)
        if let cool = colors.min(), colors.count == 1 {
            XCTFail("expected more than one heatmap color, only found \(cool)")
        }
    }
}

private func extractFillColors(svg: String) -> Set<String> {
    let pattern = "fill=\\\"(#[0-9A-Fa-f]{6})\\\""
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let range = NSRange(svg.startIndex..<svg.endIndex, in: svg)
    var colors: Set<String> = []
    regex.enumerateMatches(in: svg, options: [], range: range) { match, _, _ in
        guard let match, match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: svg) else { return }
        colors.insert(String(svg[range]))
    }
    return colors
}
