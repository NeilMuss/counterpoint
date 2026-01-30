import XCTest
import CP2Geometry
@testable import cp2_cli

final class MultiStrokeRenderingTests: XCTestCase {
    func testMultiStrokeRenderingEmitsPerStrokeGroups() throws {
        let lineA = InkPrimitive.line(InkLine(p0: InkPoint(x: 0, y: 0), p1: InkPoint(x: 0, y: 100)))
        let lineB = InkPrimitive.line(InkLine(p0: InkPoint(x: 200, y: 0), p1: InkPoint(x: 200, y: 100)))
        let ink = Ink(stem: nil, entries: ["a": lineA, "b": lineB])
        let strokes = [
            StrokeSpec(id: "stroke-a", type: .stroke, ink: "a"),
            StrokeSpec(id: "stroke-b", type: .stroke, ink: "b")
        ]
        let spec = CP2Spec(
            example: nil,
            render: nil,
            reference: nil,
            ink: ink,
            counters: nil,
            strokes: strokes
        )

        let svg = try renderSVGString(options: CLIOptions(), spec: spec)
        XCTAssertTrue(svg.contains("id=\"ink-compound\""))
        let pathCount = svg.components(separatedBy: "<path ").count - 1
        XCTAssertEqual(pathCount, 1)
    }
}
