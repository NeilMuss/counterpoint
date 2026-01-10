import XCTest
@testable import CounterpointCLI
import Domain
@testable import UseCases
import Adapters

final class GlyphAlphaIntegrationTests: XCTestCase {
    func testGlyphFixtureAlphaPreservedAndAffectsEvaluation() throws {
        let glyphURL = try fixtureURL(pathComponents: ["Fixtures", "glyphs", "J.v0.json"])
        let data = try Data(contentsOf: glyphURL)
        let document = try JSONDecoder().decode(GlyphDocument.self, from: data)

        guard let stroke = document.inputs.geometry.strokes.first(where: { $0.id == "stroke:J-main" }) else {
            XCTFail("Missing stroke:J-main")
            return
        }
        guard let keyframe = stroke.params.width.keyframes.first(where: { abs($0.t - 0.01) < 1.0e-6 }) else {
            XCTFail("Missing width keyframe at t=0.01")
            return
        }
        XCTAssertNotNil(keyframe.interpolationToNext)
        XCTAssertEqual(keyframe.interpolationToNext?.alpha ?? 0.0, -2.85, accuracy: 1.0e-6)

        let paths = Dictionary(uniqueKeysWithValues: document.inputs.geometry.paths.map { ($0.id, $0) })
        guard let spec = strokeSpec(from: stroke, paths: paths, quality: "final") else {
            XCTFail("Failed to build stroke spec")
            return
        }

        let evaluator = DefaultParamEvaluator()
        let tProbe = 0.055
        guard let debug = evaluator.debugEvaluate(spec.width, at: tProbe) else {
            XCTFail("Missing width evaluation at t=\(tProbe)")
            return
        }
        XCTAssertFalse(debug.alphaWasNil)
        XCTAssertEqual(debug.alphaFromStart ?? 0.0, -2.85, accuracy: 1.0e-6)
        XCTAssertGreaterThan(debug.uBiased, debug.uRaw)
        let linear = debug.v0 + (debug.v1 - debug.v0) * debug.uRaw
        XCTAssertGreaterThan(abs(debug.value - linear), 1.0)

        let sampler = DefaultPathSampler()
        let useCase = GenerateStrokeOutlineUseCase(sampler: sampler, evaluator: evaluator, unioner: PassthroughPolygonUnioner())
        let skeletonPaths = stroke.skeletons.compactMap { paths[$0] }.compactMap(bezierPath(from:))
        let concatenated = useCase.generateConcatenatedSamplesWithJunctions(for: spec, paths: skeletonPaths)
        let t0 = 0.01
        let t1 = 0.1
        let tm = 0.055
        guard let sample0 = sample(at: t0, samples: concatenated.samples),
              let sample1 = sample(at: t1, samples: concatenated.samples),
              let sampleM = sample(at: tm, samples: concatenated.samples) else {
            XCTFail("Failed to sample rail points at window")
            return
        }
        let l0 = DirectSilhouetteTracer.leftRailPoint(sample: sample0)
        let l1 = DirectSilhouetteTracer.leftRailPoint(sample: sample1)
        let lm = DirectSilhouetteTracer.leftRailPoint(sample: sampleM)
        let linear = Point(x: ScalarMath.lerp(l0.x, l1.x, 0.5), y: ScalarMath.lerp(l0.y, l1.y, 0.5))
        let deviation = (lm - linear).length
        XCTAssertGreaterThan(deviation, max(0.25, 0.002 * 180.0))
    }

    private func sample(at t: Double, samples: [Sample]) -> Sample? {
        guard samples.count >= 2 else { return samples.first }
        if t <= samples[0].t { return samples[0] }
        if t >= samples[samples.count - 1].t { return samples[samples.count - 1] }
        for index in 0..<(samples.count - 1) {
            let a = samples[index]
            let b = samples[index + 1]
            if t >= a.t && t <= b.t {
                let span = b.t - a.t
                let fraction = span == 0 ? 0.0 : (t - a.t) / span
                return DirectSilhouetteTracer.interpolatedSample(a, b, fraction: fraction)
            }
        }
        return nil
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
        throw NSError(domain: "GlyphAlphaIntegrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixtures not found."])
    }
}
