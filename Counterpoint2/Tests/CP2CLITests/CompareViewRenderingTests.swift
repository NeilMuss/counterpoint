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
        options.debugCompare = true

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
        XCTAssertTrue(svg.contains("fill:none;stroke:#ff66cc;stroke-width:1;vector-effect:non-scaling-stroke"))
        XCTAssertTrue(svg.contains("id=\"stroke-ink\""))
        XCTAssertTrue(svg.contains("stroke=\"none\""))
    }

    func testCenterlineOnlyView() throws {
        let options = parseArgs(["--example", "line", "--view", "centerlineOnly"])
        let svg = try renderSVGString(options: options, spec: nil)

        XCTAssertTrue(svg.contains("stroke=\"orange\""))
        XCTAssertFalse(svg.contains("id=\"stroke-ink\""))
        XCTAssertFalse(svg.contains("id=\"reference-fill\""))
        XCTAssertFalse(svg.contains("id=\"reference-outline\""))
    }

    func testCenterlineOnlyHandlesPerSegmentType() throws {
        let cubic = InkCubic(
            p0: InkPoint(x: 0, y: 0),
            p1: InkPoint(x: 20, y: 60),
            p2: InkPoint(x: 40, y: 60),
            p3: InkPoint(x: 60, y: 0)
        )
        let line = InkLine(
            p0: InkPoint(x: 60, y: 0),
            p1: InkPoint(x: 90, y: 0)
        )
        let mixedPath = InkPath(segments: [.cubic(cubic), .line(line)])
        let mixedInk = Ink(stem: nil, entries: ["mix": .path(mixedPath)])
        let mixedSpec = CP2Spec(
            example: nil,
            render: nil,
            reference: nil,
            ink: mixedInk,
            counters: nil,
            strokes: [StrokeSpec(id: "s", type: .stroke, ink: "mix")]
        )

        let options = parseArgs(["--view", "centerlineOnly"])
        let mixedSVG = try renderSVGString(options: options, spec: mixedSpec)
        let mixedHandleLines = mixedSVG.components(separatedBy: "stroke=\"#cccccc\"").count - 1
        XCTAssertEqual(mixedHandleLines, 2)

        let lineOnlyPath = InkPath(segments: [.line(line)])
        let lineOnlyInk = Ink(stem: nil, entries: ["line": .path(lineOnlyPath)])
        let lineOnlySpec = CP2Spec(
            example: nil,
            render: nil,
            reference: nil,
            ink: lineOnlyInk,
            counters: nil,
            strokes: [StrokeSpec(id: "s", type: .stroke, ink: "line")]
        )
        let lineOnlySVG = try renderSVGString(options: options, spec: lineOnlySpec)
        let lineOnlyHandleLines = lineOnlySVG.components(separatedBy: "stroke=\"#cccccc\"").count - 1
        XCTAssertEqual(lineOnlyHandleLines, 0)
    }
}
