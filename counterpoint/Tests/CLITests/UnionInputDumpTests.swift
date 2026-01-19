import XCTest
import Domain
@testable import CounterpointCLI

final class UnionInputDumpTests: XCTestCase {
    func testUnionInputDumpRoundTrip() throws {
        let rings: [Ring] = [
            [
                Point(x: 0, y: 0),
                Point(x: 10, y: 0),
                Point(x: 10, y: 10),
                Point(x: 0, y: 10),
                Point(x: 0, y: 0)
            ]
        ]
        let settings = UnionInputDumpSettings(
            batchSize: 25,
            simplifyTolerance: 0.75,
            maxVertices: 5000,
            unionMode: "force"
        )
        let dump = UnionInputDump.make(rings: rings, settings: settings)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try writeUnionInputDump(dump, to: url.path)
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(UnionInputDump.self, from: data)
        XCTAssertEqual(decoded, dump)
    }
}
