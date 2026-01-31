import XCTest
import CP2Geometry
@testable import cp2_cli

final class CounterScopingTests: XCTestCase {
    func testScopedCounterDoesNotAffectTopStroke() throws {
        let spec = makeScopedCounterSpec()
        let svg = try renderSVGString(options: CLIOptions(), spec: spec)

        guard
            let compound = svg.range(of: "id=\"ink-compound\""),
            let topStroke = svg.range(of: "id=\"stroke-ink-top\"")
        else {
            XCTFail("Missing expected ink paths")
            return
        }
        XCTAssertLessThan(compound.lowerBound, topStroke.lowerBound)
    }
}

private func makeScopedCounterSpec() -> CP2Spec {
    let lineA = InkPrimitive.line(InkLine(p0: InkPoint(x: 0, y: 0), p1: InkPoint(x: 200, y: 0)))
    let lineB = InkPrimitive.line(InkLine(p0: InkPoint(x: 0, y: 10), p1: InkPoint(x: 200, y: 10)))
    let ink = Ink(stem: nil, entries: ["a": lineA, "b": lineB])
    let params = StrokeParams(
        angleMode: .relative,
        theta: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: 0.0)]),
        widthLeft: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 18.0), Keyframe(t: 1.0, value: 18.0)]),
        widthRight: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 18.0), Keyframe(t: 1.0, value: 18.0)]),
        offset: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: 0.0)])
    )
    let strokes = [
        StrokeSpec(id: "base", type: .stroke, ink: "a", params: params),
        StrokeSpec(id: "top", type: .stroke, ink: "b", params: params)
    ]
    let counters = CounterSet(entries: [
        "hole": .ellipse(
            CounterEllipse(
                at: CounterAnchor(stroke: "base", t: 0.5),
                rx: 140,
                ry: 60,
                rotateDeg: 0,
                offset: CounterOffset(t: 0.0, n: 0.0),
                appliesTo: ["base"]
            )
        )
    ])
    return CP2Spec(example: nil, render: nil, reference: nil, ink: ink, counters: counters, strokes: strokes)
}
