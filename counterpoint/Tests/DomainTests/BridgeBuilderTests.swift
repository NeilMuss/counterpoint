import XCTest
@testable import Domain

final class BridgeBuilderTests: XCTestCase {
    func testBridgeQuadNoCrossing() throws {
        let ringA = rectangle(centerX: 0, centerY: 0, width: 10, height: 6)
        let ringB = rectangle(centerX: 10, centerY: 5, width: 10, height: 6)

        let bridges = try BridgeBuilder().bridgeRings(from: ringA, to: ringB)
        XCTAssertEqual(bridges.count, 4)

        for ring in bridges {
            XCTAssertEqual(ring.first, ring.last)
            XCTAssertGreaterThan(abs(ringAreaSigned(ring)), 0.0001)
            XCTAssertEqual(ring.count, 5)
        }
    }

    func testBridgeInversionSplitsToTriangles() throws {
        let ringA: Ring = [
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 1),
            Point(x: 0, y: 1),
            Point(x: 0, y: 0)
        ]
        let ringB: Ring = [
            Point(x: 1, y: 1),
            Point(x: 0, y: 1),
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 1)
        ]

        let bridges = try BridgeBuilder().bridgeRings(from: ringA, to: ringB)
        XCTAssertGreaterThan(bridges.count, 4)
        XCTAssertTrue(bridges.contains { $0.count == 4 })
        for ring in bridges {
            XCTAssertEqual(ring.first, ring.last)
            XCTAssertGreaterThan(abs(ringAreaSigned(ring)), 0.0001)
        }
    }

    private func rectangle(centerX: Double, centerY: Double, width: Double, height: Double) -> Ring {
        let hw = width * 0.5
        let hh = height * 0.5
        return [
            Point(x: centerX - hw, y: centerY - hh),
            Point(x: centerX + hw, y: centerY - hh),
            Point(x: centerX + hw, y: centerY + hh),
            Point(x: centerX - hw, y: centerY + hh),
            Point(x: centerX - hw, y: centerY - hh)
        ]
    }
}
