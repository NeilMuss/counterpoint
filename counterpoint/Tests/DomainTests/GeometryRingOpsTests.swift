import XCTest
import Domain

final class GeometryRingOpsTests: XCTestCase {
    func testIsClosedExact() {
        let closed: Ring = [
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 1),
            Point(x: 0, y: 0)
        ]
        let open: Ring = [
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 1)
        ]
        XCTAssertTrue(isClosed(closed))
        XCTAssertFalse(isClosed(open))
    }

    func testCloseRingIfNeededAppendsFirstPoint() {
        let open: Ring = [
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 1)
        ]
        let closed = closeRingIfNeeded(open)
        XCTAssertEqual(closed.first, closed.last)
        XCTAssertEqual(closed.count, open.count + 1)
    }

    func testRemoveConsecutiveDuplicatesExact() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 1)
        ]
        let cleaned = removeConsecutiveDuplicates(ring)
        XCTAssertEqual(cleaned, [
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 1)
        ])
    }

    func testSignedAreaRectanglePositiveOrNegative() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 2, y: 0),
            Point(x: 2, y: 1),
            Point(x: 0, y: 1)
        ]
        let area = signedArea(ring)
        XCTAssertEqual(abs(area), 2.0, accuracy: 1.0e-9)
    }

    func testNormalizeRingRejectsDegenerate() {
        XCTAssertNil(normalizeRing([]))
        XCTAssertNil(normalizeRing([Point(x: 0, y: 0)]))
        XCTAssertNil(normalizeRing([Point(x: 0, y: 0), Point(x: 1, y: 1)]))
        let collinear: Ring = [
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 2, y: 0)
        ]
        XCTAssertNil(normalizeRing(collinear))
    }

    func testNormalizeRingIsDeterministic() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 0, y: 0),
            Point(x: 2, y: 0),
            Point(x: 2, y: 1),
            Point(x: 0, y: 1)
        ]
        let first = normalizeRing(ring)
        let second = normalizeRing(ring)
        XCTAssertEqual(first, second)
    }
}
