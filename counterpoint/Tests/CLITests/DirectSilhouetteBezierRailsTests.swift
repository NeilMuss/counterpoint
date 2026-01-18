import XCTest
@testable import CounterpointCLI
import Domain
import UseCases
import Adapters

final class DirectSilhouetteBezierRailsTests: XCTestCase {
    func testDirectRailsEmitCubicSegments() throws {
        let glyphURL = try fixtureURL(pathComponents: ["Tests", "Fixtures", "glyph_v0_min.json"])
        let data = try Data(contentsOf: glyphURL)
        let document = try JSONDecoder().decode(GlyphDocument.self, from: data)

        guard let stroke = document.inputs.geometry.strokes.first(where: { $0.id == "stroke-main" }) else {
            XCTFail("Missing stroke-main")
            return
        }
        let pathById = Dictionary(uniqueKeysWithValues: document.inputs.geometry.paths.map { ($0.id, $0) })
        guard let spec = strokeSpec(from: stroke, paths: pathById, quality: "final") else {
            XCTFail("Failed to build stroke spec")
            return
        }

        let skeletonPaths = stroke.skeletons.compactMap { pathById[$0] }.compactMap(bezierPath(from:))
        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )
        let concatenated = useCase.generateConcatenatedSamplesWithJunctions(for: spec, paths: skeletonPaths)
        let direct = DirectSilhouetteTracer.trace(
            samples: concatenated.samples,
            capStyle: spec.capStyle,
            railTolerance: spec.samplingPolicy?.railTolerance ?? spec.samplingPolicy?.envelopeTolerance ?? 0.5
        )
        guard let fitted = directFittedPath(from: direct) else {
            XCTFail("Missing direct fitted path")
            return
        }
        let segments = fitted.subpaths.flatMap { $0.segments }
        XCTAssertFalse(segments.isEmpty)
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
        throw NSError(domain: "DirectSilhouetteBezierRailsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixtures not found."])
    }
}
