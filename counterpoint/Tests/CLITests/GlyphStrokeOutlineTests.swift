import XCTest
import CoreGraphics
import Domain
import UseCases
import Adapters
@testable import CounterpointCLI

final class GlyphStrokeOutlineTests: XCTestCase {
    func testGlyphStrokeFinalGolden() throws {
        let glyphURL = try fixtureURL(pathComponents: ["Fixtures", "glyphs", "J.v0.json"])
        let referenceURL = try fixtureURL(pathComponents: ["Fixtures", "references", "big_caslon_J.svg"])
        let expectedURL = try fixtureURL(pathComponents: ["Fixtures", "expected", "glyph_J_final.svg"])

        let data = try Data(contentsOf: glyphURL)
        let document = try GlyphDocument.load(from: data)

        let referenceRender: SVGPathBuilder.BackgroundGlyphRender?
        if let reference = document.derived?.reference,
           let source = SVGPathBuilder.loadBackgroundGlyph(from: referenceURL.path) {
            let bounds = source.viewBox ?? source.bounds
            let scale = reference.transform?.scale ?? 1.0
            let translate = reference.transform?.translate ?? Point(x: 0, y: 0)
            var manual = CGAffineTransform.identity
            manual = manual.scaledBy(x: scale, y: scale)
            manual = manual.translatedBy(x: translate.x, y: translate.y)
            referenceRender = SVGPathBuilder.BackgroundGlyphRender(
                elements: source.elements,
                bounds: bounds,
                fill: "#e0e0e0",
                stroke: "#4169e1",
                strokeWidth: 1.0,
                opacity: 1.0,
                zoom: 100.0,
                align: .none,
                manualTransform: manual
            )
        } else {
            referenceRender = nil
        }

        let frameBounds = glyphFrameBounds(document.frame, reference: referenceRender)

        let options = CLIOptions(
            inputPath: glyphURL.path,
            exampleName: nil,
            svgOutputPath: nil,
            svgSize: nil,
            padding: 10.0,
            quiet: true,
            useBridges: true,
            debugSamples: false,
            dumpSamplesPath: nil,
            quality: "preview",
            showEnvelope: nil,
            showEnvelopeUnion: false,
            showRays: nil,
            showAlpha: false,
            showJunctions: false,
            showRefDiff: false,
            showKeyframes: false,
            referenceOnTop: false,
            alphaProbeT: nil,
            counterpointSize: nil,
            angleModeOverride: nil,
            envelopeTolerance: nil,
            flattenTolerance: nil,
            maxSamples: nil,
            centerlineOnly: false,
            strokePreview: false,
            previewSamples: nil,
            previewQuality: nil,
            previewAngleMode: nil,
            previewAngleDeg: nil,
            previewWidth: nil,
            previewHeight: nil,
            previewNibRotateDeg: nil,
            previewUnionMode: .never,
            unionSimplifyTolerance: 0.75,
            unionMaxVertices: 5000,
            finalUnionMode: .auto,
            finalEnvelopeMode: nil,
            unionBatchSize: 50,
            unionAreaEps: 1.0e-6,
            unionWeldEps: 1.0e-5,
            unionEdgeEps: 1.0e-5,
            unionMinRingArea: 1.0,
            unionAutoTimeBudgetMs: nil,
            unionInputFilter: nil,
            unionSilhouetteK: nil,
            unionSilhouetteDropContained: nil,
            unionDumpInputPath: nil,
            outlineFit: OutlineFitMode.none,
            fitTolerance: nil,
            simplifyTolerance: nil,
            verbose: false,
            alphaDemo: nil,
            alphaDebug: false,
            traceStrokeId: nil,
            traceTMin: nil,
            traceTMax: nil,
            dumpKeyframes: false,
            diffResolution: nil
        )

        let authored = try buildAuthoredStrokePolygons(document: document, options: options)
        let builder = SVGPathBuilder()
        let svg = builder.svgDocumentForGlyphReference(
            frameBounds: frameBounds,
            size: nil,
            padding: options.padding,
            reference: referenceRender,
            centerlinePaths: [],
            polygons: authored.polygons,
            fittedPaths: authored.fittedPaths
        )

        let expected = try String(contentsOf: expectedURL, encoding: .utf8)
        XCTAssertFalse(expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Golden file is empty.")

        XCTAssertEqual(normalize(svg), normalize(expected), "Golden mismatch for glyph J final.")
    }

    func testGlyphDirectJunctionUsesBridge() throws {
        let glyphURL = try fixtureURL(pathComponents: ["Fixtures", "glyphs", "J.v0.json"])
        let data = try Data(contentsOf: glyphURL)
        let document = try GlyphDocument.load(from: data)

        let options = CLIOptions(
            inputPath: glyphURL.path,
            exampleName: nil,
            svgOutputPath: nil,
            svgSize: nil,
            padding: 10.0,
            quiet: true,
            useBridges: true,
            debugSamples: false,
            dumpSamplesPath: nil,
            quality: "final",
            showEnvelope: nil,
            showEnvelopeUnion: false,
            showRays: nil,
            showAlpha: false,
            showJunctions: false,
            showRefDiff: false,
            showKeyframes: false,
            referenceOnTop: false,
            alphaProbeT: nil,
            counterpointSize: nil,
            angleModeOverride: nil,
            envelopeTolerance: nil,
            flattenTolerance: nil,
            maxSamples: nil,
            centerlineOnly: false,
            strokePreview: false,
            previewSamples: nil,
            previewQuality: nil,
            previewAngleMode: nil,
            previewAngleDeg: nil,
            previewWidth: nil,
            previewHeight: nil,
            previewNibRotateDeg: nil,
            previewUnionMode: .never,
            unionSimplifyTolerance: 0.75,
            unionMaxVertices: 5000,
            finalUnionMode: .auto,
            finalEnvelopeMode: .direct,
            unionBatchSize: 50,
            unionAreaEps: 1.0e-6,
            unionWeldEps: 1.0e-5,
            unionEdgeEps: 1.0e-5,
            unionMinRingArea: 1.0,
            unionAutoTimeBudgetMs: nil,
            unionInputFilter: nil,
            unionSilhouetteK: nil,
            unionSilhouetteDropContained: nil,
            unionDumpInputPath: nil,
            outlineFit: OutlineFitMode.none,
            fitTolerance: nil,
            simplifyTolerance: nil,
            verbose: false,
            alphaDemo: nil,
            alphaDebug: false,
            traceStrokeId: nil,
            traceTMin: nil,
            traceTMax: nil,
            dumpKeyframes: false,
            diffResolution: nil
        )

        let authored = try buildAuthoredStrokePolygons(document: document, options: options)
        XCTAssertFalse(authored.junctionDiagnostics.isEmpty, "Expected junction diagnostics for direct envelope.")
        let fallbackCount = authored.junctionDiagnostics.filter { !$0.usedBridge }.count
        XCTAssertEqual(fallbackCount, 0, "Expected direct junctions to use tangent bridge, got \(fallbackCount) fallback(s).")
    }

    func testUnionSimplifyReducesVertices() throws {
        var ring: Ring = []
        for i in 0..<200 {
            ring.append(Point(x: Double(i), y: sin(Double(i) * 0.1)))
        }
        ring = closeRingIfNeeded(ring)
        let result = try simplifyRingsForUnion(
            [ring],
            baseTolerance: 0.5,
            maxVertices: 60,
            areaEps: 1.0e-6,
            minRingArea: 0.0,
            weldEps: 1.0e-5,
            edgeEps: 1.0e-5,
            inputFilter: .none,
            silhouetteK: 60,
            silhouetteDropContained: true
        )
        XCTAssertTrue(result.preCount > result.postCount)
        XCTAssertTrue(result.rings.first?.count ?? 0 <= 60)
    }

    func testGlyphThetaDegreesConvertedAndTangentRelativeApplied() throws {
        let path = PathGeometry(
            id: "ink:stem",
            segments: [
                .cubic(CubicBezier(
                    p0: Point(x: 0, y: 0),
                    p1: Point(x: 0, y: 0),
                    p2: Point(x: 0, y: 100),
                    p3: Point(x: 0, y: 100)
                ))
            ]
        )
        let paths = ["ink:stem": path]
        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )

        func assertEffectiveRotation(thetaDegrees: Double) throws {
            let stroke = StrokeGeometry(
                id: "stroke:test",
                skeletons: ["ink:stem"],
                params: StrokeParams(
                    angleMode: .tangentRelative,
                    width: ParamCurve(keyframes: [ParamKeyframe(t: 0, value: 10), ParamKeyframe(t: 1, value: 10)]),
                    height: ParamCurve(keyframes: [ParamKeyframe(t: 0, value: 5), ParamKeyframe(t: 1, value: 5)]),
                    theta: ParamCurve(keyframes: [ParamKeyframe(t: 0, value: thetaDegrees), ParamKeyframe(t: 1, value: thetaDegrees)])
                )
            )
            guard let spec = strokeSpec(from: stroke, paths: paths, quality: "preview") else {
                XCTFail("Failed to build StrokeSpec from glyph stroke.")
                return
            }
            let samples = useCase.generateSamples(for: spec)
            guard !samples.isEmpty else {
                XCTFail("No samples generated for glyph stroke.")
                return
            }
            let sample = samples[samples.count / 2]
            let thetaRad = thetaDegrees * .pi / 180.0
            let thetaInternal = AngleMath.wrapPi(thetaRad + (.pi / 2.0))
            let expected = AngleMath.wrapPi(sample.tangentAngle + thetaInternal)
            let delta = AngleMath.angularDifference(sample.effectiveRotation, expected)
            XCTAssertLessThan(abs(delta), 1.0e-4)
        }

        try assertEffectiveRotation(thetaDegrees: 0.0)
        try assertEffectiveRotation(thetaDegrees: 90.0)
    }

    private func glyphFrameBounds(_ frame: GlyphFrame, reference: SVGPathBuilder.BackgroundGlyphRender?) -> CGRect {
        if let size = frame.size {
            return CGRect(x: frame.origin.x, y: frame.origin.y, width: size.width, height: size.height)
        }
        if let reference {
            return reference.bounds
        }
        return CGRect(x: frame.origin.x, y: frame.origin.y, width: 1.0, height: 1.0)
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
        throw NSError(domain: "GlyphStrokeOutlineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found."])
    }

    private func normalize(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = unified.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.map { $0.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression) }
        let collapsed = trimmed.reduce(into: [String]()) { acc, line in
            if line.isEmpty, acc.last?.isEmpty == true { return }
            acc.append(line)
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
