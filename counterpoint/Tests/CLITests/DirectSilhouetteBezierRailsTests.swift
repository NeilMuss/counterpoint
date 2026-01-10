import XCTest
@testable import CounterpointCLI
import Domain
import UseCases
import Adapters

final class DirectSilhouetteBezierRailsTests: XCTestCase {
    func testDirectRailsEmitCubicSegments() throws {
        let glyphURL = try fixtureURL(pathComponents: ["Fixtures", "glyphs", "J.v0.json"])
        let data = try Data(contentsOf: glyphURL)
        let document = try JSONDecoder().decode(GlyphDocument.self, from: data)

        guard let stroke = document.inputs.geometry.strokes.first(where: { $0.id == "stroke:J-main" }) else {
            XCTFail("Missing stroke:J-main")
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
            railTolerance: spec.samplingPolicy?.envelopeTolerance ?? 0.5
        )
        guard let fitted = directFittedPath(from: direct) else {
            XCTFail("Missing direct fitted path")
            return
        }
        let segments = fitted.subpaths.flatMap { $0.segments }
        XCTAssertFalse(segments.isEmpty)
        XCTAssertTrue(segments.contains(where: { !isCollinear($0, epsilon: 1.0e-6) }))
    }

    private func isCollinear(_ segment: CubicBezier, epsilon: Double) -> Bool {
        let v = segment.p3 - segment.p0
        let v1 = segment.p1 - segment.p0
        let v2 = segment.p2 - segment.p0
        let cross1 = abs(v.x * v1.y - v.y * v1.x)
        let cross2 = abs(v.x * v2.y - v.y * v2.x)
        return cross1 <= epsilon && cross2 <= epsilon
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
