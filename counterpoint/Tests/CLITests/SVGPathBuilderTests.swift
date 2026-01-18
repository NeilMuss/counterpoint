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
}
