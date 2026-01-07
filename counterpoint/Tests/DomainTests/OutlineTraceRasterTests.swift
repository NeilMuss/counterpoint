import XCTest
import Domain

final class OutlineTraceRasterTests: XCTestCase {
    func testRasterTraceRectangleProducesOneOuterNoHoles() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 8, y: 0),
            Point(x: 8, y: 4),
            Point(x: 0, y: 4),
            Point(x: 0, y: 0)
        ]
        let input: PolygonSet = [Polygon(outer: ring)]
        let output = OutlineTracer.traceSilhouette(input, epsilon: 0.5)
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output[0].holes.count, 0)
        let area = abs(signedArea(output[0].outer))
        XCTAssertEqual(area, 32.0, accuracy: 6.0)
    }

    func testRasterTraceDonutProducesHole() {
        let outer: Ring = [
            Point(x: 0, y: 0),
            Point(x: 10, y: 0),
            Point(x: 10, y: 10),
            Point(x: 0, y: 10),
            Point(x: 0, y: 0)
        ]
        let inner: Ring = [
            Point(x: 3, y: 3),
            Point(x: 7, y: 3),
            Point(x: 7, y: 7),
            Point(x: 3, y: 7),
            Point(x: 3, y: 3)
        ]
        let input: PolygonSet = [Polygon(outer: outer, holes: [inner])]
        let output = OutlineTracer.traceSilhouette(input, epsilon: 0.5)
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output[0].holes.count, 1)
        XCTAssertGreaterThan(abs(signedArea(output[0].holes[0])), 0.1)
    }

    func testRasterTraceDeterministic() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 6, y: 0),
            Point(x: 6, y: 6),
            Point(x: 0, y: 6),
            Point(x: 0, y: 0)
        ]
        let input: PolygonSet = [Polygon(outer: ring)]
        let first = OutlineTracer.traceSilhouette(input, epsilon: 0.5)
        let second = OutlineTracer.traceSilhouette(input, epsilon: 0.5)
        XCTAssertEqual(first, second)
    }

    func testRasterTraceManyRectanglesCompletes() {
        var polygons: PolygonSet = []
        for i in 0..<20 {
            let x = Double(i) * 4.0
            let ring: Ring = [
                Point(x: x, y: 0),
                Point(x: x + 3, y: 0),
                Point(x: x + 3, y: 2),
                Point(x: x, y: 2),
                Point(x: x, y: 0)
            ]
            polygons.append(Polygon(outer: ring))
        }
        let output = OutlineTracer.traceSilhouette(polygons, epsilon: 0.25)
        XCTAssertFalse(output.isEmpty)
    }

    func testRasterClosingFillsSinglePixelHole() {
        var grid = RasterGrid(width: 5, height: 5, fill: 0)
        for y in 1...3 {
            for x in 1...3 {
                grid[x, y] = 1
            }
        }
        grid[2, 2] = 0
        let closed = closeMask(grid)
        XCTAssertEqual(closed[2, 2], 1)
        XCTAssertEqual(closed[0, 0], 0)
    }

    func testRasterTraceFiltersTinyPolygons() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 1),
            Point(x: 0, y: 1),
            Point(x: 0, y: 0)
        ]
        let input: PolygonSet = [Polygon(outer: ring)]
        let output = OutlineTracer.traceSilhouette(input, epsilon: 1.0)
        XCTAssertTrue(output.isEmpty)
    }
}
