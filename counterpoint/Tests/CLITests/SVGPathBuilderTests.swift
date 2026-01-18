import XCTest
import Domain
@testable import CounterpointCLI

final class SVGPathBuilderTests: XCTestCase {
    func testRectangleSVGContainsPathAndViewBox() {
        let polygon = Polygon(outer: [
            Point(x: 0, y: 0),
            Point(x: 10, y: 0),
            Point(x: 10, y: 5),
            Point(x: 0, y: 5),
            Point(x: 0, y: 0)
        ])
        let svg = SVGPathBuilder(precision: 2).svgDocument(for: [polygon], size: nil, padding: 1)

        XCTAssertTrue(svg.contains("<svg"))
        XCTAssertTrue(svg.contains("viewBox=\""))
        XCTAssertTrue(svg.contains("fill-rule=\"evenodd\""))
        XCTAssertTrue(svg.contains("M"))
        XCTAssertTrue(svg.contains("Z"))
    }

    func testHoleProducesTwoSubpaths() {
        let outer: Ring = [
            Point(x: 0, y: 0),
            Point(x: 10, y: 0),
            Point(x: 10, y: 10),
            Point(x: 0, y: 10),
            Point(x: 0, y: 0)
        ]
        let hole: Ring = [
            Point(x: 3, y: 3),
            Point(x: 7, y: 3),
            Point(x: 7, y: 7),
            Point(x: 3, y: 7),
            Point(x: 3, y: 3)
        ]
        let polygon = Polygon(outer: outer, holes: [hole])
        let svg = SVGPathBuilder(precision: 2).svgDocument(for: [polygon], size: nil, padding: 0)

        let mCount = svg.components(separatedBy: "M ").count - 1
        let zCount = svg.components(separatedBy: " Z").count - 1
        XCTAssertGreaterThanOrEqual(mCount, 2)
        XCTAssertGreaterThanOrEqual(zCount, 2)
        XCTAssertTrue(svg.contains("fill-rule=\"evenodd\""))
    }

    func testRailsSamplesOverlayEmitsLabelAndCrosshairEvenEmpty() {
        let polygon = Polygon(outer: [
            Point(x: 0, y: 0),
            Point(x: 10, y: 0),
            Point(x: 10, y: 5),
            Point(x: 0, y: 5),
            Point(x: 0, y: 0)
        ])
        let overlay = SVGDebugOverlay(
            skeleton: [],
            stamps: [],
            bridges: [],
            samplePoints: [],
            keyframeMarkers: [],
            tangentRays: [],
            angleRays: [],
            offsetRays: [],
            envelopeLeft: [],
            envelopeRight: [],
            envelopeOutline: [],
            capPoints: [],
            leftRailSamples: [],
            rightRailSamples: [],
            showRailsSamples: true,
            showRailsNormals: false,
            showRailsIndices: false,
            railsSampleOptions: SVGDebugOverlay.RailsSampleOptions(step: 1, start: 0, count: 10, tMin: nil, tMax: nil),
            junctionPatches: [],
            junctionCorridors: [],
            junctionControlPoints: [],
            showUnionOutline: false,
            unionPolygons: nil
        )

        let svg = SVGPathBuilder(precision: 2).svgDocument(for: [polygon], size: nil, padding: 1, debugOverlay: overlay)
        XCTAssertTrue(svg.contains("id=\"debug-rails-samples\""))
        XCTAssertTrue(svg.contains("railsSamples"))
        XCTAssertTrue(svg.contains("<line"))
        XCTAssertTrue(svg.contains("<text"))
    }

    func testRailOverlayItemsRespectGlobalTWindow() {
        let samples: [SVGDebugOverlay.RailDebugSample] = [
            .init(t: 0.0, point: Point(x: 0, y: 0), normal: Point(x: 0, y: 1)),
            .init(t: 0.25, point: Point(x: 1, y: 0), normal: Point(x: 0, y: 1)),
            .init(t: 0.5, point: Point(x: 2, y: 0), normal: Point(x: 0, y: 1)),
            .init(t: 0.75, point: Point(x: 3, y: 0), normal: Point(x: 0, y: 1)),
            .init(t: 1.0, point: Point(x: 4, y: 0), normal: Point(x: 0, y: 1))
        ]
        var overlay = SVGDebugOverlay(
            skeleton: [],
            stamps: [],
            bridges: [],
            samplePoints: [],
            keyframeMarkers: [],
            tangentRays: [],
            angleRays: [],
            offsetRays: [],
            envelopeLeft: [],
            envelopeRight: [],
            envelopeOutline: [],
            capPoints: [],
            leftRailSamples: [],
            rightRailSamples: samples,
            showRailsSamples: true,
            showRailsNormals: false,
            showRailsIndices: true,
            railsSampleOptions: SVGDebugOverlay.RailsSampleOptions(step: 1, start: 0, count: 10, tMin: nil, tMax: nil),
            junctionPatches: [],
            junctionCorridors: [],
            junctionControlPoints: [],
            showUnionOutline: false,
            unionPolygons: nil
        )
        overlay.railsWindowGT0 = 0.4
        overlay.railsWindowGT1 = 0.6

        let items = SVGPathBuilder(precision: 2).railOverlayItems(overlay)
        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertGreaterThanOrEqual(item.globalT, 0.4 - 1.0e-6)
            XCTAssertLessThanOrEqual(item.globalT, 0.6 + 1.0e-6)
        }
    }

    func testRingOverlayItemsRespectGlobalTWindow() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 10, y: 0),
            Point(x: 10, y: 10),
            Point(x: 0, y: 10),
            Point(x: 0, y: 0)
        ]
        var overlay = SVGDebugOverlay(
            skeleton: [],
            stamps: [],
            bridges: [],
            samplePoints: [],
            keyframeMarkers: [],
            tangentRays: [],
            angleRays: [],
            offsetRays: [],
            envelopeLeft: [],
            envelopeRight: [],
            envelopeOutline: [],
            capPoints: [],
            leftRailSamples: [],
            rightRailSamples: [],
            railsRings: [ring],
            showRailsRing: true,
            showRailsSamples: false,
            showRailsNormals: false,
            showRailsIndices: false,
            railsSampleOptions: SVGDebugOverlay.RailsSampleOptions(),
            junctionPatches: [],
            junctionCorridors: [],
            junctionControlPoints: [],
            showUnionOutline: false,
            unionPolygons: nil
        )
        overlay.ringWindowGT0 = 0.2
        overlay.ringWindowGT1 = 0.6

        let items = SVGPathBuilder(precision: 2).ringOverlayItems(overlay, name: "railsRing")
        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertGreaterThanOrEqual(item.ringGT, 0.2 - 1.0e-6)
            XCTAssertLessThanOrEqual(item.ringGT, 0.6 + 1.0e-6)
        }
    }
}
