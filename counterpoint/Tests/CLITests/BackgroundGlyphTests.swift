import XCTest
import Domain
import UseCases
import Adapters
@testable import CounterpointCLI

final class BackgroundGlyphTests: XCTestCase {
    func testBackgroundGlyphPathRendersInSVG() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M 0 0 L 10 0 L 10 10 Z"/>
          <path d="M 20 0 L 30 0 L 30 10 Z"/>
        </svg>
        """
        let tempDir = FileManager.default.temporaryDirectory
        let svgURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("svg")
        try svg.write(to: svgURL, atomically: true, encoding: .utf8)

        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 20, y: 0),
                    p2: Point(x: 40, y: 0),
                    p3: Point(x: 60, y: 0)
                )
            ]),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(10),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(),
            backgroundGlyph: BackgroundGlyph(
                svgPath: svgURL.path,
                opacity: 1.0,
                zoom: 100.0,
                fill: "#e0e0e0",
                stroke: "#4169e1",
                strokeWidth: 1.0,
                align: .none
            )
        )

        let outline = try GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        ).generateOutline(for: spec)

        let source = try XCTUnwrap(SVGPathBuilder.loadBackgroundGlyph(from: spec.backgroundGlyph!.svgPath))
        let render = SVGPathBuilder.BackgroundGlyphRender(
            elements: source.elements,
            bounds: source.bounds,
            fill: spec.backgroundGlyph!.fill,
            stroke: spec.backgroundGlyph!.stroke,
            strokeWidth: spec.backgroundGlyph!.strokeWidth,
            opacity: spec.backgroundGlyph!.opacity,
            zoom: spec.backgroundGlyph!.zoom,
            align: spec.backgroundGlyph!.align,
            manualTransform: SVGPathBuilder.parseTransformString(spec.backgroundGlyph!.transform)
        )

        let output = SVGPathBuilder().svgDocument(
            for: outline,
            size: nil,
            padding: 10.0,
            backgroundGlyph: render
        )

        XCTAssertTrue(output.contains("fill=\"#e0e0e0\""))
        XCTAssertTrue(output.contains("stroke=\"#4169e1\""))
        XCTAssertTrue(output.contains("d=\"M 0 0 L 10 0 L 10 10 Z\""))
        XCTAssertTrue(output.contains("d=\"M 20 0 L 30 0 L 30 10 Z\""))
    }

    func testBackgroundGlyphWithoutViewBoxExpandsOutputBounds() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M 200 100 L 210 100 L 210 110 L 200 110 Z"/>
        </svg>
        """
        let tempDir = FileManager.default.temporaryDirectory
        let svgURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("svg")
        try svg.write(to: svgURL, atomically: true, encoding: .utf8)

        let spec = StrokeSpec(
            path: BezierPath(segments: [
                CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 20, y: 0),
                    p2: Point(x: 40, y: 0),
                    p3: Point(x: 60, y: 0)
                )
            ]),
            width: ParamTrack.constant(10),
            height: ParamTrack.constant(10),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec(),
            backgroundGlyph: BackgroundGlyph(
                svgPath: svgURL.path,
                opacity: 1.0,
                zoom: 100.0,
                align: .none
            )
        )

        let outline = try GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        ).generateOutline(for: spec)

        let source = try XCTUnwrap(SVGPathBuilder.loadBackgroundGlyph(from: spec.backgroundGlyph!.svgPath))
        let render = SVGPathBuilder.BackgroundGlyphRender(
            elements: source.elements,
            bounds: source.bounds,
            fill: spec.backgroundGlyph!.fill,
            stroke: spec.backgroundGlyph!.stroke,
            strokeWidth: spec.backgroundGlyph!.strokeWidth,
            opacity: spec.backgroundGlyph!.opacity,
            zoom: spec.backgroundGlyph!.zoom,
            align: spec.backgroundGlyph!.align,
            manualTransform: SVGPathBuilder.parseTransformString(spec.backgroundGlyph!.transform)
        )

        let output = SVGPathBuilder().svgDocument(
            for: outline,
            size: nil,
            padding: 10.0,
            backgroundGlyph: render
        )

        let viewBox = try XCTUnwrap(parseViewBox(from: output))
        XCTAssertGreaterThanOrEqual(viewBox.maxX, 210.0)
        XCTAssertGreaterThanOrEqual(viewBox.maxY, 110.0)
        XCTAssertTrue(output.contains("id=\"background-glyph\""))
    }

    private func parseViewBox(from svg: String) -> CGRect? {
        let pattern = "viewBox=\\\"([0-9eE\\-\\.\\s]+)\\\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(svg.startIndex..<svg.endIndex, in: svg)
        guard let match = regex.firstMatch(in: svg, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: svg) else {
            return nil
        }
        let parts = svg[valueRange].split(whereSeparator: { $0 == " " || $0 == "," })
        guard parts.count == 4,
              let minX = Double(parts[0]),
              let minY = Double(parts[1]),
              let width = Double(parts[2]),
              let height = Double(parts[3]) else {
            return nil
        }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}
