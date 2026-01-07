import XCTest
import Domain

final class OutlineTracerTests: XCTestCase {
    func testTraceSilhouetteReturnsInput() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 10, y: 0),
            Point(x: 10, y: 5),
            Point(x: 0, y: 5),
            Point(x: 0, y: 0)
        ]
        let input: PolygonSet = [Polygon(outer: ring)]
        let output = OutlineTracer.traceSilhouette(input, epsilon: 0.01)
        XCTAssertEqual(output, input)
    }
}
