import XCTest
import CP2Geometry
@testable import cp2_cli

final class KeyframeOverlayTests: XCTestCase {
    func testKeyframeOverlayEmitsGroupAndLabels() throws {
        let render = RenderSettings(
            canvasPx: CanvasSize(width: 800, height: 800),
            fitMode: .none,
            paddingWorld: 0,
            clipToFrame: false,
            worldFrame: WorldRect(minX: 0, minY: 0, maxX: 400, maxY: 400)
        )
        let ink = Ink(stem: .line(InkLine(p0: InkPoint(x: 100, y: 0), p1: InkPoint(x: 100, y: 200))))
        let params = StrokeParams(
            angleMode: .relative,
            theta: nil,
            width: nil,
            widthLeft: KeyframedScalar(
                keyframes: [
                    Keyframe(t: 0.0, value: 20.0),
                    Keyframe(t: 0.013, value: 20.0),
                    Keyframe(t: 1.0, value: 40.0)
                ]
            ),
            widthRight: nil,
            offset: nil,
            alpha: nil
        )
        let stroke = StrokeSpec(id: "test", type: .stroke, ink: "stem", params: params)
        let spec = CP2Spec(example: nil, render: render, reference: nil, ink: ink, strokes: [stroke])
        var options = CLIOptions()
        options.debugKeyframes = true
        options.keyframesLabels = true
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("id=\"debug-keyframes\""))
        XCTAssertTrue(svg.contains(">0.013<"))
    }
}
