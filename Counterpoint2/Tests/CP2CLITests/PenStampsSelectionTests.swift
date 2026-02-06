import XCTest
@testable import cp2_cli

final class PenStampsSelectionTests: XCTestCase {
    func testSampleIndexSelectionIsInclusiveAndDeterministic() {
        let indices = selectPenStampTargetIndices(start: 0, end: 63, step: 16)
        XCTAssertEqual(indices, [0, 16, 32, 48])
    }

    func testGTSelectionIsInclusiveAndDeterministic() {
        let gts = selectPenStampTargetGTs(start: 0.30, end: 0.55, step: 0.02)
        XCTAssertEqual(gts.count, 13)
        XCTAssertEqual(gts.first ?? -1.0, 0.30, accuracy: 1.0e-9)
        XCTAssertEqual(gts.last ?? -1.0, 0.54, accuracy: 1.0e-9)
    }
}
