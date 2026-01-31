import XCTest
import CP2Geometry
@testable import cp2_cli

final class CounterClipPreviewTests: XCTestCase {
    func testClipCountersToInkEmitsClipPathAndSeparateCounter() throws {
        let spec = makeOversizedCounterSpec()
        var options = CLIOptions()
        options.clipCountersToInk = true
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("id=\"ink-shape\""))
        XCTAssertTrue(svg.contains("id=\"counter-shape\""))
        XCTAssertTrue(svg.contains("clip-path=\"url(#clip-ink)\""))
        XCTAssertTrue(svg.contains("clipPath id=\"clip-ink\""))
    }

    func testDefaultModeDoesNotEmitClipPath() throws {
        let spec = makeOversizedCounterSpec()
        let svg = try renderSVGString(options: CLIOptions(), spec: spec)
        XCTAssertFalse(svg.contains("clipPath id=\"clip-ink\""))
        XCTAssertFalse(svg.contains("id=\"counter-shape\""))
    }
}

private func makeOversizedCounterSpec() -> CP2Spec {
    let line = InkPrimitive.line(InkLine(p0: InkPoint(x: 0, y: 0), p1: InkPoint(x: 200, y: 0)))
    let ink = Ink(stem: nil, entries: ["line": line])
    let params = StrokeParams(
        angleMode: .relative,
        theta: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: 0.0)]),
        widthLeft: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 20.0), Keyframe(t: 1.0, value: 20.0)]),
        widthRight: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 20.0), Keyframe(t: 1.0, value: 20.0)]),
        offset: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: 0.0)])
    )
    let stroke = StrokeSpec(id: "line-stroke", type: .stroke, ink: "line", params: params)
    let counters = CounterSet(entries: [
        "oversize": .ellipse(
            CounterEllipse(
                at: CounterAnchor(stroke: "line-stroke", t: 0.5),
                rx: 200,
                ry: 120,
                rotateDeg: 0,
                offset: CounterOffset(t: 0.0, n: 0.0)
            )
        )
    ])
    return CP2Spec(example: nil, render: nil, reference: nil, ink: ink, counters: counters, strokes: [stroke])
}
