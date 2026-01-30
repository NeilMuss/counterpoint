import XCTest
@testable import cp2_cli

final class ECounterIntegrationTest: XCTestCase {
    func testERendersCounterCompoundPath() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/e.v0.json")
        let svg = try renderSVGString(options: CLIOptions(), spec: spec)
        XCTAssertTrue(svg.contains("fill-rule=\"nonzero\""))

        guard let pathData = extractInkCompoundPathData(from: svg) else {
            XCTFail("Missing ink compound path")
            return
        }
        let subpathCount = countSubpaths(in: pathData)
        XCTAssertGreaterThanOrEqual(subpathCount, 2)
    }
}

private func extractInkCompoundPathData(from svg: String) -> String? {
    guard let idRange = svg.range(of: "id=\"ink-compound\"") else { return nil }
    guard let dRange = svg.range(of: "d=\"", range: idRange.upperBound..<svg.endIndex) else { return nil }
    let start = dRange.upperBound
    guard let end = svg[start...].firstIndex(of: "\"") else { return nil }
    return String(svg[start..<end])
}

private func countSubpaths(in d: String) -> Int {
    let tokens = d.split { $0 == " " || $0 == "\n" || $0 == "\t" }
    return tokens.filter { $0 == "M" }.count
}
