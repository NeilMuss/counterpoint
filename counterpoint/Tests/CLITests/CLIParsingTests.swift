import XCTest
@testable import CounterpointCLI

final class CLIParsingTests: XCTestCase {
    func testDumpUnionInputPathParsing() throws {
        let options = try parseOptionsForTests([
            "Fixtures/glyphs/J.v0.json",
            "--dump-union-input",
            "/tmp/union-input.json"
        ])
        XCTAssertEqual(options.dumpUnionInputPath, "/tmp/union-input.json")
    }
}
