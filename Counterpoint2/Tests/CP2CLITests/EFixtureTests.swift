import XCTest
import CP2Geometry
@testable import cp2_cli

final class EFixtureTests: XCTestCase {
    func testEFixtureLoadsAndRenders() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/e.v0.json")
        var options = CLIOptions()
        options.example = "e"
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("<g id=\"stroke-ink\">"))
        XCTAssertTrue(svg.contains("id=\"ink-compound\""))
        XCTAssertTrue(svg.contains("path d=\""))
    }

    func testCountersOverlayEmitsGroup() throws {
        let counters = CounterSet(entries: [
            "counter": .ink(.cubic(
                InkCubic(
                    p0: InkPoint(x: 50, y: 50),
                    p1: InkPoint(x: 20, y: 80),
                    p2: InkPoint(x: 80, y: 120),
                    p3: InkPoint(x: 50, y: 150)
                )
            ))
        ])
        let spec = CP2Spec(example: nil, render: nil, reference: nil, ink: nil, counters: counters, strokes: nil)
        var options = CLIOptions()
        options.debugCounters = true
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("id=\"debug-counters\""))
    }

    func testEFixtureEndRightFilletOverlayEmits() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/e.v0.json")
        var options = CLIOptions()
        options.debugCenterline = true
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("debug-cap-fillet-end-right"))
        XCTAssertTrue(svg.contains("debug-cap-fillet-end-left"))
    }
}
