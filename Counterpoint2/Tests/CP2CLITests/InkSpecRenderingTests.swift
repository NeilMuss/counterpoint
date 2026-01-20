import XCTest
import CP2Geometry
@testable import cp2_cli

final class InkSpecRenderingTests: XCTestCase {
    func testInkStemLineAffectsCenterlineSVG() throws {
        let ink = Ink(stem: .line(InkLine(p0: InkPoint(x: 200, y: 900), p1: InkPoint(x: 250, y: 300))))
        let spec = CP2Spec(example: nil, render: nil, reference: nil, ink: ink)
        var options = CLIOptions()
        options.debugCenterline = true
        options.example = nil
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("x1=\"200.0000\" y1=\"900.0000\""))
        XCTAssertTrue(svg.contains("x2=\"250.0000\" y2=\"300.0000\""))
    }

    func testInkStemCubicChangesCenterlineSVG() throws {
        let render = RenderSettings(
            canvasPx: CanvasSize(width: 800, height: 800),
            fitMode: .none,
            paddingWorld: 0,
            clipToFrame: false,
            worldFrame: WorldRect(minX: 0, minY: 0, maxX: 400, maxY: 400)
        )
        let baseInk = Ink(
            stem: .cubic(
                InkCubic(
                    p0: InkPoint(x: 100, y: 50),
                    p1: InkPoint(x: 50, y: 150),
                    p2: InkPoint(x: 150, y: 250),
                    p3: InkPoint(x: 100, y: 350)
                )
            )
        )
        let altInk = Ink(
            stem: .cubic(
                InkCubic(
                    p0: InkPoint(x: 100, y: 50),
                    p1: InkPoint(x: 80, y: 150),
                    p2: InkPoint(x: 150, y: 250),
                    p3: InkPoint(x: 100, y: 350)
                )
            )
        )
        let specA = CP2Spec(example: nil, render: render, reference: nil, ink: baseInk)
        let specB = CP2Spec(example: nil, render: render, reference: nil, ink: altInk)
        var options = CLIOptions()
        options.debugCenterline = true
        let svgA = try renderSVGString(options: options, spec: specA)
        let svgB = try renderSVGString(options: options, spec: specB)
        XCTAssertNotEqual(svgA, svgB)
        XCTAssertTrue(svgA.contains("M 100.0000 50.0000"))
        XCTAssertTrue(svgA.contains("L 100.0000 350.0000"))
    }

    func testInkCubicSamplingHitsEndpoints() {
        let cubic = InkCubic(
            p0: InkPoint(x: 0, y: 0),
            p1: InkPoint(x: 0, y: 10),
            p2: InkPoint(x: 10, y: 10),
            p3: InkPoint(x: 10, y: 0)
        )
        let points = sampleInkCubicPoints(cubic, steps: 9)
        XCTAssertEqual(points.first, Vec2(0, 0))
        XCTAssertEqual(points.last, Vec2(10, 0))
    }
}
