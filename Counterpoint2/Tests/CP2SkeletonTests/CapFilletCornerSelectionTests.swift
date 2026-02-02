import XCTest
import CP2Geometry
import CP2Skeleton

final class CapFilletCornerSelectionTests: XCTestCase {
    func testRightCornerSelectionUsesRightRailVertex() {
        let leftRail = [Vec2(0, 0), Vec2(10, 0)]
        let rightRail = [Vec2(0, 10), Vec2(10, 10)]

        var rightFillets: [CapFilletDebug] = []
        _ = buildCaps(
            leftRail: leftRail,
            rightRail: rightRail,
            capNamespace: "test",
            capLocalIndex: 0,
            widthStart: 20.0,
            widthEnd: 20.0,
            startCap: .fillet(radius: 2.0, corner: .right),
            endCap: .butt,
            debugFillet: { rightFillets.append($0) }
        )

        guard let right = rightFillets.first(where: { $0.kind == "start" && $0.side == "right" }) else {
            XCTFail("Missing right fillet debug")
            return
        }
        XCTAssertTrue(right.success)
        XCTAssertLessThan((right.corner - leftRail[0]).length, 1.0e-6)

        var leftFillets: [CapFilletDebug] = []
        _ = buildCaps(
            leftRail: leftRail,
            rightRail: rightRail,
            capNamespace: "test",
            capLocalIndex: 0,
            widthStart: 20.0,
            widthEnd: 20.0,
            startCap: .fillet(radius: 2.0, corner: .left),
            endCap: .butt,
            debugFillet: { leftFillets.append($0) }
        )

        guard let left = leftFillets.first(where: { $0.kind == "start" && $0.side == "left" }) else {
            XCTFail("Missing left fillet debug")
            return
        }
        XCTAssertTrue(left.success)
        XCTAssertLessThan((left.corner - rightRail[0]).length, 1.0e-6)
        XCTAssertGreaterThan((left.corner - right.corner).length, 1.0e-3)
    }
}
