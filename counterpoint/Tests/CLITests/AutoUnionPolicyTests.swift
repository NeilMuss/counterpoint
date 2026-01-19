import XCTest
@testable import CounterpointCLI

final class AutoUnionPolicyTests: XCTestCase {
    func testForceBypassesTouchingPairSkip() {
        let shouldSkip = shouldSkipAutoUnionForTouchingPairs(
            policy: .force,
            touchingPairsRemaining: 45,
            droppedCount: 0,
            maxDrops: 10
        )
        XCTAssertFalse(shouldSkip)
    }

    func testAutoPreservesTouchingPairSkip() {
        let shouldSkip = shouldSkipAutoUnionForTouchingPairs(
            policy: .auto,
            touchingPairsRemaining: 45,
            droppedCount: 0,
            maxDrops: 10
        )
        XCTAssertTrue(shouldSkip)
    }
}
