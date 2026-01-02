import XCTest
import Domain
@testable import CounterpointCLI

final class ShowcaseTests: XCTestCase {
    private var runSlow: Bool {
        ProcessInfo.processInfo.environment["RUN_SLOW_TESTS"] == "1"
    }

    func testShowcaseRequiresOutputDirectory() {
        XCTAssertThrowsError(try parseShowcaseOptions([]))
    }

    func testShowcaseGoldenSVGs() throws {
        try XCTSkipUnless(runSlow, "Set RUN_SLOW_TESTS=1 to run showcase golden rendering.")
        for preset in ShowcasePresets.all {
            let expectedURL = try fixtureURL(pathComponents: ["Fixtures", "Showcase", "\(preset.name).svg"])
            let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            XCTAssertFalse(expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            let svg = try renderPresetSVG(preset, quality: "final")
            XCTAssertEqual(normalize(svg), normalize(expected), "Golden mismatch for \(preset.name)")
        }
    }

    func testShowcaseSmokePreview() throws {
        let overrides = [
            "--quality", "preview",
            "--samples", "120",
            "--envelope-sides", "24"
        ]
        for preset in ShowcasePresets.all {
            let svg = try renderPresetSVG(preset, quality: nil, overrides: overrides)
            XCTAssertFalse(svg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(svg.contains("<path fill=\"black\""))
        }
    }

    func testLineTrumpetAlphaBiasShiftsGrowth() throws {
        let baseArgs = [
            "--svg", "out.svg",
            "--view", "envelope,rails",
            "--envelope-mode", "rails",
            "--size-start", "5",
            "--size-end", "50",
            "--aspect-start", "0.35",
            "--aspect-end", "0.35",
            "--angle-start", "30",
            "--angle-end", "30"
        ]

        let neutralConfig = try parseScurveOptions(baseArgs + ["--alpha-end", "0.0"])
        let lateGrowthConfig = try parseScurveOptions(baseArgs + ["--alpha-end", "0.9"])
        let earlyGrowthConfig = try parseScurveOptions(baseArgs + ["--alpha-end", "-0.9"])

        let neutralGeom = try buildLineGeometry(config: neutralConfig)
        let lateGeom = try buildLineGeometry(config: lateGrowthConfig)
        let earlyGeom = try buildLineGeometry(config: earlyGrowthConfig)

        let neutralThickness = thickness(at: 0.9, geometry: neutralGeom)
        let lateThickness = thickness(at: 0.9, geometry: lateGeom)
        let earlyThickness = thickness(at: 0.9, geometry: earlyGeom)
        XCTAssertGreaterThan(lateThickness, neutralThickness)
        XCTAssertLessThan(earlyThickness, neutralThickness)
    }

    private func renderPresetSVG(_ preset: ShowcasePreset, quality: String?, overrides: [String] = []) throws -> String {
        var args = preset.args
        if !args.contains("--svg") {
            args.append(contentsOf: ["--svg", "out.svg"])
        }
        if let quality, !args.contains("--quality") {
            args.append(contentsOf: ["--quality", quality])
        }
        if !overrides.isEmpty {
            args.append(contentsOf: overrides)
        }

        let config = try parseScurveOptions(args)
        try validate(config: config)
        let geometry: ScurveGeometry
        switch preset.subcommand {
        case .scurve:
            geometry = try buildScurveGeometry(config: config)
        case .line:
            geometry = try buildLineGeometry(config: config)
        }

        let needsEnvelope = config.view.contains(.envelope)
        let fallbackToSamples = needsEnvelope && config.envelopeMode == .union && geometry.unionPolygons.isEmpty
        let polygons: PolygonSet
        if needsEnvelope {
            if config.envelopeMode == .union {
                polygons = geometry.unionPolygons.isEmpty
                    ? geometry.stampRings.map { Polygon(outer: $0) }
                    : geometry.unionPolygons
            } else {
                polygons = geometry.envelopeOutline.isEmpty ? [] : [Polygon(outer: geometry.envelopeOutline)]
            }
        } else {
            polygons = []
        }

        let fitTolerance = config.fitTolerance ?? defaultFitTolerance(polygons: polygons)
        let simplifyTolerance = config.simplifyTolerance ?? (fitTolerance * 1.5)
        var fittedPaths: [FittedPath]?
        var renderPolygons: PolygonSet
        switch config.outlineFit {
        case .none:
            fittedPaths = nil
            renderPolygons = polygons
        case .simplify:
            let fitter = BezierFitter(tolerance: fitTolerance)
            let simplified = polygons.map { polygon in
                let outer = fitter.simplifyRing(polygon.outer, closed: true)
                let holes = polygon.holes.map { fitter.simplifyRing($0, closed: true) }
                return Polygon(outer: outer, holes: holes)
            }
            fittedPaths = nil
            renderPolygons = simplified
        case .bezier:
            if config.envelopeMode == .union, !geometry.centerlineSamples.isEmpty {
                fittedPaths = fitUnionRails(
                    polygons,
                    centerlineSamples: geometry.centerlineSamples,
                    simplifyTolerance: simplifyTolerance,
                    fitTolerance: fitTolerance
                )
            } else {
                let simplifier = BezierFitter(tolerance: simplifyTolerance)
                let simplified = polygons.map { polygon in
                    let outer = simplifier.simplifyRing(polygon.outer, closed: true)
                    let holes = polygon.holes.map { simplifier.simplifyRing($0, closed: true) }
                    return Polygon(outer: outer, holes: holes)
                }
                let fitter = BezierFitter(tolerance: fitTolerance)
                fittedPaths = fitter.fitPolygonSet(simplified)
            }
            renderPolygons = []
        }

        if config.outlineFit == .bezier, let fitted = fittedPaths {
            if outlineHasSelfIntersection(fitted) {
                fittedPaths = nil
                renderPolygons = polygons
            }
        }

        let overlay = SVGDebugOverlay(
            skeleton: geometry.centerline,
            stamps: (config.view.contains(.samples) || fallbackToSamples) ? geometry.stampRings : [],
            bridges: [],
            samplePoints: geometry.samplePoints,
            tangentRays: geometry.tangentRays,
            angleRays: geometry.angleRays,
            offsetRays: geometry.offsetRays,
            envelopeLeft: config.view.contains(.rails) ? geometry.envelopeLeft : [],
            envelopeRight: config.view.contains(.rails) ? geometry.envelopeRight : [],
            envelopeOutline: config.view.contains(.envelope) ? geometry.envelopeOutline : [],
            showUnionOutline: config.view.contains(.union),
            unionPolygons: geometry.unionPolygons
        )

        return SVGPathBuilder().svgDocument(for: renderPolygons, fittedPaths: fittedPaths, size: config.svgSize, padding: config.padding, debugOverlay: overlay)
    }

    private func thickness(at s: Double, geometry: ScurveGeometry) -> Double {
        guard !geometry.sValues.isEmpty,
              geometry.envelopeLeft.count == geometry.envelopeRight.count,
              !geometry.envelopeLeft.isEmpty
        else { return 0.0 }
        let targetIndex = geometry.sValues.enumerated()
            .min { abs($0.element - s) < abs($1.element - s) }?.offset ?? 0
        if targetIndex >= geometry.envelopeLeft.count { return 0.0 }
        let left = geometry.envelopeLeft[targetIndex]
        let right = geometry.envelopeRight[targetIndex]
        return (left - right).length
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
        throw NSError(domain: "ShowcaseTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixtures not found."])
    }

    private func normalize(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = unified.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.map { $0.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression) }
        return trimmed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
