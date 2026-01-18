import XCTest
import CoreGraphics
import Domain
@testable import CounterpointCLI

final class BumpLabelTests: XCTestCase {
    func testSVGLabelBumpEmitsMarker() throws {
        let glyphURL = try fixtureURL(pathComponents: ["Fixtures", "glyphs", "J.v0.json"])
        let data = try Data(contentsOf: glyphURL)
        let document = try GlyphDocument.load(from: data)

        var options = CLIOptions(
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
            verbose: false
        )
        options.labelBump = true
        options.labelBumpGT0 = 0.60
        options.labelBumpGT1 = 0.90
        options.labelBumpSide = .left

        let svg = try buildGlyphSVG(document: document, options: options, inputPath: glyphURL.path)
        XCTAssertTrue(svg.contains("BUMP"), "SVG should include bump label text.")
        XCTAssertTrue(svg.contains("debug-bump"), "SVG should include bump marker group.")
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
        throw NSError(domain: "BumpLabelTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found."])
    }
}
