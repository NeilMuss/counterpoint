import XCTest
@testable import Domain

final class StrokeTipCodableTests: XCTestCase {
    func testStrokeTipSpecRoundTrip() throws {
        let spec = StrokeTipSpec(id: "a", offset: 1.25)
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(StrokeTipSpec.self, from: data)
        XCTAssertEqual(decoded, spec)
    }

    func testStrokeTipsSingleRoundTrip() throws {
        let tips = StrokeTips.single(42)
        let data = try JSONEncoder().encode(tips)
        let decoded = try JSONDecoder().decode(StrokeTips<Int>.self, from: data)
        XCTAssertEqual(decoded, tips)
        XCTAssertTrue(decoded.isSingle)
        XCTAssertEqual(decoded.default, 42)
        XCTAssertEqual(decoded.tips.count, 1)
        XCTAssertTrue(decoded.tips.keys.contains("default"))
    }
}
