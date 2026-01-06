import XCTest
import Foundation
import Domain
import UseCases
import Adapters
@testable import CounterpointCLI

final class TeardropDemoTests: XCTestCase {
    func testTeardropDemoUnionIsSmall() throws {
        var spec = try loadFixture(named: "teardrop-demo")
        spec.samplingPolicy = .preview
        if case .ellipse = spec.counterpointShape {
            spec.counterpointShape = .ellipse(segments: 24)
        }
        try StrokeSpecValidator().validate(spec)

        let outline = try makeUseCase().generateOutline(for: spec, includeBridges: true)
        XCTAssertFalse(outline.isEmpty)
        XCTAssertLessThanOrEqual(outline.count, 8)
    }

    func testTeardropDemoSVGDeterminism() throws {
        var spec = try loadFixture(named: "teardrop-demo")
        spec.samplingPolicy = .preview
        if case .ellipse = spec.counterpointShape {
            spec.counterpointShape = .ellipse(segments: 24)
        }
        try StrokeSpecValidator().validate(spec)

        let useCase = makeUseCase()
        let outlineA = try useCase.generateOutline(for: spec, includeBridges: true)
        let outlineB = try useCase.generateOutline(for: spec, includeBridges: true)
        let builder = SVGPathBuilder(precision: 4)
        let svgA = normalize(builder.svgDocument(for: outlineA, size: nil, padding: 10.0))
        let svgB = normalize(builder.svgDocument(for: outlineB, size: nil, padding: 10.0))

        XCTAssertEqual(svgA, svgB)
    }

    private func makeUseCase() -> GenerateStrokeOutlineUseCase {
        GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: IOverlayPolygonUnionAdapter()
        )
    }

    private func loadFixture(named name: String) throws -> StrokeSpec {
        let fileURL = URL(fileURLWithPath: #file)
        var dir = fileURL.deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("Fixtures/specs/\(name).json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                let data = try Data(contentsOf: candidate)
                return try JSONDecoder().decode(StrokeSpec.self, from: data)
            }
            dir.deleteLastPathComponent()
        }
        throw NSError(domain: "TeardropDemoTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found."])
    }

    private func normalize(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = unified.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.map { $0.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression) }
        return trimmed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
