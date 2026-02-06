import XCTest
import CP2Geometry
@testable import CP2Skeleton

final class RectCornersCornerOrderTests: XCTestCase {
    func testCornersAreCyclicAndEdgesAlternateLengths() {
        let corners = penCorners(
            center: Vec2(0.0, 0.0),
            crossAxis: Vec2(1.0, 0.0),
            widthLeft: 50.0,
            widthRight: 50.0,
            height: 10.0
        )
        let ring = [corners.c0, corners.c1, corners.c2, corners.c3, corners.c0]
        let area = signedArea(ring)
        XCTAssertTrue(abs(area) > 1.0e-6)

        let pts = [corners.c0, corners.c1, corners.c2, corners.c3]
        var lengths: [Double] = []
        lengths.reserveCapacity(4)
        for i in 0..<4 {
            let a = pts[i]
            let b = pts[(i + 1) % 4]
            lengths.append((a - b).length)
        }
        let sorted = lengths.sorted()
        let shortLen = sorted[0]
        let longLen = sorted[3]
        XCTAssertTrue(longLen > shortLen * 2.0)

        let eps = 1.0e-6
        let evenShortOddLong = zip(lengths.indices, lengths).allSatisfy { index, len in
            if index % 2 == 0 {
                return abs(len - shortLen) <= eps
            }
            return abs(len - longLen) <= eps
        }
        let evenLongOddShort = zip(lengths.indices, lengths).allSatisfy { index, len in
            if index % 2 == 0 {
                return abs(len - longLen) <= eps
            }
            return abs(len - shortLen) <= eps
        }
        XCTAssertTrue(evenShortOddLong || evenLongOddShort)
    }
}
