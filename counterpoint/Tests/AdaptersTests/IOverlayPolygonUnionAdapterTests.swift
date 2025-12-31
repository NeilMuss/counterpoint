import XCTest
@testable import Adapters
@testable import Domain

final class IOverlayPolygonUnionAdapterTests: XCTestCase {
    func testUnionOverlappingRectangles() throws {
        let rectA: Ring = [
            Point(x: 0, y: 0),
            Point(x: 10, y: 0),
            Point(x: 10, y: 10),
            Point(x: 0, y: 10),
            Point(x: 0, y: 0)
        ]
        let rectB: Ring = [
            Point(x: 5, y: 0),
            Point(x: 15, y: 0),
            Point(x: 15, y: 10),
            Point(x: 5, y: 10),
            Point(x: 5, y: 0)
        ]

        let adapter = IOverlayPolygonUnionAdapter()
        let result = try adapter.union(subjectRings: [rectA, rectB])

        XCTAssertEqual(result.count, 1)
        guard let polygon = result.first else {
            XCTFail("Expected one polygon")
            return
        }
        XCTAssertGreaterThan(polygon.outer.count, 3)
        XCTAssertEqual(polygon.outer.first, polygon.outer.last)

        let bounds = boundsOf(polygon: polygon)
        XCTAssertEqual(bounds.minX, 0.0, accuracy: 0.25)
        XCTAssertEqual(bounds.maxX, 15.0, accuracy: 0.25)
        XCTAssertEqual(bounds.minY, 0.0, accuracy: 0.25)
        XCTAssertEqual(bounds.maxY, 10.0, accuracy: 0.25)
    }

    private func boundsOf(polygon: Domain.Polygon) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for point in polygon.outer {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return (minX, maxX, minY, maxY)
    }
}
