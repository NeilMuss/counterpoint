import XCTest
import CP2Geometry
@testable import cp2_cli

final class FinalContourSelectionTests: XCTestCase {
    func testSelectFinalContourUsesEnvelopeWhenSimple() {
        let ring = [
            Vec2(0, 0),
            Vec2(10, 0),
            Vec2(10, 5),
            Vec2(0, 5),
            Vec2(0, 0)
        ]
        let selection = selectFinalContour(
            rawRings: [ring],
            planarRings: nil,
            faces: nil
        )
        XCTAssertEqual(selection.envelopeIndex, 0)
        XCTAssertEqual(selection.finalContour.provenance, .tracedRing(index: 0))
        XCTAssertEqual(selection.finalContour.reason, "max-area-simple")
        XCTAssertEqual(selection.ring, ring)
    }
}
