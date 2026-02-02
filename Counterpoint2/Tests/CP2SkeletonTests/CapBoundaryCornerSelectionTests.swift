import XCTest
import CP2Geometry
import CP2Skeleton

final class CapBoundaryCornerSelectionTests: XCTestCase {
    func testCornerSelectionPicksRightAngleCorners() {
        let leftRail = [Vec2(0, -30), Vec2(200, -30)]
        let rightRail = [Vec2(0, -110), Vec2(200, -110)]
        var boundaries: [CapBoundaryDebug] = []
        _ = buildCaps(
            leftRail: leftRail,
            rightRail: rightRail,
            capNamespace: "test",
            capLocalIndex: 0,
            widthStart: 80.0,
            widthEnd: 80.0,
            startCap: .butt,
            endCap: .fillet(radius: 5.0, corner: .both),
            capFilletArcSegments: 8,
            debugFillet: nil,
            debugCapBoundary: { boundaries.append($0) }
        )
        let endBoundary = boundaries.first { $0.endpoint == "end" }
        XCTAssertNotNil(endBoundary)
        guard let boundary = endBoundary else { return }
        XCTAssertEqual(boundary.chosenIndices.count, 2)
        for theta in boundary.chosenThetas {
            XCTAssertGreaterThan(abs(theta), 1.3) // ~75deg
        }
    }
}
