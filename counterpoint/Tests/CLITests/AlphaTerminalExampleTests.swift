import XCTest
import Domain
import UseCases
import Adapters
@testable import CounterpointCLI

final class AlphaTerminalExampleTests: XCTestCase {
    func testExampleAlphaTerminalSVGWrites() throws {
        let specData = try loadFixture(named: "alpha-terminal")
        let spec = try JSONDecoder().decode(StrokeSpec.self, from: specData)
        try StrokeSpecValidator().validate(spec)

        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )
        let outline = try useCase.generateOutline(for: spec, includeBridges: true)
        let svg = SVGPathBuilder(precision: 3).svgDocument(for: outline, size: nil, padding: 10.0)

        XCTAssertTrue(svg.contains("fill-rule=\"evenodd\""))
        XCTAssertTrue(svg.contains("M "))
        XCTAssertTrue(svg.contains(" Z"))
    }

    func testAlphaBiasShrinksTerminalWidth() throws {
        let specData = try loadFixture(named: "alpha-terminal")
        let spec = try JSONDecoder().decode(StrokeSpec.self, from: specData)
        let evaluator = DefaultParamEvaluator()

        let width95 = evaluator.evaluate(spec.width, at: 0.95)
        let width98 = evaluator.evaluate(spec.width, at: 0.98)

        XCTAssertLessThan(width98, width95 * 0.5)
    }

    func testAlphaTerminalRunsWithPreviewAndFinal() throws {
        let specData = try loadFixture(named: "alpha-terminal")
        var spec = try JSONDecoder().decode(StrokeSpec.self, from: specData)

        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )

        spec.samplingPolicy = .preview
        let previewSamples = useCase.generateSamples(for: spec)
        XCTAssertLessThanOrEqual(previewSamples.count, SamplingPolicy.preview.maxSamples)
        let previewOutline = try useCase.generateOutline(for: spec, includeBridges: false)
        XCTAssertFalse(previewOutline.isEmpty)

        spec.samplingPolicy = .final
        let finalSamples = useCase.generateSamples(for: spec)
        XCTAssertLessThanOrEqual(finalSamples.count, SamplingPolicy.final.maxSamples)
        let finalOutline = try useCase.generateOutline(for: spec, includeBridges: false)
        XCTAssertFalse(finalOutline.isEmpty)
    }

    private func loadFixture(named name: String) throws -> Data {
        let fileURL = URL(fileURLWithPath: #file)
        var dir = fileURL.deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("Fixtures/specs/\(name).json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try Data(contentsOf: candidate)
            }
            dir.deleteLastPathComponent()
        }
        throw NSError(domain: "AlphaTerminalExampleTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found."])
    }
}
