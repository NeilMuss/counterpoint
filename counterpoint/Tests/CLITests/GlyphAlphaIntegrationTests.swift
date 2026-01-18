import XCTest
@testable import CounterpointCLI
import Domain
@testable import UseCases
import Adapters

final class GlyphAlphaIntegrationTests: XCTestCase {
    func testGlyphFixtureAlphaPreservedAndAffectsEvaluation() throws {
        let document = GlyphDocument(
            schema: GlyphDocument.schemaId,
            engine: nil,
            glyph: nil,
            frame: GlyphFrame(
                origin: Point(x: 0, y: 0),
                size: GlyphSize(width: 400, height: 400),
                baselineY: 0,
                advanceWidth: 400,
                leftSidebearing: 20,
                rightSidebearing: 20,
                guides: nil
            ),
            inputs: GlyphInputs(
                geometry: GlyphGeometryInputs(
                    ink: [
                        .path(PathGeometry(
                            id: "path-stem",
                            segments: [
                                .cubic(CubicBezier(
                                    p0: Point(x: 0, y: 0),
                                    p1: Point(x: 0, y: 0),
                                    p2: Point(x: 0, y: 100),
                                    p3: Point(x: 0, y: 100)
                                ))
                            ]
                        )),
                        .stroke(StrokeGeometry(
                            id: "stroke-main",
                            skeletons: ["path-stem"],
                            params: StrokeParams(
                                angleMode: .absolute,
                                width: ParamCurve(keyframes: [
                                    ParamKeyframe(t: 0.0, value: 180.0),
                                    ParamKeyframe(t: 0.05, value: 180.0, interpolationToNext: Interpolation(alpha: -2.5)),
                                    ParamKeyframe(t: 0.16, value: 90.0),
                                    ParamKeyframe(t: 1.0, value: 90.0)
                                ]),
                                height: ParamCurve(keyframes: [ParamKeyframe(t: 0.0, value: 6.0), ParamKeyframe(t: 1.0, value: 6.0)]),
                                theta: ParamCurve(keyframes: [ParamKeyframe(t: 0.0, value: 0.0), ParamKeyframe(t: 1.0, value: 0.0)])
                            )
                        ))
                    ],
                    whitespace: []
                ),
                constraints: [],
                operations: []
            ),
            derived: nil
        )

        guard let stroke = document.inputs.geometry.strokes.first(where: { $0.id == "stroke-main" }) else {
            XCTFail("Missing stroke-main")
            return
        }
        guard let keyframe = stroke.params.width.keyframes.first(where: { abs($0.t - 0.05) < 1.0e-6 }) else {
            XCTFail("Missing width keyframe at t=0.05")
            return
        }
        XCTAssertNotNil(keyframe.interpolationToNext)
        XCTAssertEqual(keyframe.interpolationToNext?.alpha ?? 0.0, -2.5, accuracy: 1.0e-6)

        let paths: [String: PathGeometry] = Dictionary(uniqueKeysWithValues: document.inputs.geometry.paths.map { ($0.id, $0) })
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
        XCTAssertEqual(debug.alphaFromStart ?? 0.0, -2.5, accuracy: 1.0e-6)
        XCTAssertGreaterThan(debug.uBiased, debug.uRaw)
        let linearWidth = debug.v0 + (debug.v1 - debug.v0) * debug.uRaw
        XCTAssertGreaterThan(abs(debug.value - linearWidth), 1.0)

        let sampler = DefaultPathSampler()
        let useCase = GenerateStrokeOutlineUseCase(sampler: sampler, evaluator: evaluator, unioner: PassthroughPolygonUnioner())
        let skeletonPaths = stroke.skeletons.compactMap { paths[$0] }.compactMap(bezierPath(from:))
        let concatenated = useCase.generateConcatenatedSamplesWithJunctions(for: spec, paths: skeletonPaths)
        let t0 = 0.05
        let t1 = 0.16
        let tm = 0.105
        guard let sample0 = sample(at: t0, samples: concatenated.samples),
              let sample1 = sample(at: t1, samples: concatenated.samples),
              let sampleM = sample(at: tm, samples: concatenated.samples) else {
            XCTFail("Failed to sample rail points at window")
            return
        }
        let l0 = DirectSilhouetteTracer.leftRailPoint(sample: sample0)
        let l1 = DirectSilhouetteTracer.leftRailPoint(sample: sample1)
        let lm = DirectSilhouetteTracer.leftRailPoint(sample: sampleM)
        let linearRail = Point(x: ScalarMath.lerp(l0.x, l1.x, 0.5), y: ScalarMath.lerp(l0.y, l1.y, 0.5))
        let deviation = (lm - linearRail).length
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
}
