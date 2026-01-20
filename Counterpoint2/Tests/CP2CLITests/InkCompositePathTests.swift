import XCTest
import CP2Geometry
@testable import cp2_cli

final class InkCompositePathTests: XCTestCase {
    func testCompositeContinuousPathRendersBothSegments() throws {
        let render = RenderSettings(
            canvasPx: CanvasSize(width: 800, height: 800),
            fitMode: .none,
            paddingWorld: 0,
            clipToFrame: false,
            worldFrame: WorldRect(minX: 0, minY: 0, maxX: 400, maxY: 400)
        )
        let path = InkPath(segments: [
            .line(InkLine(p0: InkPoint(x: 100, y: 50), p1: InkPoint(x: 100, y: 200))),
            .cubic(InkCubic(
                p0: InkPoint(x: 100, y: 200),
                p1: InkPoint(x: 50, y: 260),
                p2: InkPoint(x: 150, y: 320),
                p3: InkPoint(x: 100, y: 350)
            ))
        ])
        let ink = Ink(stem: .path(path), entries: ["stem": .path(path)])
        let spec = CP2Spec(example: nil, render: render, reference: nil, ink: ink)
        var options = CLIOptions()
        options.debugCenterline = true
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("x1=\"100.0000\" y1=\"50.0000\""))
        XCTAssertTrue(svg.contains("M 100.0000 200.0000"))
    }

    func testDiscontinuityWarnsAndStrictFails() {
        let render = RenderSettings(
            canvasPx: CanvasSize(width: 800, height: 800),
            fitMode: .none,
            paddingWorld: 0,
            clipToFrame: false,
            worldFrame: WorldRect(minX: 0, minY: 0, maxX: 400, maxY: 400)
        )
        let path = InkPath(segments: [
            .line(InkLine(p0: InkPoint(x: 0, y: 0), p1: InkPoint(x: 0, y: 50))),
            .line(InkLine(p0: InkPoint(x: 100, y: 100), p1: InkPoint(x: 100, y: 150)))
        ])
        let ink = Ink(stem: .path(path), entries: ["stem": .path(path)])
        let spec = CP2Spec(example: nil, render: render, reference: nil, ink: ink)
        var warnings: [String] = []
        var options = CLIOptions()
        options.debugCenterline = true
        options.strictInk = false
        _ = try? renderSVGString(options: options, spec: spec, warnSink: { warnings.append($0) })
        XCTAssertTrue(warnings.contains { $0.contains("ink continuity warning") })

        options.strictInk = true
        XCTAssertThrowsError(try renderSVGString(options: options, spec: spec))
    }

    func testInkSelectionChoosesNamedEntry() throws {
        let render = RenderSettings(
            canvasPx: CanvasSize(width: 800, height: 800),
            fitMode: .none,
            paddingWorld: 0,
            clipToFrame: false,
            worldFrame: WorldRect(minX: 0, minY: 0, maxX: 400, maxY: 400)
        )
        let stem = InkPrimitive.line(InkLine(p0: InkPoint(x: 10, y: 10), p1: InkPoint(x: 10, y: 100)))
        let spine = InkPrimitive.line(InkLine(p0: InkPoint(x: 200, y: 10), p1: InkPoint(x: 200, y: 100)))
        let ink = Ink(stem: stem, entries: ["stem": stem, "spine": spine])
        let spec = CP2Spec(example: nil, render: render, reference: nil, ink: ink)
        var options = CLIOptions()
        options.debugCenterline = true
        options.inkName = "spine"
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("x1=\"200.0000\" y1=\"10.0000\""))
    }

    func testHeartlineExpansionIncludesBothParts() throws {
        let render = RenderSettings(
            canvasPx: CanvasSize(width: 800, height: 800),
            fitMode: .none,
            paddingWorld: 0,
            clipToFrame: false,
            worldFrame: WorldRect(minX: 0, minY: 0, maxX: 400, maxY: 400)
        )
        let spine = InkPrimitive.cubic(
            InkCubic(
                p0: InkPoint(x: 100, y: 50),
                p1: InkPoint(x: 80, y: 150),
                p2: InkPoint(x: 120, y: 250),
                p3: InkPoint(x: 100, y: 300)
            )
        )
        let hook = InkPrimitive.cubic(
            InkCubic(
                p0: InkPoint(x: 100, y: 300),
                p1: InkPoint(x: 130, y: 320),
                p2: InkPoint(x: 160, y: 260),
                p3: InkPoint(x: 140, y: 220)
            )
        )
        let heartline = InkPrimitive.heartline(Heartline(parts: ["spine", "hook"]))
        let ink = Ink(stem: heartline, entries: ["spine": spine, "hook": hook, "J_heartline": heartline])
        let spec = CP2Spec(example: nil, render: render, reference: nil, ink: ink)
        var options = CLIOptions()
        options.debugCenterline = true
        options.inkName = "J_heartline"
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("spine"))
        XCTAssertTrue(svg.contains("hook"))
    }
}
