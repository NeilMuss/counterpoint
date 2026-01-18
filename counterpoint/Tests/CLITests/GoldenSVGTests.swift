import XCTest
import Foundation
import Domain
import UseCases
import Adapters
@testable import CounterpointCLI

final class GoldenSVGTests: XCTestCase {
    func testGoldenSVGs() throws {
        try SlowTestGate.requireSlowTests()
        let cases = [
            "straight-absolute",
            "straight-tangent-relative",
            "s-curve",
            "l-shape",
            "alpha-terminal",
            "teardrop-demo",
            "global-angle-scurve"
        ]

        for name in cases {
            let specURL = try fixtureURL(pathComponents: ["Fixtures", "specs", "\(name).json"])
            let expectedURL = try fixtureURL(pathComponents: ["Fixtures", "expected", "\(name).svg"])

            let specData = try Data(contentsOf: specURL)
            var spec = try JSONDecoder().decode(StrokeSpec.self, from: specData)
            if spec.samplingPolicy == nil {
                spec.samplingPolicy = .preview
            }
            try StrokeSpecValidator().validate(spec)

            let useCase = GenerateStrokeOutlineUseCase(
                sampler: DefaultPathSampler(),
                evaluator: DefaultParamEvaluator(),
                unioner: IOverlayPolygonUnionAdapter()
            )
            let outline = try useCase.generateOutline(for: spec, includeBridges: true)
            let svg = SVGPathBuilder().svgDocument(for: outline, size: nil, padding: 10.0)

            let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            XCTAssertFalse(expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Golden file is empty. Run ./Scripts/update_golden.sh")

            let normalizedActual = normalize(svg)
            let normalizedExpected = normalize(expected)
            XCTAssertEqual(normalizedActual, normalizedExpected, "Golden mismatch for \(name). Run ./Scripts/update_golden.sh")
        }
    }

    private func fixtureURL(pathComponents: [String]) throws -> URL {
        let fileURL = URL(fileURLWithPath: #file)
        var dir = fileURL.deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = pathComponents.reduce(dir) { $0.appendingPathComponent($1) }
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir.deleteLastPathComponent()
        }
        throw NSError(domain: "GoldenSVGTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixtures not found."])
    }

    private func normalize(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = unified.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.map { $0.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression) }
        return trimmed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
