import XCTest
import Domain

final class GeometrySegmentsTests: XCTestCase {
    func testSegmentsFromRingClosesAndDedupes() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 0, y: 0),
            Point(x: 2, y: 0),
            Point(x: 2, y: 1)
        ]
        let segmentsList = segments(from: ring, ensureClosed: true)
        XCTAssertEqual(segmentsList.count, 3)
        XCTAssertEqual(segmentsList.first?.a, Point(x: 0, y: 0))
        XCTAssertEqual(segmentsList.last?.b, Point(x: 0, y: 0))
    }

    func testIntersectionProperCross() {
        let s1 = Segment(a: Point(x: 0, y: 0), b: Point(x: 2, y: 2))
        let s2 = Segment(a: Point(x: 0, y: 2), b: Point(x: 2, y: 0))
        let result = intersect(s1, s2)
        switch result {
        case .proper(let point):
            XCTAssertEqual(point.x, 1.0, accuracy: 1.0e-9)
            XCTAssertEqual(point.y, 1.0, accuracy: 1.0e-9)
        default:
            XCTFail("Expected proper intersection")
        }
    }

    func testIntersectionEndpointTouch() {
        let s1 = Segment(a: Point(x: 0, y: 0), b: Point(x: 1, y: 0))
        let s2 = Segment(a: Point(x: 1, y: 0), b: Point(x: 2, y: 0))
        let result = intersect(s1, s2)
        switch result {
        case .endpoint(let point):
            XCTAssertEqual(point, Point(x: 1, y: 0))
        default:
            XCTFail("Expected endpoint intersection")
        }
    }

    func testIntersectionParallelNone() {
        let s1 = Segment(a: Point(x: 0, y: 0), b: Point(x: 1, y: 0))
        let s2 = Segment(a: Point(x: 0, y: 1), b: Point(x: 1, y: 1))
        XCTAssertEqual(intersect(s1, s2), .none)
    }

    func testIntersectionCollinearOverlap() {
        let s1 = Segment(a: Point(x: 0, y: 0), b: Point(x: 3, y: 0))
        let s2 = Segment(a: Point(x: 1, y: 0), b: Point(x: 2, y: 0))
        let result = intersect(s1, s2)
        switch result {
        case .collinearOverlap(let overlap):
            XCTAssertEqual(overlap.a, Point(x: 1, y: 0))
            XCTAssertEqual(overlap.b, Point(x: 2, y: 0))
        default:
            XCTFail("Expected collinear overlap")
        }
    }

    func testIntersectionCollinearDisjointNone() {
        let s1 = Segment(a: Point(x: 0, y: 0), b: Point(x: 1, y: 0))
        let s2 = Segment(a: Point(x: 2, y: 0), b: Point(x: 3, y: 0))
        XCTAssertEqual(intersect(s1, s2), .none)
    }
}
