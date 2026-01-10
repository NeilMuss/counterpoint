import Foundation
import CoreGraphics
import Domain
import UseCases
import Adapters

struct CLI {
    func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, first == "scurve" {
            try runScurve(args: Array(args.dropFirst()))
            return
        }
        if let first = args.first, first == "line" {
            try runLine(args: Array(args.dropFirst()))
            return
        }
        if let first = args.first, first == "showcase" {
            try runShowcase(args: Array(args.dropFirst()))
            return
        }
        if let first = args.first, first == "union-dump" {
            try runUnionDump(args: Array(args.dropFirst()))
            return
        }
        let options = try parseOptions(args)
        let inputData: Data

        if let exampleName = options.exampleName {
            let normalized = exampleName.isEmpty ? nil : exampleName
            do {
                if let data = try loadExampleFixture(named: normalized) {
                    inputData = data
                } else {
                    inputData = exampleSpecData(named: normalized)
                }
            } catch {
                throw CLIError.runtime("Failed to load example fixture: \(error.localizedDescription)")
            }
        } else if let path = options.inputPath, path != "-" {
            do {
                inputData = try Data(contentsOf: URL(fileURLWithPath: path))
            } catch {
                throw CLIError.invalidArguments("Failed to read input file at: \(path)")
            }
        } else {
            inputData = readStdin()
        }

        if inputData.isEmpty {
            throw CLIError.runtime("Input data is empty.")
        }

        DefaultParamEvaluator.enableAlphaMonotonicityCheck = options.verbose || options.alphaDebug
        DefaultParamEvaluator.alphaMonotonicityVerbose = options.verbose || options.alphaDebug

        let decoder = JSONDecoder()
        if let glyphDoc = try? decoder.decode(GlyphDocument.self, from: inputData),
           glyphDoc.schema == GlyphDocument.schemaId {
            if options.verbose || options.dumpKeyframes {
                dumpDecodedKeyframes(document: glyphDoc, options: options)
            }
            try GlyphDocumentValidator().validate(glyphDoc)
            try renderGlyphDocument(glyphDoc, options: options, inputPath: options.inputPath)
            return
        }
        var spec: StrokeSpec
        do {
            spec = try decoder.decode(StrokeSpec.self, from: inputData)
        } catch {
            let preview = String(data: inputData.prefix(80), encoding: .utf8) ?? "<non-utf8>"
            throw CLIError.runtime("Failed to decode StrokeSpec JSON (bytes=\(inputData.count)) preview=\(preview): \(error.localizedDescription)")
        }
        if let quality = options.quality {
            spec.samplingPolicy = (quality == "final") ? .final : .preview
        } else if spec.samplingPolicy == nil {
            spec.samplingPolicy = .preview
        }
        if let override = options.angleModeOverride {
            spec.angleMode = override
        }
        if options.envelopeTolerance != nil || options.flattenTolerance != nil || options.maxSamples != nil {
            let base = spec.samplingPolicy ?? SamplingPolicy.fromSamplingSpec(spec.sampling)
            let overridden = SamplingPolicy(
                flattenTolerance: options.flattenTolerance ?? base.flattenTolerance,
                envelopeTolerance: options.envelopeTolerance ?? base.envelopeTolerance,
                maxSamples: options.maxSamples ?? base.maxSamples,
                maxRecursionDepth: base.maxRecursionDepth,
                minParamStep: base.minParamStep
            )
            spec.samplingPolicy = overridden
        }
        if options.exampleName == "teardrop-demo" {
            if case .ellipse = spec.counterpointShape {
                let segments = (options.quality == "final") ? 64 : 24
                spec.counterpointShape = .ellipse(segments: segments)
            }
        }
        if options.exampleName == "global-angle-scurve" {
            if case .ellipse = spec.counterpointShape {
                let segments = (options.quality == "final") ? 64 : 24
                spec.counterpointShape = .ellipse(segments: segments)
            }
        }
        if options.exampleName == "global-angle-scurve", let cpSize = options.counterpointSize {
            let width = max(0.01, cpSize)
            let height = max(0.01, cpSize * 1.5)
            spec.width = ParamTrack.constant(width)
            spec.height = ParamTrack.constant(height)
        }
        try StrokeSpecValidator().validate(spec)

        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: IOverlayPolygonUnionAdapter()
        )
        if let dumpPath = options.dumpSamplesPath {
            GenerateStrokeOutlineUseCase.logSampleEvaluation = true
            let samples = useCase.generateSamples(for: spec)
            try dumpSamplesCSV(samples: samples, spec: spec, to: dumpPath)
        }
        let outline = try useCase.generateOutline(for: spec, includeBridges: options.useBridges)

        if let svgPath = options.svgOutputPath {
            let outputURL = URL(fileURLWithPath: svgPath)
            let outputDir = outputURL.deletingLastPathComponent()
            if !outputDir.path.isEmpty, outputDir.path != "." {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            }
            let builder = SVGPathBuilder()
            let debugOverlay = (options.debugSamples || options.showAlpha) ? makeDebugOverlay(spec: spec, options: options) : nil
            let backgroundGlyph: SVGPathBuilder.BackgroundGlyphRender?
            if let glyph = spec.backgroundGlyph {
                guard let source = SVGPathBuilder.loadBackgroundGlyph(from: glyph.svgPath) else {
                    throw CLIError.runtime("Failed to load background glyph SVG at: \(glyph.svgPath)")
                }
                backgroundGlyph = SVGPathBuilder.BackgroundGlyphRender(
                    elements: source.elements,
                    bounds: source.bounds,
                    fill: glyph.fill,
                    stroke: glyph.stroke,
                    strokeWidth: glyph.strokeWidth,
                    opacity: glyph.opacity,
                    zoom: glyph.zoom,
                    align: glyph.align,
                    manualTransform: SVGPathBuilder.parseTransformString(glyph.transform)
                )
            } else {
                backgroundGlyph = nil
            }
            let svg = builder.svgDocument(
                for: outline,
                size: options.svgSize,
                padding: options.padding,
                debugOverlay: debugOverlay,
                debugReference: spec.debugReference,
                backgroundGlyph: backgroundGlyph
            )
            do {
                try svg.write(to: outputURL, atomically: true, encoding: .utf8)
            } catch {
                throw CLIError.runtime("Failed to write SVG at: \(svgPath)")
            }
        }

        if !options.quiet {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let output = try encoder.encode(outline)

            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data([0x0A]))
        }
    }

    private func readStdin() -> Data {
        let stdin = FileHandle.standardInput
        return stdin.readDataToEndOfFile()
    }

    private func runScurve(args: [String]) throws {
        let config = try parseScurveOptions(args)
        try validate(config: config)

        let geometry = try buildScurveGeometry(config: config)
        try writeScurveOutput(config: config, geometry: geometry)
    }

    private func runLine(args: [String]) throws {
        let config = try parseScurveOptions(args)
        try validate(config: config)

        let geometry = try buildLineGeometry(config: config)
        try writeScurveOutput(config: config, geometry: geometry)
    }

    private func runShowcase(args: [String]) throws {
        let options = try parseShowcaseOptions(args)
        let outURL = URL(fileURLWithPath: options.outputDirectory)
        try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

        var rendered = 0
        for preset in ShowcasePresets.all {
            var presetArgs = preset.args
            if let quality = options.quality, !presetArgs.contains("--quality") {
                presetArgs.append(contentsOf: ["--quality", quality])
            }
            let outputPath = outURL.appendingPathComponent("\(preset.name).svg").path
            presetArgs.append(contentsOf: ["--svg", outputPath])

            switch preset.subcommand {
            case .scurve:
                try runScurve(args: presetArgs)
            case .line:
                try runLine(args: presetArgs)
            }
            rendered += 1
        }

        print("Rendered \(rendered) showcase SVGs to \(options.outputDirectory)")
    }

    private func runUnionDump(args: [String]) throws {
        let options = try parseUnionDumpOptions(args)
        let inputURL = URL(fileURLWithPath: options.inputPath)
        let data: Data
        do {
            data = try Data(contentsOf: inputURL)
        } catch {
            throw CLIError.invalidArguments("Failed to read input file at: \(options.inputPath)")
        }
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([[Point]].self, from: data)
        let originalRings: [Ring] = decoded.map { $0 }

        if let ringIndex = options.printRingOriginalIndex {
            guard ringIndex >= 0 && ringIndex < originalRings.count else {
                throw CLIError.invalidArguments("union-dump print-ring-original-index out of range (index=\(ringIndex), count=\(originalRings.count))")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let output = try encoder.encode(originalRings[ringIndex])
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data([0x0A]))
            if options.dryRun {
                return
            }
        }

        var selection = try computeUnionDumpSelection(rings: originalRings, options: options)
        let selectedOriginal = selection.keptOriginalIndices
        let snapTol = options.snapTol ?? 1.0e-3
        let touchEps = options.touchEps ?? ((options.snapTol ?? 0.0) > 0 ? (options.snapTol ?? 1.0e-3) * 0.5 : 1.0e-6)
        if options.cleanupCoincidentEdges {
            let indexed = selection.keptOriginalIndices.map { index in
                IndexedRing(index: index, ring: originalRings[index])
            }
            let cleanup = cleanupCoincidentEdges(
                rings: indexed,
                snapTol: snapTol,
                minRemainingCount: nil
            )
            selection = UnionDumpSelection(
                rings: cleanup.rings.map { $0.ring },
                keptOriginalIndices: cleanup.rings.map { $0.index },
                dropOriginalIndices: selection.dropOriginalIndices + cleanup.dropped.map { $0.index }
            )
            logCoincidentEdgeCleanup(label: "union-dump", result: cleanup)
        }
        if options.cleanupTouchingEdges {
            let indexed = selection.keptOriginalIndices.map { index in
                IndexedRing(index: index, ring: originalRings[index])
            }
            let cleanup = cleanupTouchingEdges(
                rings: indexed,
                epsilon: touchEps,
                minKeep: nil,
                maxDrops: nil,
                verbose: false
            )
            selection = UnionDumpSelection(
                rings: cleanup.rings.map { $0.ring },
                keptOriginalIndices: cleanup.rings.map { $0.index },
                dropOriginalIndices: selection.dropOriginalIndices + cleanup.dropped.map { $0.ring.index }
            )
            logTouchingCleanup(label: "union-dump", result: cleanup)
        }
        let stats = ringSummary(selection.rings)
        let keptList = selection.keptOriginalIndices.sorted().map(String.init).joined(separator: ",")
        let providedDrop = (options.dropOriginalIndices + options.dropIndices).sorted().map(String.init).joined(separator: ",")
        let finalSet = Set(selection.keptOriginalIndices)
        let cleanupDropped = selectedOriginal.filter { !finalSet.contains($0) }
        let allDropped = (options.dropOriginalIndices + options.dropIndices + cleanupDropped).sorted()
        let droppedList = allDropped.map(String.init).joined(separator: ",")
        if let dumpPath = options.dumpAfterCleanupPath {
            dumpUnionInputRings(selection.rings, to: dumpPath)
        }
        if options.dryRun {
            print("union-dump dry-run inputRings=\(originalRings.count) keepFirst=\(options.keepFirst.map(String.init) ?? "nil") dropOriginal=\(providedDrop.isEmpty ? "[]" : "[\(providedDrop)]") keptOriginal=\(keptList.isEmpty ? "[]" : "[\(keptList)]") finalRings=\(stats.ringCount) totalVerts=\(stats.totalVerts) maxRingVerts=\(stats.maxRingVerts)")
            return
        }
        if options.noUnion {
            let selectedList = selectedOriginal.sorted().map(String.init).joined(separator: ",")
            print("union-dump cleanup-only inputRings=\(originalRings.count) selectedOriginal=\(selectedList.isEmpty ? "[]" : "[\(selectedList)]") droppedOriginal=\(droppedList.isEmpty ? "[]" : "[\(droppedList)]") finalOriginal=\(keptList.isEmpty ? "[]" : "[\(keptList)]") finalRings=\(stats.ringCount) totalVerts=\(stats.totalVerts) maxRingVerts=\(stats.maxRingVerts)")
            return
        }
        if keptList.isEmpty {
            print("union-dump input rings=\(stats.ringCount) totalVerts=\(stats.totalVerts) maxRingVerts=\(stats.maxRingVerts) keptOriginal=[]")
        } else {
            print("union-dump input rings=\(stats.ringCount) totalVerts=\(stats.totalVerts) maxRingVerts=\(stats.maxRingVerts) keptOriginal=[\(keptList)]")
        }

        let unioner = IOverlayPolygonUnionAdapter()
        let unionResult = try unioner.union(subjectRings: selection.rings)

        if let outPath = options.outPath {
            let outputURL = URL(fileURLWithPath: outPath)
            let outputDir = outputURL.deletingLastPathComponent()
            if !outputDir.path.isEmpty, outputDir.path != "." {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let output = try encoder.encode(unionResult)
            try output.write(to: outputURL)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let output = try encoder.encode(unionResult)
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data([0x0A]))
        }

        if let svgPath = options.svgPath {
            let outputURL = URL(fileURLWithPath: svgPath)
            let outputDir = outputURL.deletingLastPathComponent()
            if !outputDir.path.isEmpty, outputDir.path != "." {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            }
            let svg = svgDocumentForUnionDump(
                inputRings: selection.rings,
                unionResult: unionResult,
                padding: 10.0
            )
            try svg.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }

    private func writeScurveOutput(config: ScurvePlaygroundConfig, geometry: ScurveGeometry) throws {
        if config.envelopeMode == .union {
            let vertexCount = geometry.unionPolygons.reduce(0) { sum, polygon in
                let holes = polygon.holes.reduce(0) { $0 + $1.count }
                return sum + polygon.outer.count + holes
            }
            print("union envelope: effectiveSampleCount \(geometry.sValues.count)")
            print("envelopeSides \(config.envelopeSegments)")
            print("union components \(geometry.unionPolygons.count) vertexCount \(vertexCount)")
            if config.verbose {
                print("max overlap ratio \(String(format: "%.3f", geometry.maxOverlapRatio))")
            }
            if geometry.unionPolygons.isEmpty {
                print("UNION FAILED/EMPTY, falling back to samples")
            }
        }

    let needsEnvelope = config.view.contains(.envelope)
    let preferRailsForJoin = config.envelopeMode == .union && config.joinStyle != .round
    let fallbackToSamples = needsEnvelope && config.envelopeMode == .union && geometry.unionPolygons.isEmpty
    let polygons: PolygonSet
    if needsEnvelope {
        if config.envelopeMode == .union && !preferRailsForJoin {
            polygons = geometry.unionPolygons.isEmpty
                ? geometry.stampRings.map { Polygon(outer: $0) }
                : geometry.unionPolygons
        } else if config.envelopeMode == .direct {
            var combined: PolygonSet = []
            if !geometry.envelopeOutline.isEmpty {
                combined.append(Polygon(outer: geometry.envelopeOutline))
            }
            combined.append(contentsOf: geometry.unionPolygons)
            polygons = combined
        } else {
            polygons = geometry.envelopeOutline.isEmpty ? [] : [Polygon(outer: geometry.envelopeOutline)]
        }
    } else {
        polygons = []
        }

        let fitTolerance = config.fitTolerance ?? defaultFitTolerance(polygons: polygons)
        let simplifyTolerance = config.simplifyTolerance ?? (fitTolerance * 1.5)
        let cornerThreshold = outlineCornerThresholdDegrees(for: config.joinStyle)
        var fittedPaths: [FittedPath]?
        var renderPolygons: PolygonSet
        switch config.outlineFit {
        case .none:
            fittedPaths = nil
            renderPolygons = polygons
        case .simplify:
            let fitter = BezierFitter(tolerance: fitTolerance, cornerThresholdDegrees: cornerThreshold)
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
                    fitTolerance: fitTolerance,
                    cornerThresholdDegrees: cornerThreshold
                )
            } else {
                let simplifier = BezierFitter(tolerance: simplifyTolerance, cornerThresholdDegrees: cornerThreshold)
                let simplified = polygons.map { polygon in
                    let outer = simplifier.simplifyRing(polygon.outer, closed: true)
                    let holes = polygon.holes.map { simplifier.simplifyRing($0, closed: true) }
                    return Polygon(outer: outer, holes: holes)
                }
                let fitter = BezierFitter(tolerance: fitTolerance, cornerThresholdDegrees: cornerThreshold)
                fittedPaths = fitter.fitPolygonSet(simplified)
            }
            renderPolygons = []
        }

        if config.envelopeMode == .direct, !geometry.envelopeOutline.isEmpty {
            if let directPath = catmullRomFittedPath(from: geometry.envelopeOutline) {
                fittedPaths = [directPath]
            }
        }

        if config.outlineFit == .bezier, config.envelopeMode != .direct, let fitted = fittedPaths {
            if outlineHasSelfIntersection(fitted) {
                if config.verbose {
                    print("warning: fitted outline self-intersects, falling back to raw envelope")
                }
                fittedPaths = nil
                renderPolygons = polygons
            }
        }

        let alphaChart: SVGPathBuilder.AlphaDebugChart?
        if config.view.contains(.alpha) {
            let width0 = config.widthStart ?? config.sizeStart
            let width1 = config.widthEnd ?? config.sizeEnd
            let widthTrack = ParamTrack(keyframes: [
                Keyframe(t: 0.0, value: width0, interpolationToNext: Interpolation(alpha: 0.0)),
                Keyframe(t: 1.0, value: width1)
            ])
            alphaChart = makeAlphaChart(track: widthTrack, tProbe: 0.5, trackLabel: "width", alphaOverride: nil)
        } else {
            alphaChart = nil
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
            capPoints: geometry.capPoints,
            junctionPatches: config.view.contains(.junctions) ? geometry.junctionPatches : [],
            junctionCorridors: config.view.contains(.junctions) ? geometry.junctionCorridors : [],
            junctionControlPoints: config.view.contains(.junctions) ? geometry.junctionControlPoints : [],
            showUnionOutline: config.view.contains(.union),
            unionPolygons: geometry.unionPolygons,
            alphaChart: alphaChart
        )

        let builder = SVGPathBuilder()
        let svg = builder.svgDocument(for: renderPolygons, fittedPaths: fittedPaths, size: config.svgSize, padding: config.padding, debugOverlay: overlay)
        try svg.write(to: URL(fileURLWithPath: config.svgOutputPath), atomically: true, encoding: .utf8)
    }

    private func exampleSpecData(named name: String?) -> Data {
        let normalized = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized?.lowercased() {
        case "global-angle-scurve", "global-angle":
            return Data(globalAngleExample.utf8)
        case "teardrop-demo", "teardrop":
            return Data(teardropDemoExample.utf8)
        case "alpha-terminal", "alpha":
            return Data(alphaTerminalExample.utf8)
        case "s-curve", "scurve", "s":
            return Data(sCurveExample.utf8)
        default:
            return Data(straightExample.utf8)
        }
    }

    private var straightExample: String {
        """
        {
          "path": {
            "segments": [
              {
                "p0": {"x": 0, "y": 0},
                "p1": {"x": 33, "y": 0},
                "p2": {"x": 66, "y": 0},
                "p3": {"x": 100, "y": 0}
              }
            ]
          },
          "width": {"keyframes": [{"t": 0, "value": 10}, {"t": 1, "value": 20}]},
          "height": {"keyframes": [{"t": 0, "value": 20}, {"t": 1, "value": 20}]},
          "theta": {"keyframes": [{"t": 0, "value": 0}, {"t": 1, "value": 0}]},
          "angleMode": "absolute",
          "sampling": {
            "baseSpacing": 4.0,
            "flatnessTolerance": 1.0,
            "rotationThresholdDegrees": 10.0,
            "minimumSpacing": 0.0001
          }
        }
        """
    }

    private var sCurveExample: String {
        """
        {
          "path": {
            "segments": [
              {
                "p0": {"x": 0, "y": 0},
                "p1": {"x": 25, "y": 60},
                "p2": {"x": 75, "y": -60},
                "p3": {"x": 100, "y": 0}
              }
            ]
          },
          "width": {"keyframes": [{"t": 0, "value": 12}, {"t": 1, "value": 18}]},
          "height": {"keyframes": [{"t": 0, "value": 16}, {"t": 1, "value": 16}]},
          "theta": {"keyframes": [{"t": 0, "value": 0.2}, {"t": 1, "value": 0.2}]},
          "angleMode": "tangentRelative",
          "sampling": {
            "baseSpacing": 2.0,
            "flatnessTolerance": 0.5,
            "rotationThresholdDegrees": 5.0,
            "minimumSpacing": 0.0001
          }
        }
        """
    }

    private var alphaTerminalExample: String {
        """
        {
          "path": {
            "segments": [
              {
                "p0": {"x": 0, "y": 0},
                "p1": {"x": 18, "y": 18},
                "p2": {"x": 42, "y": -10},
                "p3": {"x": 60, "y": 0}
              }
            ]
          },
          "width": {
            "keyframes": [
              {"t": 0.0, "value": 18},
              {"t": 0.88, "value": 18},
              {"t": 0.93, "value": 6, "interpolationToNext": {"alpha": 0.8}},
              {"t": 0.965, "value": 30, "interpolationToNext": {"alpha": 0.98}},
              {"t": 1.0, "value": 0.2}
            ]
          },
          "height": {
            "keyframes": [
              {"t": 0.0, "value": 28},
              {"t": 0.94, "value": 28, "interpolationToNext": {"alpha": 0.6}},
              {"t": 1.0, "value": 4.0, "interpolationToNext": {"alpha": 0.85}}
            ]
          },
          "theta": {"keyframes": [{"t": 0, "value": 0}, {"t": 1, "value": 0}]},
          "angleMode": "tangentRelative",
          "capStyle": "round",
          "joinStyle": "bevel",
          "sampling": {
            "baseSpacing": 6.0,
            "flatnessTolerance": 2.5,
            "rotationThresholdDegrees": 20.0,
            "minimumSpacing": 0.0001,
            "maxSamples": 80
          },
          "samplingPolicy": {
            "flattenTolerance": 2.5,
            "envelopeTolerance": 0.8,
            "maxSamples": 80,
            "maxRecursionDepth": 7,
            "minParamStep": 0.02
          }
        }
        """
    }

    private var teardropDemoExample: String {
        """
        {
          "path": {
            "segments": [
              {
                "p0": {"x": 0, "y": 0},
                "p1": {"x": 16, "y": 18},
                "p2": {"x": 44, "y": -12},
                "p3": {"x": 60, "y": 0}
              }
            ]
          },
          "width": {
            "keyframes": [
              {"t": 0.0, "value": 18},
              {"t": 0.88, "value": 18, "interpolationToNext": {"alpha": 0.8}},
              {"t": 0.93, "value": 6, "interpolationToNext": {"alpha": -0.6}},
              {"t": 0.965, "value": 30, "interpolationToNext": {"alpha": 0.98}},
              {"t": 1.0, "value": 0.2}
            ]
          },
          "height": {
            "keyframes": [
              {"t": 0.0, "value": 28},
              {"t": 0.94, "value": 28, "interpolationToNext": {"alpha": 0.85}},
              {"t": 1.0, "value": 4.0}
            ]
          },
          "theta": {"keyframes": [{"t": 0, "value": 0}, {"t": 1, "value": 0}]},
          "angleMode": "tangentRelative",
          "capStyle": "round",
          "joinStyle": "bevel",
          "counterpointShape": {"type": "ellipse", "segments": 24},
          "sampling": {
            "baseSpacing": 2.5,
            "flatnessTolerance": 1.5,
            "rotationThresholdDegrees": 8.0,
            "minimumSpacing": 0.0001,
            "maxSamples": 120
          },
          "samplingPolicy": {
            "flattenTolerance": 1.5,
            "envelopeTolerance": 2.0,
            "maxSamples": 80,
            "maxRecursionDepth": 7,
            "minParamStep": 0.01
          }
        }
        """
    }

    private var globalAngleExample: String {
        """
        {
          "path": {
            "segments": [
              {
                "p0": {"x": 0, "y": 0},
                "p1": {"x": 40, "y": 120},
                "p2": {"x": 60, "y": 120},
                "p3": {"x": 100, "y": 0}
              },
              {
                "p0": {"x": 100, "y": 0},
                "p1": {"x": 140, "y": -120},
                "p2": {"x": 160, "y": -120},
                "p3": {"x": 200, "y": 0}
              },
              {
                "p0": {"x": 200, "y": 0},
                "p1": {"x": 240, "y": 120},
                "p2": {"x": 260, "y": 120},
                "p3": {"x": 300, "y": 0}
              }
            ]
          },
          "width": {"keyframes": [{"t": 0, "value": 12.0}, {"t": 1, "value": 12.0}]},
          "height": {"keyframes": [{"t": 0, "value": 18.0}, {"t": 1, "value": 18.0}]},
          "theta": {"keyframes": [{"t": 0, "value": 0.1745329252}, {"t": 1, "value": 1.308996939}]},
          "angleMode": "absolute",
          "counterpointShape": {"type": "ellipse", "segments": 24},
          "sampling": {
            "baseSpacing": 3.0,
            "flatnessTolerance": 1.0,
            "rotationThresholdDegrees": 8.0,
            "minimumSpacing": 0.0001,
            "maxSamples": 140
          }
        }
        """
    }
}

private func loadExampleFixture(named name: String?) throws -> Data? {
    guard let name else { return nil }
    let cwd = FileManager.default.currentDirectoryPath
    let url = URL(fileURLWithPath: cwd)
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("specs")
        .appendingPathComponent("\(name).json")
    if FileManager.default.fileExists(atPath: url.path) {
        return try Data(contentsOf: url)
    }
    return nil
}

struct CLIOptions {
    var inputPath: String?
    var exampleName: String?
    var svgOutputPath: String?
    var svgSize: CGSize?
    var padding: Double
    var quiet: Bool
    var useBridges: Bool
    var debugSamples: Bool
    var dumpSamplesPath: String?
    var quality: String?
    var showEnvelope: Bool?
    var showEnvelopeUnion: Bool
    var showRays: Bool?
    var showAlpha: Bool
    var showJunctions: Bool
    var showRefDiff: Bool
    var alphaProbeT: Double?
    var counterpointSize: Double?
    var angleModeOverride: AngleMode?
    var envelopeTolerance: Double?
    var flattenTolerance: Double?
    var maxSamples: Int?
    var centerlineOnly: Bool
    var strokePreview: Bool
    var previewSamples: Int?
    var previewQuality: String?
    var previewAngleMode: AngleMode?
    var previewAngleDeg: Double?
    var previewWidth: Double?
    var previewHeight: Double?
    var previewNibRotateDeg: Double?
    var previewUnionMode: PreviewUnionMode?
    var unionSimplifyTolerance: Double?
    var unionMaxVertices: Int?
    var finalUnionMode: FinalUnionMode?
    var finalEnvelopeMode: FinalEnvelopeMode?
    var unionBatchSize: Int?
    var unionAreaEps: Double?
    var unionWeldEps: Double?
    var unionEdgeEps: Double?
    var unionMinRingArea: Double?
    var unionAutoTimeBudgetMs: Int?
    var unionInputFilter: UnionInputFilter?
    var unionSilhouetteK: Int?
    var unionSilhouetteDropContained: Bool?
    var unionDumpInputPath: String?
    var outlineFit: OutlineFitMode?
    var fitTolerance: Double?
    var simplifyTolerance: Double?
    var verbose: Bool
    var alphaDemo: Double?
    var alphaDebug: Bool
    var traceStrokeId: String?
    var traceTMin: Double?
    var traceTMax: Double?
    var dumpKeyframes: Bool
    var diffResolution: Int?
}

enum UnionInputFilter: String {
    case none
    case silhouette
}

private struct UnionDumpOptions {
    var inputPath: String
    var svgPath: String?
    var outPath: String?
    var dropIndices: [Int]
    var dropOriginalIndices: [Int]
    var keepFirst: Int?
    var keepIndices: [Int]
    var dryRun: Bool
    var printRingOriginalIndex: Int?
    var cleanupCoincidentEdges: Bool
    var snapTol: Double?
    var cleanupTouchingEdges: Bool
    var touchEps: Double?
    var noUnion: Bool
    var dumpAfterCleanupPath: String?
}

struct ScurvePlaygroundConfig: Equatable {
    var svgOutputPath: String
    var svgSize: CGSize?
    var padding: Double
    var angleStart: Double
    var angleEnd: Double
    var sizeStart: Double
    var sizeEnd: Double
    var aspectStart: Double
    var aspectEnd: Double
    var offsetStart: Double
    var offsetEnd: Double
    var widthStart: Double?
    var widthEnd: Double?
    var heightStart: Double?
    var heightEnd: Double?
    var alphaStart: Double
    var alphaEnd: Double
    var angleMode: AngleMode
    var samplesPerSegment: Int
    var maxSamples: Int
    var maxDepth: Int
    var tolerance: Double
    var isFinal: Bool
    var ellipseSegments: Int
    var envelopeSegments: Int
    var view: Set<ScurveView>
    var envelopeMode: EnvelopeMode
    var verbose: Bool
    var outlineFit: OutlineFitMode
    var fitTolerance: Double?
    var simplifyTolerance: Double?
    var joinStyle: JoinStyle
    var useKinkPath: Bool
    var dumpSamplesPath: String?
}

enum ScurveView: String {
    case envelope
    case samples
    case rays
    case rails
    case caps
    case junctions
    case union
    case centerline
    case offset
    case alpha
    case refDiff
}

enum EnvelopeMode: String {
    case rails
    case union
    case direct
}

enum PreviewUnionMode: String {
    case auto
    case never
    case always
}

enum FinalUnionMode: String {
    case auto
    case never
    case always
    case trace
}

enum FinalEnvelopeMode: String {
    case direct
}

struct ScurveGeometry {
    var envelopeLeft: [Point]
    var envelopeRight: [Point]
    var envelopeOutline: Ring
    var capPoints: [Point]
    var junctionPatches: [Ring]
    var junctionCorridors: [Ring]
    var junctionControlPoints: [Point]
    var unionPolygons: PolygonSet
    var stampRings: [Ring]
    var samplePoints: [Point]
    var tangentRays: [(Point, Point)]
    var angleRays: [(Point, Point)]
    var offsetRays: [(Point, Point)]
    var centerline: [Point]
    var sValues: [Double]
    var maxOverlapRatio: Double
    var centerlineSamples: [PathDomain.Sample]
}

struct ShowcaseOptions {
    var outputDirectory: String
    var quality: String?
}

private func parseOptions(_ args: [String]) throws -> CLIOptions {
    var options = CLIOptions(inputPath: nil, exampleName: nil, svgOutputPath: nil, svgSize: nil, padding: 10.0, quiet: false, useBridges: true, debugSamples: false, dumpSamplesPath: nil, quality: nil, showEnvelope: nil, showEnvelopeUnion: false, showRays: nil, showAlpha: false, showJunctions: false, showRefDiff: false, alphaProbeT: nil, counterpointSize: nil, angleModeOverride: nil, envelopeTolerance: nil, flattenTolerance: nil, maxSamples: nil, centerlineOnly: false, strokePreview: false, previewSamples: nil, previewQuality: nil, previewAngleMode: nil, previewAngleDeg: nil, previewWidth: nil, previewHeight: nil, previewNibRotateDeg: nil, previewUnionMode: nil, unionSimplifyTolerance: nil, unionMaxVertices: nil, finalUnionMode: nil, finalEnvelopeMode: nil, unionBatchSize: nil, unionAreaEps: nil, unionWeldEps: nil, unionEdgeEps: nil, unionMinRingArea: nil, unionAutoTimeBudgetMs: nil, unionInputFilter: nil, unionSilhouetteK: nil, unionSilhouetteDropContained: nil, unionDumpInputPath: nil, outlineFit: nil, fitTolerance: nil, simplifyTolerance: nil, verbose: false, alphaDemo: nil, alphaDebug: false, traceStrokeId: nil, traceTMin: nil, traceTMax: nil, dumpKeyframes: false, diffResolution: nil)
    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--example":
            let name = (index + 1 < args.count) ? args[index + 1] : nil
            if let name, !name.hasPrefix("--") {
                options.exampleName = name
                index += 1
            } else {
                options.exampleName = ""
            }
        case "--svg":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--svg requires an output path") }
            options.svgOutputPath = args[index + 1]
            index += 1
        case "--svg-size":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--svg-size requires WxH") }
            options.svgSize = try parseSize(args[index + 1])
            index += 1
        case "--padding":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--padding requires a number")
            }
            options.padding = value
            index += 1
        case "--quiet":
            options.quiet = true
        case "--verbose":
            options.verbose = true
        case "--bridges":
            options.useBridges = true
        case "--no-bridges":
            options.useBridges = false
        case "--debug-samples":
            options.debugSamples = true
        case "--debug-overlay":
            options.debugSamples = true
        case "--centerline-only":
            options.centerlineOnly = true
        case "--stroke-preview":
            options.strokePreview = true
        case "--preview-samples":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--preview-samples requires an integer")
            }
            options.previewSamples = value
            index += 1
        case "--preview-quality":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--preview-quality requires preview|final") }
            options.previewQuality = args[index + 1].lowercased()
            index += 1
        case "--preview-angle-mode":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--preview-angle-mode requires absolute|relative") }
            options.previewAngleMode = try parseAngleMode(args[index + 1])
            index += 1
        case "--preview-angle-deg":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--preview-angle-deg requires a number")
            }
            options.previewAngleDeg = value
            index += 1
        case "--preview-width":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--preview-width requires a number")
            }
            options.previewWidth = value
            index += 1
        case "--preview-height":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--preview-height requires a number")
            }
            options.previewHeight = value
            index += 1
        case "--preview-nib-rotate-deg":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--preview-nib-rotate-deg requires a number")
            }
            options.previewNibRotateDeg = value
            index += 1
        case "--preview-union":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--preview-union requires auto|never|always") }
            let mode = args[index + 1].lowercased()
            guard let parsed = PreviewUnionMode(rawValue: mode) else {
                throw CLIError.invalidArguments("--preview-union must be auto|never|always")
            }
            options.previewUnionMode = parsed
            index += 1
        case "--final-union":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--final-union requires auto|never|always|trace") }
            let mode = args[index + 1].lowercased()
            guard let parsed = FinalUnionMode(rawValue: mode) else {
                throw CLIError.invalidArguments("--final-union must be auto|never|always|trace")
            }
            options.finalUnionMode = parsed
            index += 1
        case "--final-envelope":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--final-envelope requires direct") }
            let mode = args[index + 1].lowercased()
            guard let parsed = FinalEnvelopeMode(rawValue: mode) else {
                throw CLIError.invalidArguments("--final-envelope must be direct")
            }
            options.finalEnvelopeMode = parsed
            index += 1
        case "--union-simplify-tol":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-simplify-tol requires a number")
            }
            options.unionSimplifyTolerance = value
            index += 1
        case "--union-max-verts":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-max-verts requires an integer")
            }
            options.unionMaxVertices = value
            index += 1
        case "--union-batch-size":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-batch-size requires an integer")
            }
            options.unionBatchSize = value
            index += 1
        case "--union-area-eps":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-area-eps requires a number")
            }
            options.unionAreaEps = value
            index += 1
        case "--union-weld-eps":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-weld-eps requires a number")
            }
            options.unionWeldEps = value
            index += 1
        case "--union-edge-eps":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-edge-eps requires a number")
            }
            options.unionEdgeEps = value
            index += 1
        case "--union-auto-time-budget-ms":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-auto-time-budget-ms requires an integer")
            }
            options.unionAutoTimeBudgetMs = value
            index += 1
        case "--union-input-filter":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--union-input-filter requires none|silhouette") }
            let mode = args[index + 1].lowercased()
            guard let parsed = UnionInputFilter(rawValue: mode) else {
                throw CLIError.invalidArguments("--union-input-filter must be none|silhouette")
            }
            options.unionInputFilter = parsed
            index += 1
        case "--union-silhouette-k":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-silhouette-k requires an integer")
            }
            options.unionSilhouetteK = value
            index += 1
        case "--union-silhouette-drop-contained":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-silhouette-drop-contained requires 0 or 1")
            }
            options.unionSilhouetteDropContained = value != 0
            index += 1
        case "--union-dump-input":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--union-dump-input requires a file path") }
            options.unionDumpInputPath = args[index + 1]
            index += 1
        case "--union-min-ring-area":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--union-min-ring-area requires a number")
            }
            options.unionMinRingArea = value
            index += 1
        case "--outline-fit":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--outline-fit requires none|simplify|bezier") }
            let mode = args[index + 1].lowercased()
            guard let parsed = OutlineFitMode(rawValue: mode) else {
                throw CLIError.invalidArguments("--outline-fit must be none|simplify|bezier")
            }
            options.outlineFit = parsed
            index += 1
        case "--fit-tolerance":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--fit-tolerance requires a number")
            }
            options.fitTolerance = value
            index += 1
        case "--simplify-tolerance":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--simplify-tolerance requires a number")
            }
            options.simplifyTolerance = value
            index += 1
        case "--dump-samples":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--dump-samples requires a file path") }
            options.dumpSamplesPath = args[index + 1]
            index += 1
        case "--show-envelope":
            options.showEnvelope = true
        case "--show-rays":
            options.showRays = true
        case "--no-rays":
            options.showRays = false
        case "--show-envelope-union":
            options.showEnvelopeUnion = true
        case "--cp-size":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--cp-size requires a number")
            }
            options.counterpointSize = value
            index += 1
        case "--angle-mode":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--angle-mode requires absolute|relative") }
            options.angleModeOverride = try parseAngleMode(args[index + 1])
            index += 1
        case "--quality":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--quality requires preview|final") }
            options.quality = args[index + 1].lowercased()
            index += 1
        case "--envelope-mode":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--envelope-mode requires rails|union") }
            let mode = args[index + 1].lowercased()
            guard EnvelopeMode(rawValue: mode) != nil else {
                throw CLIError.invalidArguments("--envelope-mode must be rails|union")
            }
            index += 1
        case "--view":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--view requires a value") }
            let viewModes = try parseViewModes(args[index + 1])
            if viewModes.isEmpty {
                options.debugSamples = false
                options.showEnvelope = false
                options.showRays = false
                options.showEnvelopeUnion = false
                options.showAlpha = false
                options.showJunctions = false
            } else {
                if viewModes.contains(.samples) { options.debugSamples = true }
                if viewModes.contains(.rays) { options.showRays = true }
                if viewModes.contains(.envelope) { options.showEnvelope = true }
                if viewModes.contains(.union) { options.showEnvelopeUnion = true }
                if viewModes.contains(.alpha) { options.showAlpha = true }
                if viewModes.contains(.junctions) { options.showJunctions = true }
                if viewModes.contains(.refDiff) { options.showRefDiff = true }
            }
            index += 1
        case "--alpha-probe-t":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--alpha-probe-t requires a number")
            }
            options.alphaProbeT = value
            options.showAlpha = true
            index += 1
        case "--diff-resolution":
            guard index + 1 < args.count, let value = Int(args[index + 1]), value > 0 else {
                throw CLIError.invalidArguments("--diff-resolution requires a positive integer")
            }
            options.diffResolution = value
            index += 1
        case "--alpha-demo":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--alpha-demo requires a number")
            }
            options.alphaDemo = value
            options.showAlpha = true
            index += 1
        case "--alpha-debug":
            options.alphaDebug = true
        case "--trace-alpha-window":
            guard index + 2 < args.count,
                  let tMin = Double(args[index + 1]),
                  let tMax = Double(args[index + 2]) else {
                throw CLIError.invalidArguments("--trace-alpha-window requires tmin tmax")
            }
            options.traceTMin = tMin
            options.traceTMax = tMax
            index += 2
        case "--trace-stroke":
            guard index + 1 < args.count else {
                throw CLIError.invalidArguments("--trace-stroke requires a stroke id")
            }
            options.traceStrokeId = args[index + 1]
            index += 1
        case "--trace-tmin":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--trace-tmin requires a number")
            }
            options.traceTMin = value
            index += 1
        case "--trace-tmax":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--trace-tmax requires a number")
            }
            options.traceTMax = value
            index += 1
        case "--dump-keyframes":
            options.dumpKeyframes = true
        case "--envelope-tol":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--envelope-tol requires a number")
            }
            options.envelopeTolerance = value
            index += 1
        case "--flatten-tol":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--flatten-tol requires a number")
            }
            options.flattenTolerance = value
            index += 1
        case "--max-samples":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--max-samples requires an integer")
            }
            options.maxSamples = value
            index += 1
        default:
            if !arg.hasPrefix("--") {
                options.inputPath = arg
            }
        }
        index += 1
    }

    return options
}

private func parseUnionDumpOptions(_ args: [String]) throws -> UnionDumpOptions {
    guard let inputPath = args.first, !inputPath.hasPrefix("--") else {
        throw CLIError.invalidArguments("union-dump requires an input JSON path")
    }
    var options = UnionDumpOptions(
        inputPath: inputPath,
        svgPath: nil,
        outPath: nil,
        dropIndices: [],
        dropOriginalIndices: [],
        keepFirst: nil,
        keepIndices: [],
        dryRun: false,
        printRingOriginalIndex: nil,
        cleanupCoincidentEdges: false,
        snapTol: nil,
        cleanupTouchingEdges: false,
        touchEps: nil,
        noUnion: false,
        dumpAfterCleanupPath: nil
    )
    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--svg":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--svg requires an output path") }
            options.svgPath = args[index + 1]
            index += 1
        case "--out":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--out requires an output path") }
            options.outPath = args[index + 1]
            index += 1
        case "--drop-index":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--drop-index requires an integer (0-based original index)")
            }
            options.dropIndices.append(value)
            index += 1
        case "--drop-original-index":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--drop-original-index requires an integer (0-based)")
            }
            options.dropOriginalIndices.append(value)
            index += 1
        case "--cleanup-coincident-edges":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--cleanup-coincident-edges requires 0 or 1")
            }
            options.cleanupCoincidentEdges = value != 0
            index += 1
        case "--cleanup-touching-edges":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--cleanup-touching-edges requires 0 or 1")
            }
            options.cleanupTouchingEdges = value != 0
            index += 1
        case "--snap-tol":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--snap-tol requires a number")
            }
            options.snapTol = value
            index += 1
        case "--touch-eps":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--touch-eps requires a number")
            }
            options.touchEps = value
            index += 1
        case "--keep-first":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--keep-first requires an integer")
            }
            options.keepFirst = value
            index += 1
        case "--keep-indices":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--keep-indices requires a list") }
            options.keepIndices = try parseIndexList(args[index + 1])
            index += 1
        case "--dry-run":
            options.dryRun = true
        case "--print-ring-original-index":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--print-ring-original-index requires an integer (0-based)")
            }
            options.printRingOriginalIndex = value
            index += 1
        case "--no-union":
            options.noUnion = true
        case "--cleanup-only":
            options.noUnion = true
        case "--dump-after-cleanup":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--dump-after-cleanup requires a path") }
            options.dumpAfterCleanupPath = args[index + 1]
            index += 1
        default:
            throw CLIError.invalidArguments("Unknown option for union-dump: \(arg)")
        }
        index += 1
    }
    return options
}

private func parseIndexList(_ value: String) throws -> [Int] {
    var result: [Int] = []
    let parts = value.split(separator: ",")
    for part in parts {
        let token = part.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { continue }
        if let dashIndex = token.firstIndex(of: "-") {
            let startString = token[..<dashIndex]
            let endString = token[token.index(after: dashIndex)...]
            guard let start = Int(startString), let end = Int(endString), start <= end else {
                throw CLIError.invalidArguments("--keep-indices has invalid range: \(token)")
            }
            result.append(contentsOf: start...end)
        } else {
            guard let value = Int(token) else {
                throw CLIError.invalidArguments("--keep-indices has invalid entry: \(token)")
            }
            result.append(value)
        }
    }
    return result
}

private struct UnionDumpSelection {
    let rings: [Ring]
    let keptOriginalIndices: [Int]
    let dropOriginalIndices: [Int]
}

private struct IndexedRing {
    let index: Int
    let ring: Ring
    let area: Double

    init(index: Int, ring: Ring) {
        self.index = index
        self.ring = ring
        self.area = abs(ringArea(ring))
    }
}

private struct CoincidentEdgeCleanupResult {
    let rings: [IndexedRing]
    let dropped: [IndexedRing]
    let coincidentEdgeCount: Int
    let involvedIndices: [Int]
}

private struct TouchingCleanupResult {
    let rings: [IndexedRing]
    let dropped: [(ring: IndexedRing, degree: Int)]
    let pairCount: Int
    let involvedIndices: [Int]
}

private struct QuantizedPoint: Hashable {
    let x: Int
    let y: Int
}

private struct EdgeKey: Hashable {
    let ax: Int
    let ay: Int
    let bx: Int
    let by: Int
}

private func computeUnionDumpSelection(rings: [Ring], options: UnionDumpOptions) throws -> UnionDumpSelection {
    let count = rings.count
    var keptIndices = Array(0..<count)

    if let keepFirst = options.keepFirst {
        if keepFirst <= 0 {
            keptIndices = []
        } else {
            keptIndices = Array(keptIndices.prefix(min(keepFirst, count)))
        }
    } else if !options.keepIndices.isEmpty {
        let keepSet = Set(options.keepIndices)
        if let maxIndex = keepSet.max(), maxIndex >= count {
            throw CLIError.invalidArguments("union-dump keep-indices out of range (max=\(maxIndex), count=\(count))")
        }
        keptIndices = keptIndices.filter { keepSet.contains($0) }
    }

    let dropOriginal = options.dropOriginalIndices + options.dropIndices
    if !dropOriginal.isEmpty {
        let dropSet = Set(dropOriginal)
        if let maxIndex = dropSet.max(), maxIndex >= count {
            throw CLIError.invalidArguments("union-dump drop-original-index out of range (max=\(maxIndex), count=\(count))")
        }
        keptIndices = keptIndices.filter { !dropSet.contains($0) }
    }

    let keptRings = keptIndices.map { rings[$0] }
    return UnionDumpSelection(rings: keptRings, keptOriginalIndices: keptIndices, dropOriginalIndices: dropOriginal)
}

private func cleanupCoincidentEdges(
    rings: [IndexedRing],
    snapTol: Double,
    minRemainingCount: Int?
) -> CoincidentEdgeCleanupResult {
    guard snapTol > 0, rings.count > 1 else {
        return CoincidentEdgeCleanupResult(rings: rings, dropped: [], coincidentEdgeCount: 0, involvedIndices: [])
    }
    var working = rings
    var dropped: [IndexedRing] = []
    var lastEdgeCount = 0
    var lastInvolved: [Int] = []

    while true {
        let edgeInfo = coincidentEdgeInfo(rings: working, snapTol: snapTol)
        lastEdgeCount = edgeInfo.edgeCount
        lastInvolved = Array(edgeInfo.involvedIndices).sorted()
        if edgeInfo.edgeCount == 0 || edgeInfo.involvedIndices.isEmpty {
            break
        }
        if let minRemainingCount, working.count <= minRemainingCount {
            break
        }
        let candidate = working
            .filter { edgeInfo.involvedIndices.contains($0.index) }
            .min {
                if abs($0.area - $1.area) > 1.0e-9 {
                    return $0.area < $1.area
                }
                return $0.index < $1.index
            }
        guard let toDrop = candidate else { break }
        working.removeAll { $0.index == toDrop.index }
        dropped.append(toDrop)
    }

    return CoincidentEdgeCleanupResult(
        rings: working,
        dropped: dropped,
        coincidentEdgeCount: lastEdgeCount,
        involvedIndices: lastInvolved
    )
}

private func cleanupTouchingEdges(
    rings: [IndexedRing],
    epsilon: Double,
    minKeep: Int?,
    maxDrops: Int?,
    verbose: Bool
) -> TouchingCleanupResult {
    print("cleanup-touching start rings=\(rings.count)")
    guard epsilon > 0, rings.count > 1 else {
        return TouchingCleanupResult(rings: rings, dropped: [], pairCount: 0, involvedIndices: [])
    }
    var working = rings
    var dropped: [(ring: IndexedRing, degree: Int)] = []
    var lastPairCount = 0
    var lastInvolved: [Int] = []
    let maxDropLimit = maxDrops ?? rings.count

    while true {
        if dropped.count >= maxDropLimit {
            break
        }
        let touchInfo = touchingPairs(rings: working, epsilon: epsilon)
        print("cleanup-touching computedPairs=\(touchInfo.pairCount)")
        lastPairCount = touchInfo.pairCount
        lastInvolved = Array(touchInfo.involvedIndices).sorted()
        if touchInfo.pairCount == 0 || touchInfo.involvedIndices.isEmpty {
            break
        }
        if let minKeep, working.count <= minKeep {
            break
        }
        guard let candidate = selectTouchDropCandidate(rings: working, degrees: touchInfo.degrees) else {
            break
        }
        if verbose {
            print("cleanup-touching drop idx=\(candidate.ring.index) degree=\(candidate.degree) area=\(String(format: "%.4f", candidate.ring.area)) remaining=\(max(0, working.count - 1)) pairs=\(touchInfo.pairCount)")
        }
        working.removeAll { $0.index == candidate.ring.index }
        dropped.append(candidate)
    }

    return TouchingCleanupResult(
        rings: working,
        dropped: dropped,
        pairCount: lastPairCount,
        involvedIndices: lastInvolved
    )
}

private func touchingPairs(
    rings: [IndexedRing],
    epsilon: Double
) -> (pairCount: Int, involvedIndices: Set<Int>, degrees: [Int: Int]) {
    var pairCount = 0
    var involved: Set<Int> = []
    var degrees: [Int: Int] = [:]
    for i in 0..<rings.count {
        let a = rings[i]
        for j in (i + 1)..<rings.count {
            let b = rings[j]
            if ringsTouch(a.ring, b.ring, epsilon: epsilon) {
                pairCount += 1
                involved.insert(a.index)
                involved.insert(b.index)
                degrees[a.index, default: 0] += 1
                degrees[b.index, default: 0] += 1
            }
        }
    }
    return (pairCount, involved, degrees)
}

private func selectTouchDropCandidate(
    rings: [IndexedRing],
    degrees: [Int: Int]
) -> (ring: IndexedRing, degree: Int)? {
    var best: (ring: IndexedRing, degree: Int)?
    for ring in rings {
        guard let degree = degrees[ring.index], degree > 0 else { continue }
        if let current = best {
            if degree > current.degree {
                best = (ring, degree)
            } else if degree == current.degree {
                if abs(ring.area - current.ring.area) > 1.0e-9 {
                    if ring.area < current.ring.area {
                        best = (ring, degree)
                    }
                } else if ring.index < current.ring.index {
                    best = (ring, degree)
                }
            }
        } else {
            best = (ring, degree)
        }
    }
    return best
}

private func ringsTouch(_ a: Ring, _ b: Ring, epsilon: Double) -> Bool {
    guard a.count > 1, b.count > 1 else { return false }
    for point in a {
        if pointOnRing(point, ring: b, epsilon: epsilon) { return true }
    }
    for point in b {
        if pointOnRing(point, ring: a, epsilon: epsilon) { return true }
    }
    let aCount = a.count
    let bCount = b.count
    for i in 0..<aCount {
        let a1 = a[i]
        let a2 = a[(i + 1) % aCount]
        for j in 0..<bCount {
            let b1 = b[j]
            let b2 = b[(j + 1) % bCount]
            if segmentsTouch(a1, a2, b1, b2, epsilon: epsilon) {
                return true
            }
        }
    }
    return false
}

private func pointOnRing(_ point: Point, ring: Ring, epsilon: Double) -> Bool {
    guard ring.count > 1 else { return false }
    for i in 0..<ring.count {
        let a = ring[i]
        let b = ring[(i + 1) % ring.count]
        if pointToSegmentDistanceSquared(point, a, b) <= epsilon * epsilon {
            return true
        }
    }
    return false
}

private func segmentsTouch(_ p1: Point, _ p2: Point, _ q1: Point, _ q2: Point, epsilon: Double) -> Bool {
    if segmentsIntersectInclusive(p1, p2, q1, q2, epsilon: epsilon) {
        return true
    }
    if pointToSegmentDistanceSquared(p1, q1, q2) <= epsilon * epsilon { return true }
    if pointToSegmentDistanceSquared(p2, q1, q2) <= epsilon * epsilon { return true }
    if pointToSegmentDistanceSquared(q1, p1, p2) <= epsilon * epsilon { return true }
    if pointToSegmentDistanceSquared(q2, p1, p2) <= epsilon * epsilon { return true }
    return false
}

private func segmentsIntersectInclusive(_ p1: Point, _ p2: Point, _ q1: Point, _ q2: Point, epsilon: Double) -> Bool {
    func orientation(_ a: Point, _ b: Point, _ c: Point) -> Double {
        (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
    }
    func onSegment(_ a: Point, _ b: Point, _ c: Point) -> Bool {
        min(a.x, c.x) - epsilon <= b.x && b.x <= max(a.x, c.x) + epsilon &&
        min(a.y, c.y) - epsilon <= b.y && b.y <= max(a.y, c.y) + epsilon &&
        abs(pointToSegmentDistanceSquared(b, a, c)) <= epsilon * epsilon
    }

    let o1 = orientation(p1, p2, q1)
    let o2 = orientation(p1, p2, q2)
    let o3 = orientation(q1, q2, p1)
    let o4 = orientation(q1, q2, p2)

    if (o1 * o2 < 0) && (o3 * o4 < 0) {
        return true
    }
    if abs(o1) <= epsilon && onSegment(p1, q1, p2) { return true }
    if abs(o2) <= epsilon && onSegment(p1, q2, p2) { return true }
    if abs(o3) <= epsilon && onSegment(q1, p1, q2) { return true }
    if abs(o4) <= epsilon && onSegment(q1, p2, q2) { return true }
    return false
}

private func pointToSegmentDistanceSquared(_ p: Point, _ a: Point, _ b: Point) -> Double {
    let ab = b - a
    let ap = p - a
    let abLen2 = ab.dot(ab)
    if abLen2 <= 0 { return ap.dot(ap) }
    let t = max(0.0, min(1.0, ap.dot(ab) / abLen2))
    let proj = Point(x: a.x + ab.x * t, y: a.y + ab.y * t)
    let delta = p - proj
    return delta.dot(delta)
}

private func coincidentEdgeInfo(
    rings: [IndexedRing],
    snapTol: Double
) -> (edgeCount: Int, involvedIndices: Set<Int>) {
    var edgeMap: [EdgeKey: Set<Int>] = [:]
    edgeMap.reserveCapacity(rings.count * 4)
    for ring in rings {
        let points = ring.ring
        guard points.count >= 2 else { continue }
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let qa = quantizePoint(a, snapTol: snapTol)
            let qb = quantizePoint(b, snapTol: snapTol)
            if qa == qb { continue }
            let key = edgeKey(qa, qb)
            edgeMap[key, default: []].insert(ring.index)
        }
    }
    var involved: Set<Int> = []
    var coincidentEdges = 0
    for entry in edgeMap.values {
        if entry.count >= 2 {
            coincidentEdges += 1
            involved.formUnion(entry)
        }
    }
    return (coincidentEdges, involved)
}

private func quantizePoint(_ point: Point, snapTol: Double) -> QuantizedPoint {
    QuantizedPoint(
        x: Int((point.x / snapTol).rounded()),
        y: Int((point.y / snapTol).rounded())
    )
}

private func edgeKey(_ a: QuantizedPoint, _ b: QuantizedPoint) -> EdgeKey {
    if a.x < b.x || (a.x == b.x && a.y <= b.y) {
        return EdgeKey(ax: a.x, ay: a.y, bx: b.x, by: b.y)
    }
    return EdgeKey(ax: b.x, ay: b.y, bx: a.x, by: a.y)
}

private func logCoincidentEdgeCleanup(label: String, result: CoincidentEdgeCleanupResult) {
    if result.coincidentEdgeCount == 0 {
        print("cleanup-coincident-edges foundEdges=0 involvedRings=[]")
        return
    }
    let involved = result.involvedIndices.map(String.init).joined(separator: ",")
    let dropped = result.dropped.map { "\($0.index):\(String(format: "%.4f", $0.area))" }.joined(separator: ",")
    print("cleanup-coincident-edges foundEdges=\(result.coincidentEdgeCount) involvedRings=[\(involved)]")
    if dropped.isEmpty {
        print("cleanup-coincident-edges dropped=[] remaining=\(result.rings.count)")
    } else {
        print("cleanup-coincident-edges dropped=[\(dropped)] remaining=\(result.rings.count)")
    }
}

private func logTouchingCleanup(label: String, result: TouchingCleanupResult) {
    if result.pairCount == 0 {
        print("cleanup-touching foundPairs=0 involvedRings=[]")
        return
    }
    let involved = result.involvedIndices.map(String.init).joined(separator: ",")
    print("cleanup-touching foundPairs=\(result.pairCount) involvedRings=[\(involved)]")
    let dropped = result.dropped.map { "\($0.ring.index):\(String(format: "%.4f", $0.ring.area)):\($0.degree)" }.joined(separator: ",")
    print("cleanup-touching dropped=\(dropped.isEmpty ? "[]" : "[\(dropped)]") remaining=\(result.rings.count) pairs=\(result.pairCount)")
}

private struct RingSummary {
    let ringCount: Int
    let totalVerts: Int
    let maxRingVerts: Int
}

private func ringSummary(_ rings: [Ring]) -> RingSummary {
    var total = 0
    var maxVerts = 0
    for ring in rings {
        total += ring.count
        maxVerts = max(maxVerts, ring.count)
    }
    return RingSummary(ringCount: rings.count, totalVerts: total, maxRingVerts: maxVerts)
}

private func svgDocumentForUnionDump(inputRings: [Ring], unionResult: PolygonSet, padding: Double) -> String {
    let inputPaths = inputRings.map { ringStrokePath($0, stroke: "#444", strokeWidth: 1.0) }.joined(separator: "\n  ")
    let unionPaths = unionResult.map { polygonPath($0, fill: "#111", fillOpacity: 0.2) }.joined(separator: "\n  ")
    let bounds = unionBounds(boundsForRings(inputRings), boundsForPolygons(unionResult)) ?? CGRect(x: 0, y: 0, width: 100, height: 100)
    let padded = bounds.insetBy(dx: -padding, dy: -padding)
    let viewBox = "\(formatSVGNumber(padded.minX)) \(formatSVGNumber(padded.minY)) \(formatSVGNumber(padded.width)) \(formatSVGNumber(padded.height))"
    let width = formatSVGNumber(padded.width)
    let height = formatSVGNumber(padded.height)
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="\(viewBox)">
      \(unionPaths)
      \(inputPaths)
    </svg>
    """
}

private func ringStrokePath(_ ring: Ring, stroke: String, strokeWidth: Double) -> String {
    let d = ringPathData(ring)
    guard !d.isEmpty else { return "" }
    return "<path fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(formatSVGNumber(strokeWidth))\" stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"\(d)\"/>"
}

private func polygonPath(_ polygon: Polygon, fill: String, fillOpacity: Double) -> String {
    let outer = ringPathData(polygon.outer)
    let holes = polygon.holes.map { ringPathData($0) }.joined(separator: " ")
    let d = holes.isEmpty ? outer : "\(outer) \(holes)"
    guard !d.isEmpty else { return "" }
    return "<path fill=\"\(fill)\" fill-opacity=\"\(formatSVGNumber(fillOpacity))\" stroke=\"none\" fill-rule=\"evenodd\" d=\"\(d)\"/>"
}

private func ringPathData(_ ring: Ring) -> String {
    guard let first = ring.first else { return "" }
    var parts: [String] = []
    parts.reserveCapacity(ring.count + 2)
    parts.append("M \(formatSVGNumber(first.x)) \(formatSVGNumber(first.y))")
    for point in ring.dropFirst() {
        parts.append("L \(formatSVGNumber(point.x)) \(formatSVGNumber(point.y))")
    }
    parts.append("Z")
    return parts.joined(separator: " ")
}

private func formatSVGNumber(_ value: Double, precision: Int = 4) -> String {
    let factor = pow(10.0, Double(precision))
    let rounded = (value * factor).rounded() / factor
    if rounded == -0.0 { return "0" }
    return String(format: "%0.*f", precision, rounded)
}

private func boundsForRings(_ rings: [Ring]) -> CGRect? {
    var bounds: CGRect?
    for ring in rings {
        let ringBounds = ringBounds(ring)
        if ringBounds.isNull { continue }
        bounds = bounds?.union(ringBounds) ?? ringBounds
    }
    return bounds
}

private func boundsForPolygons(_ polygons: PolygonSet) -> CGRect? {
    var bounds: CGRect?
    for polygon in polygons {
        let outerBounds = ringBounds(polygon.outer)
        if !outerBounds.isNull {
            bounds = bounds?.union(outerBounds) ?? outerBounds
        }
        for hole in polygon.holes {
            let holeBounds = ringBounds(hole)
            if !holeBounds.isNull {
                bounds = bounds?.union(holeBounds) ?? holeBounds
            }
        }
    }
    return bounds
}

private func unionBounds(_ lhs: CGRect?, _ rhs: CGRect?) -> CGRect? {
    switch (lhs, rhs) {
    case (nil, nil):
        return nil
    case let (value?, nil), let (nil, value?):
        return value
    case let (left?, right?):
        return left.union(right)
    }
}

func parseScurveOptions(_ args: [String]) throws -> ScurvePlaygroundConfig {
    var svgOutputPath: String?
    var svgSize: CGSize?
    var padding: Double = 10.0
    var angleStart = 10.0
    var angleEnd = 75.0
    var sizeStart = 12.0
    var sizeEnd = 12.0
    var aspectStart = 1.5
    var aspectEnd = 1.5
    var offsetStart = 0.0
    var offsetEnd = 0.0
    var widthStart: Double?
    var widthEnd: Double?
    var heightStart: Double?
    var heightEnd: Double?
    var alphaStart = 0.0
    var alphaEnd = 0.0
    var angleMode: AngleMode = .absolute
    var maxSamples: Int?
    var quality: String?
    var view: Set<ScurveView> = [.envelope, .centerline]
    var envelopeMode: EnvelopeMode = .union
    var envelopeSegments: Int = 48
    var verbose = false
    var outlineFit: OutlineFitMode?
    var fitTolerance: Double?
    var simplifyTolerance: Double?
    var joinStyleName = "round"
    var miterLimit: Double = 4.0
    var useKinkPath = false
    var dumpSamplesPath: String?

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--svg":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--svg requires an output path") }
            svgOutputPath = args[index + 1]
            index += 1
        case "--svg-size":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--svg-size requires WxH") }
            svgSize = try parseSize(args[index + 1])
            index += 1
        case "--padding":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--padding requires a number")
            }
            padding = value
            index += 1
        case "--angle-start":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--angle-start requires a number")
            }
            angleStart = value
            index += 1
        case "--angle-end":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--angle-end requires a number")
            }
            angleEnd = value
            index += 1
        case "--size-start":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--size-start requires a number")
            }
            sizeStart = value
            index += 1
        case "--size-end":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--size-end requires a number")
            }
            sizeEnd = value
            index += 1
        case "--aspect-start":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--aspect-start requires a number")
            }
            aspectStart = value
            index += 1
        case "--aspect-end":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--aspect-end requires a number")
            }
            aspectEnd = value
            index += 1
        case "--offset-start":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--offset-start requires a number")
            }
            offsetStart = value
            index += 1
        case "--offset-end":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--offset-end requires a number")
            }
            offsetEnd = value
            index += 1
        case "--width-start":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--width-start requires a number")
            }
            widthStart = value
            index += 1
        case "--width-end":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--width-end requires a number")
            }
            widthEnd = value
            index += 1
        case "--height-start":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--height-start requires a number")
            }
            heightStart = value
            index += 1
        case "--height-end":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--height-end requires a number")
            }
            heightEnd = value
            index += 1
        case "--alpha-start":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--alpha-start requires a number")
            }
            alphaStart = value
            index += 1
        case "--alpha-end":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--alpha-end requires a number")
            }
            alphaEnd = value
            index += 1
        case "--angle-mode":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--angle-mode requires absolute|relative") }
            angleMode = try parseAngleMode(args[index + 1])
            index += 1
        case "--samples":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--samples requires an integer")
            }
            maxSamples = max(4, value)
            index += 1
        case "--quality":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--quality requires preview|final") }
            quality = args[index + 1].lowercased()
            index += 1
        case "--view":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--view requires a value") }
            view = try parseViewModes(args[index + 1])
            index += 1
        case "--envelope-mode":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--envelope-mode requires rails|union|direct") }
            let mode = args[index + 1].lowercased()
            guard let parsed = EnvelopeMode(rawValue: mode) else {
                throw CLIError.invalidArguments("--envelope-mode must be rails|union|direct")
            }
            envelopeMode = parsed
            index += 1
        case "--envelope-sides":
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw CLIError.invalidArguments("--envelope-sides requires an integer")
            }
            envelopeSegments = max(8, value)
            index += 1
        case "--no-centerline":
            view.remove(.centerline)
        case "--verbose":
            verbose = true
        case "--outline-fit":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--outline-fit requires none|simplify|bezier") }
            let mode = args[index + 1].lowercased()
            guard let parsed = OutlineFitMode(rawValue: mode) else {
                throw CLIError.invalidArguments("--outline-fit must be none|simplify|bezier")
            }
            outlineFit = parsed
            index += 1
        case "--join":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--join requires round|bevel|miter") }
            let mode = args[index + 1].lowercased()
            guard ["round", "bevel", "miter"].contains(mode) else {
                throw CLIError.invalidArguments("--join must be round|bevel|miter")
            }
            joinStyleName = mode
            index += 1
        case "--miter-limit":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--miter-limit requires a number")
            }
            miterLimit = value
            index += 1
        case "--kink":
            useKinkPath = true
        case "--fit-tolerance":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--fit-tolerance requires a number")
            }
            fitTolerance = value
            index += 1
        case "--simplify-tolerance":
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw CLIError.invalidArguments("--simplify-tolerance requires a number")
            }
            simplifyTolerance = value
            index += 1
        case "--dump-samples":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--dump-samples requires a file path") }
            dumpSamplesPath = args[index + 1]
            index += 1
        default:
            break
        }
        index += 1
    }

    let resolvedSamples: Int
    let resolvedMaxSamples: Int
    let resolvedMaxDepth: Int
    let resolvedTolerance: Double
    let isFinal: Bool
    let ellipseSegments: Int
    if quality == "final" {
        resolvedSamples = 200
        ellipseSegments = 64
        resolvedMaxSamples = maxSamples ?? 800
        resolvedMaxDepth = 14
        resolvedTolerance = 0.0
        isFinal = true
    } else {
        resolvedSamples = 80
        ellipseSegments = 24
        resolvedMaxSamples = maxSamples ?? 200
        resolvedMaxDepth = 10
        resolvedTolerance = 0.0
        isFinal = false
    }

    guard let svgOutputPath else {
        throw CLIError.invalidArguments("scurve requires --svg <outputPath>")
    }

    let resolvedOutlineFit: OutlineFitMode
    if let outlineFit {
        resolvedOutlineFit = outlineFit
    } else {
        resolvedOutlineFit = isFinal ? .bezier : .none
    }

    let joinStyle: JoinStyle
    switch joinStyleName {
    case "bevel":
        joinStyle = .bevel
    case "miter":
        joinStyle = .miter(miterLimit: miterLimit)
    default:
        joinStyle = .round
    }

    return ScurvePlaygroundConfig(
        svgOutputPath: svgOutputPath,
        svgSize: svgSize,
        padding: padding,
        angleStart: angleStart,
        angleEnd: angleEnd,
        sizeStart: sizeStart,
        sizeEnd: sizeEnd,
        aspectStart: aspectStart,
        aspectEnd: aspectEnd,
        offsetStart: offsetStart,
        offsetEnd: offsetEnd,
        widthStart: widthStart,
        widthEnd: widthEnd,
        heightStart: heightStart,
        heightEnd: heightEnd,
        alphaStart: alphaStart,
        alphaEnd: alphaEnd,
        angleMode: angleMode,
        samplesPerSegment: resolvedSamples,
        maxSamples: resolvedMaxSamples,
        maxDepth: resolvedMaxDepth,
        tolerance: resolvedTolerance,
        isFinal: isFinal,
        ellipseSegments: ellipseSegments,
        envelopeSegments: envelopeSegments,
        view: view,
        envelopeMode: envelopeMode,
        verbose: verbose,
        outlineFit: resolvedOutlineFit,
        fitTolerance: fitTolerance,
        simplifyTolerance: simplifyTolerance,
        joinStyle: joinStyle,
        useKinkPath: useKinkPath,
        dumpSamplesPath: dumpSamplesPath
    )
}

func parseShowcaseOptions(_ args: [String]) throws -> ShowcaseOptions {
    var outputDirectory: String?
    var quality: String?
    var index = 0

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--out":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--out requires a directory path") }
            outputDirectory = args[index + 1]
            index += 1
        case "--quality":
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--quality requires preview|final") }
            quality = args[index + 1].lowercased()
            index += 1
        default:
            break
        }
        index += 1
    }

    guard let outputDirectory else {
        throw CLIError.invalidArguments("showcase requires --out <dir>")
    }

    return ShowcaseOptions(outputDirectory: outputDirectory, quality: quality)
}

private func parseViewModes(_ text: String) throws -> Set<ScurveView> {
    let raw = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    if raw.contains("all") {
        return Set([.envelope, .samples, .rays, .rails, .caps, .junctions, .union, .centerline, .offset, .alpha, .refDiff])
    }
    if raw.contains("none") {
        return []
    }
    var result: Set<ScurveView> = []
    for item in raw where !item.isEmpty {
        let resolved: String
        switch item {
        case "diff", "ref-diff":
            resolved = "refDiff"
        default:
            resolved = item
        }
        guard let mode = ScurveView(rawValue: resolved) else {
            throw CLIError.invalidArguments("--view must be envelope|samples|rays|rails|caps|junctions|union|centerline|offset|alpha|ref-diff|all|none")
        }
        result.insert(mode)
    }
    return result
}

func validate(config: ScurvePlaygroundConfig) throws {
    if config.sizeStart <= 0.0 || config.sizeEnd <= 0.0 {
        throw CLIError.invalidArguments("size must be > 0")
    }
    if config.aspectStart <= 0.0 || config.aspectEnd <= 0.0 {
        throw CLIError.invalidArguments("aspect must be > 0")
    }
    if let widthStart = config.widthStart, widthStart <= 0.0 {
        throw CLIError.invalidArguments("width must be > 0")
    }
    if let widthEnd = config.widthEnd, widthEnd <= 0.0 {
        throw CLIError.invalidArguments("width must be > 0")
    }
    if let heightStart = config.heightStart, heightStart <= 0.0 {
        throw CLIError.invalidArguments("height must be > 0")
    }
    if let heightEnd = config.heightEnd, heightEnd <= 0.0 {
        throw CLIError.invalidArguments("height must be > 0")
    }
    if config.alphaStart < -1.0 || config.alphaStart > 1.0 || config.alphaEnd < -1.0 || config.alphaEnd > 1.0 {
        throw CLIError.invalidArguments("alpha must be in [-1,1]")
    }
    if !config.offsetStart.isFinite || !config.offsetEnd.isFinite {
        throw CLIError.invalidArguments("offset must be finite")
    }
    if config.maxSamples < 2 {
        throw CLIError.invalidArguments("samples must be >= 2")
    }
    if case .miter(let limit) = config.joinStyle {
        if limit <= 0.0 || !limit.isFinite {
            throw CLIError.invalidArguments("miter-limit must be positive and finite")
        }
    }
}

private func globalScurvePath() -> BezierPath {
    BezierPath(segments: [
        CubicBezier(
            p0: Point(x: 0, y: 0),
            p1: Point(x: 40, y: 120),
            p2: Point(x: 60, y: 120),
            p3: Point(x: 100, y: 0)
        ),
        CubicBezier(
            p0: Point(x: 100, y: 0),
            p1: Point(x: 140, y: -120),
            p2: Point(x: 160, y: -120),
            p3: Point(x: 200, y: 0)
        ),
        CubicBezier(
            p0: Point(x: 200, y: 0),
            p1: Point(x: 240, y: 120),
            p2: Point(x: 260, y: 120),
            p3: Point(x: 300, y: 0)
        )
    ])
}

private func globalLinePath() -> BezierPath {
    BezierPath(segments: [
        CubicBezier(
            p0: Point(x: 0, y: 0),
            p1: Point(x: 100, y: 0),
            p2: Point(x: 200, y: 0),
            p3: Point(x: 300, y: 0)
        )
    ])
}

private func globalKinkPath() -> BezierPath {
    BezierPath(segments: [
        CubicBezier(
            p0: Point(x: 0, y: 0),
            p1: Point(x: 40, y: 0),
            p2: Point(x: 80, y: 0),
            p3: Point(x: 120, y: 0)
        ),
        CubicBezier(
            p0: Point(x: 120, y: 0),
            p1: Point(x: 120, y: 40),
            p2: Point(x: 120, y: 80),
            p3: Point(x: 120, y: 120)
        )
    ])
}

private func applyBias(s: Double, alphaStart: Double, alphaEnd: Double) -> Double {
    let clamped = ScalarMath.clamp01(s)
    let alpha = ScalarMath.lerp(alphaStart, alphaEnd, clamped)
    return biasCurve(t: clamped, bias: alpha)
}

private func biasCurve(t: Double, bias: Double) -> Double {
    if abs(bias) < 1.0e-9 { return t }
    let clamped = min(max(abs(bias), 0.0001), 0.9999)
    let value = t / ((1.0 / clamped - 2.0) * (1.0 - t) + 1.0)
    if bias >= 0.0 { return value }
    return 1.0 - value
}

func buildScurveGeometry(config: ScurvePlaygroundConfig) throws -> ScurveGeometry {
    let path = config.useKinkPath ? globalKinkPath() : globalScurvePath()
    return try buildPlaygroundGeometry(path: path, config: config)
}

func buildLineGeometry(config: ScurvePlaygroundConfig) throws -> ScurveGeometry {
    let path = config.useKinkPath ? globalKinkPath() : globalLinePath()
    return try buildPlaygroundGeometry(path: path, config: config)
}

func buildPlaygroundGeometry(path: BezierPath, config: ScurvePlaygroundConfig) throws -> ScurveGeometry {
    let domain = PathDomain(path: path, samplesPerSegment: config.samplesPerSegment)
    let angleField = ParamField.linearDegrees(startDeg: config.angleStart, endDeg: config.angleEnd)
    let offsetField = ParamField { s in ScalarMath.lerp(config.offsetStart, config.offsetEnd, ScalarMath.clamp01(s)) }

    let widthField: ParamField
    let heightField: ParamField
    if let widthStart = config.widthStart, let widthEnd = config.widthEnd,
       let heightStart = config.heightStart, let heightEnd = config.heightEnd {
        widthField = ParamField { s in ScalarMath.lerp(widthStart, widthEnd, ScalarMath.clamp01(s)) }
        heightField = ParamField { s in ScalarMath.lerp(heightStart, heightEnd, ScalarMath.clamp01(s)) }
    } else {
        let sizeField = ParamField { s in ScalarMath.lerp(config.sizeStart, config.sizeEnd, ScalarMath.clamp01(s)) }
        let aspectField = ParamField { s in ScalarMath.lerp(config.aspectStart, config.aspectEnd, ScalarMath.clamp01(s)) }
        widthField = ParamField { s in sizeField.evaluate(s) }
        heightField = ParamField { s in sizeField.evaluate(s) * aspectField.evaluate(s) }
    }

    var envelopeLeft: [Point] = []
    var envelopeRight: [Point] = []
    var railCenters: [Point] = []
    var railSegmentIndices: [Int] = []
    var samplePoints: [Point] = []
    var tangentRays: [(Point, Point)] = []
    var angleRays: [(Point, Point)] = []
    var offsetRays: [(Point, Point)] = []
    var stampRings: [Ring] = []

    let bounds = domain.samples.reduce(CGRect.null) { rect, sample in
        rect.union(CGRect(x: sample.point.x, y: sample.point.y, width: 0, height: 0))
    }
    let diag = hypot(bounds.width, bounds.height)
    let rayLength = max(8.0, diag * 0.05)
    let tolerance: Double
    if config.tolerance > 0.0 {
        tolerance = config.tolerance
    } else if config.isFinal {
        tolerance = max(0.4, diag * 0.001)
    } else {
        tolerance = max(1.5, diag * 0.0025)
    }

    let showRays = config.view.contains(.rays)
    let showSamples = config.view.contains(.samples)
    let showRails = config.view.contains(.rails)
    let showEnvelope = config.view.contains(.envelope)
    let showOffsets = config.view.contains(.offset)
    let envelopeUsesUnion = config.envelopeMode == .union
    let envelopeUsesDirect = config.envelopeMode == .direct
    let needsStamps = showSamples || config.view.contains(.union) || (showEnvelope && envelopeUsesUnion)
    let supportShape: CounterpointShape = .ellipse(segments: config.envelopeSegments)

    let stamping = CounterpointStamping()
    let overlapSplit: ((Double, Double) -> Bool)? = envelopeUsesUnion ? { s0, s1 in
        let sample0 = domain.evalAtS(s0, path: path)
        let sample1 = domain.evalAtS(s1, path: path)
        let biased0 = applyBias(s: s0, alphaStart: config.alphaStart, alphaEnd: config.alphaEnd)
        let biased1 = applyBias(s: s1, alphaStart: config.alphaStart, alphaEnd: config.alphaEnd)
        let angle0 = angleField.evaluate(biased0)
        let angle1 = angleField.evaluate(biased1)
        let dir0 = AngleMath.directionVector(unitTangent: sample0.unitTangent, angleDegrees: angle0, mode: config.angleMode)
        let dir1 = AngleMath.directionVector(unitTangent: sample1.unitTangent, angleDegrees: angle1, mode: config.angleMode)
        let axis0 = dir0.normalized() ?? Point(x: 1, y: 0)
        let axis1 = dir1.normalized() ?? Point(x: 1, y: 0)
        let n0 = axis0.leftNormal()
        let n1 = axis1.leftNormal()
        let width0 = widthField.evaluate(biased0)
        let height0 = heightField.evaluate(biased0)
        let width1 = widthField.evaluate(biased1)
        let height1 = heightField.evaluate(biased1)
        let offset0 = offsetField.evaluate(biased0)
        let offset1 = offsetField.evaluate(biased1)
        let center0 = sample0.point + n0 * offset0
        let center1 = sample1.point + n1 * offset1
        let r0 = supportRadius(direction: n0, axis: axis0, normal: n0, width: width0, height: height0, shape: supportShape)
        let r1 = supportRadius(direction: n1, axis: axis1, normal: n1, width: width1, height: height1, shape: supportShape)
        let d = (center1 - center0).length
        let rMin = min(r0, r1)
        let overlapFactor = 0.8
        let overlapFactorMin = 0.8
        let overlapFail = d > overlapFactor * (r0 + r1) || d > overlapFactorMin * (2.0 * rMin)
        let dot = max(-1.0, min(1.0, axis0.dot(axis1)))
        let angleDelta = acos(dot) * 180.0 / .pi
        let angleFail = angleDelta > 12.0
        return overlapFail || angleFail
    } : nil

    var sampleList = adaptiveSampleParameters(
        domain: domain,
        maxDepth: config.maxDepth,
        maxSamples: config.maxSamples,
        tolerance: tolerance,
        baseIntervals: 16,
        leftRightAt: { s in
            let sample = domain.evalAtS(s, path: path)
            let biasedS = applyBias(s: s, alphaStart: config.alphaStart, alphaEnd: config.alphaEnd)
            let angleDeg = angleField.evaluate(biasedS)
            let dir = AngleMath.directionVector(unitTangent: sample.unitTangent, angleDegrees: angleDeg, mode: config.angleMode)
            let dirUnit = dir.normalized() ?? Point(x: 1, y: 0)
            let normal = dirUnit.leftNormal()
            let width = widthField.evaluate(biasedS)
            let height = heightField.evaluate(biasedS)
            let halfWidth = width * 0.5
            let halfHeight = height * 0.5
            let offset = offsetField.evaluate(biasedS)
            let center = sample.point + normal * offset
            if envelopeUsesDirect {
                let tangentAngle = atan2(sample.unitTangent.y, sample.unitTangent.x)
                let angleRadians = angleDeg * .pi / 180.0
                let effectiveRotation: Double
                switch config.angleMode {
                case .absolute:
                    effectiveRotation = angleRadians
                case .tangentRelative:
                    effectiveRotation = tangentAngle + angleRadians
                }
                let leftOffset = DirectSilhouetteTracer.supportOffset(direction: sample.unitTangent.leftNormal(), width: width, height: height, thetaWorld: effectiveRotation)
                let rightOffset = DirectSilhouetteTracer.supportOffset(direction: sample.unitTangent.leftNormal() * -1.0, width: width, height: height, thetaWorld: effectiveRotation)
                return (center + leftOffset, center + rightOffset)
            } else {
                let leftOffset = orientedEllipseSupportPoint(direction: normal, axis: dirUnit, normal: normal, a: halfWidth, b: halfHeight)
                let rightOffset = orientedEllipseSupportPoint(direction: normal * -1.0, axis: dirUnit, normal: normal, a: halfWidth, b: halfHeight)
                return (center + leftOffset, center + rightOffset)
            }
        },
        shouldSplit: overlapSplit
    )

    if envelopeUsesUnion && config.isFinal {
        sampleList = ensureMinSamples(sampleList, minCount: 250)
    }

    var maxOverlapRatio = 0.0
    var sampleCSVLines: [String]? = config.dumpSamplesPath == nil ? nil : ["index,u_grid,u_geom,t_progress,t_eval_used_for_tracks,x,y,width_eval,height_eval,theta_eval,theta_internal,offset_eval,alpha_eval"]
    var directSamples: [Sample] = []
    if envelopeUsesDirect {
        directSamples.reserveCapacity(sampleList.count)
    }
    for (index, s) in sampleList.enumerated() {
        let sample = domain.evalAtS(s, path: path)
        let alpha = ScalarMath.lerp(config.alphaStart, config.alphaEnd, ScalarMath.clamp01(sample.s))
        let biasedS = applyBias(s: sample.s, alphaStart: config.alphaStart, alphaEnd: config.alphaEnd)
        let angleDeg = angleField.evaluate(biasedS)
        let dir = AngleMath.directionVector(unitTangent: sample.unitTangent, angleDegrees: angleDeg, mode: config.angleMode)
        let dirUnit = dir.normalized() ?? Point(x: 1, y: 0)
        let normal = dirUnit.leftNormal()

        let width = widthField.evaluate(biasedS)
        let height = heightField.evaluate(biasedS)
        let halfWidth = width * 0.5
        let halfHeight = height * 0.5
        let offset = offsetField.evaluate(biasedS)
        let center = sample.point + normal * offset
        if sampleCSVLines != nil {
            let thetaRadians = angleDeg * .pi / 180.0
            let effectiveRotation: Double
            switch config.angleMode {
            case .absolute:
                effectiveRotation = thetaRadians
            case .tangentRelative:
                effectiveRotation = atan2(sample.unitTangent.y, sample.unitTangent.x) + thetaRadians
            }
            let line = "\(index),\(formatCSVNumber(sample.s)),\(formatCSVNumber(sample.s)),\(formatCSVNumber(sample.s)),\(formatCSVNumber(biasedS)),\(formatCSVNumber(center.x)),\(formatCSVNumber(center.y)),\(formatCSVNumber(width)),\(formatCSVNumber(height)),\(formatCSVNumber(thetaRadians)),\(formatCSVNumber(effectiveRotation)),\(formatCSVNumber(offset)),\(formatCSVNumber(alpha))"
            sampleCSVLines?.append(line)
        }

        if showEnvelope || showRails {
            if envelopeUsesDirect {
                let tangentAngle = atan2(sample.unitTangent.y, sample.unitTangent.x)
                let angleRadians = angleDeg * .pi / 180.0
                let effectiveRotation: Double
                switch config.angleMode {
                case .absolute:
                    effectiveRotation = angleRadians
                case .tangentRelative:
                    effectiveRotation = tangentAngle + angleRadians
                }
                directSamples.append(
                    Sample(
                        uGeom: sample.s,
                        uGrid: sample.s,
                        t: sample.s,
                        point: center,
                        tangentAngle: tangentAngle,
                        width: width,
                        height: height,
                        theta: angleRadians,
                        effectiveRotation: effectiveRotation,
                        alpha: alpha
                    )
                )
            } else {
                let leftOffset = orientedEllipseSupportPoint(direction: normal, axis: dirUnit, normal: normal, a: halfWidth, b: halfHeight)
                let rightOffset = orientedEllipseSupportPoint(direction: normal * -1.0, axis: dirUnit, normal: normal, a: halfWidth, b: halfHeight)
                envelopeLeft.append(center + leftOffset)
                envelopeRight.append(center + rightOffset)
                railCenters.append(center)
                railSegmentIndices.append(sample.segmentIndex)
            }
        }

        if envelopeUsesDirect, !showEnvelope, !showRails {
            let tangentAngle = atan2(sample.unitTangent.y, sample.unitTangent.x)
            let angleRadians = angleDeg * .pi / 180.0
            let effectiveRotation: Double
            switch config.angleMode {
            case .absolute:
                effectiveRotation = angleRadians
            case .tangentRelative:
                effectiveRotation = tangentAngle + angleRadians
            }
            directSamples.append(
                Sample(
                    uGeom: sample.s,
                    uGrid: sample.s,
                    t: sample.s,
                    point: center,
                    tangentAngle: tangentAngle,
                    width: width,
                    height: height,
                    theta: angleRadians,
                    effectiveRotation: effectiveRotation,
                    alpha: alpha
                )
            )
        }

        if needsStamps {
            let tangentAngle = atan2(sample.unitTangent.y, sample.unitTangent.x)
            let angleRadians = angleDeg * .pi / 180.0
            let effectiveRotation: Double
            switch config.angleMode {
            case .absolute:
                effectiveRotation = angleRadians
            case .tangentRelative:
                effectiveRotation = tangentAngle + angleRadians
            }
            let segments = envelopeUsesUnion ? config.envelopeSegments : config.ellipseSegments
            let stamped = stamping.ring(
                for: Sample(
                    uGeom: sample.s,
                    uGrid: sample.s,
                    t: sample.s,
                    point: center,
                    tangentAngle: tangentAngle,
                    width: width,
                    height: height,
                    theta: angleRadians,
                    effectiveRotation: effectiveRotation,
                    alpha: alpha
                ),
                shape: .ellipse(segments: segments)
            )
            stampRings.append(stamped)
        }

        if config.view.contains(.centerline) {
            samplePoints.append(center)
        }
        if showOffsets {
            offsetRays.append((sample.point, center))
        }
        if showRays {
            let angleEnd = center + dirUnit * rayLength
            let tangentEnd = center + sample.unitTangent * rayLength
            angleRays.append((center, angleEnd))
            tangentRays.append((center, tangentEnd))
        }
    }
    if let dumpPath = config.dumpSamplesPath, let lines = sampleCSVLines {
        try writeCSV(lines: lines, to: dumpPath)
    }
    if envelopeUsesUnion, sampleList.count > 1 {
        for i in 0..<(sampleList.count - 1) {
            let s0 = sampleList[i]
            let s1 = sampleList[i + 1]
            let sample0 = domain.evalAtS(s0, path: path)
            let sample1 = domain.evalAtS(s1, path: path)
            let biased0 = applyBias(s: s0, alphaStart: config.alphaStart, alphaEnd: config.alphaEnd)
            let biased1 = applyBias(s: s1, alphaStart: config.alphaStart, alphaEnd: config.alphaEnd)
            let angle0 = angleField.evaluate(biased0)
            let angle1 = angleField.evaluate(biased1)
            let dir0 = AngleMath.directionVector(unitTangent: sample0.unitTangent, angleDegrees: angle0, mode: config.angleMode)
            let dir1 = AngleMath.directionVector(unitTangent: sample1.unitTangent, angleDegrees: angle1, mode: config.angleMode)
            let axis0 = dir0.normalized() ?? Point(x: 1, y: 0)
            let axis1 = dir1.normalized() ?? Point(x: 1, y: 0)
            let n0 = axis0.leftNormal()
            let n1 = axis1.leftNormal()
            let width0 = widthField.evaluate(biased0)
            let height0 = heightField.evaluate(biased0)
            let width1 = widthField.evaluate(biased1)
            let height1 = heightField.evaluate(biased1)
            let offset0 = offsetField.evaluate(biased0)
            let offset1 = offsetField.evaluate(biased1)
            let center0 = sample0.point + n0 * offset0
            let center1 = sample1.point + n1 * offset1
            let r0 = supportRadius(direction: n0, axis: axis0, normal: n0, width: width0, height: height0, shape: supportShape)
            let r1 = supportRadius(direction: n1, axis: axis1, normal: n1, width: width1, height: height1, shape: supportShape)
            let d = (center1 - center0).length
            let denom = max(1.0e-9, r0 + r1)
            let ratio = d / denom
            if ratio > maxOverlapRatio {
                maxOverlapRatio = ratio
            }
        }
    }

    var envelopeOutline: Ring = []
    var capPoints: [Point] = []
    var unionPolygons: PolygonSet = []
    var junctionPatches: [Ring] = []
    var junctionCorridors: [Ring] = []
    var junctionControlPoints: [Point] = []
    if envelopeUsesDirect {
        let railTolerance = config.tolerance > 0 ? config.tolerance : 0.5
        let paramsProvider: DirectSilhouetteTracer.DirectSilhouetteParamProvider = { t, tangentAngle in
            let clampedT = ScalarMath.clamp01(t)
            let biasedT = applyBias(s: clampedT, alphaStart: config.alphaStart, alphaEnd: config.alphaEnd)
            let angleDeg = angleField.evaluate(biasedT)
            let theta = angleDeg * .pi / 180.0
            let width = widthField.evaluate(biasedT)
            let height = heightField.evaluate(biasedT)
            let alpha = ScalarMath.lerp(config.alphaStart, config.alphaEnd, clampedT)
            let effectiveRotation: Double
            switch config.angleMode {
            case .absolute:
                effectiveRotation = theta
            case .tangentRelative:
                effectiveRotation = tangentAngle + theta
            }
            return (width, height, theta, effectiveRotation, alpha)
        }
        let direct = DirectSilhouetteTracer.trace(
            samples: directSamples,
            capStyle: .round,
            railTolerance: railTolerance,
            paramsProvider: paramsProvider,
            verbose: config.verbose
        )
        envelopeLeft = direct.leftRail
        envelopeRight = direct.rightRail
        envelopeOutline = showEnvelope ? direct.outline : []
        capPoints = config.view.contains(.caps) ? direct.capPoints : []
        junctionPatches = config.view.contains(.junctions) ? direct.junctionPatches : []
        junctionCorridors = config.view.contains(.junctions) ? direct.junctionCorridors : []
        junctionControlPoints = config.view.contains(.junctions) ? direct.junctionControlPoints : []
        unionPolygons = direct.junctionPatches.map { Polygon(outer: $0) }
    } else {
        if !envelopeLeft.isEmpty,
           envelopeLeft.count == envelopeRight.count,
           envelopeLeft.count == railCenters.count {
            let joined = applyRailJoins(
                left: envelopeLeft,
                right: envelopeRight,
                centers: railCenters,
                segmentIndices: railSegmentIndices,
                joinStyle: config.joinStyle,
                cornerThresholdDegrees: 35.0,
                roundSegments: config.joinStyle == .round ? 10 : 6
            )
            envelopeLeft = joined.left
            envelopeRight = joined.right
        }

        if showEnvelope, !envelopeLeft.isEmpty, envelopeLeft.count == envelopeRight.count {
            envelopeOutline = closeRingIfNeeded(envelopeLeft + envelopeRight.reversed())
        }
    }

    if (showEnvelope && envelopeUsesUnion) || config.view.contains(.union) {
        let builder = BridgeBuilder()
        var rings = stampRings
        if stampRings.count > 1 {
            for i in 0..<(stampRings.count - 1) {
                if let bridges = try? builder.bridgeRings(from: stampRings[i], to: stampRings[i + 1]) {
                    rings.append(contentsOf: bridges)
                }
            }
        }
        unionPolygons = try IOverlayPolygonUnionAdapter().union(subjectRings: rings)
    }

    let centerline = config.view.contains(.centerline) ? domain.samples.map { $0.point } : []
    return ScurveGeometry(
        envelopeLeft: envelopeLeft,
        envelopeRight: envelopeRight,
        envelopeOutline: envelopeOutline,
        capPoints: capPoints,
        junctionPatches: junctionPatches,
        junctionCorridors: junctionCorridors,
        junctionControlPoints: junctionControlPoints,
        unionPolygons: unionPolygons,
        stampRings: stampRings,
        samplePoints: samplePoints,
        tangentRays: tangentRays,
        angleRays: angleRays,
        offsetRays: offsetRays,
        centerline: centerline,
        sValues: sampleList,
        maxOverlapRatio: maxOverlapRatio,
        centerlineSamples: domain.samples
    )
}

func adaptiveSampleParameters(
    domain: PathDomain,
    maxDepth: Int,
    maxSamples: Int,
    tolerance: Double,
    baseIntervals: Int,
    leftRightAt: (Double) -> (Point, Point),
    shouldSplit: ((Double, Double) -> Bool)? = nil
) -> [Double] {
    let intervalCount = max(1, baseIntervals)
    let step = 1.0 / Double(intervalCount)
    var intervals: [(Double, Double, Int)] = []
    intervals.reserveCapacity(intervalCount)
    for i in 0..<intervalCount {
        let s0 = Double(i) * step
        let s1 = Double(i + 1) * step
        intervals.append((s0, s1, 0))
    }

    var result: [Double] = []
    result.reserveCapacity(maxSamples)

    func refine(s0: Double, s1: Double, depth: Int) {
        if result.count >= maxSamples - 1 {
            result.append(s0)
            return
        }
        if depth >= maxDepth {
            result.append(s0)
            return
        }
        let sm = (s0 + s1) * 0.5
        let left0 = leftRightAt(s0).0
        let right0 = leftRightAt(s0).1
        let left1 = leftRightAt(s1).0
        let right1 = leftRightAt(s1).1
        let leftM = leftRightAt(sm).0
        let rightM = leftRightAt(sm).1

        let leftInterp = lerpPoint(left0, left1, 0.5)
        let rightInterp = lerpPoint(right0, right1, 0.5)
        let errLeft = (leftM - leftInterp).length
        let errRight = (rightM - rightInterp).length
        let err = max(errLeft, errRight)
        let forceSplit = shouldSplit?(s0, s1) ?? false

        if err > tolerance || forceSplit {
            refine(s0: s0, s1: sm, depth: depth + 1)
            refine(s0: sm, s1: s1, depth: depth + 1)
        } else {
            result.append(s0)
        }
    }

    for (s0, s1, depth) in intervals {
        refine(s0: s0, s1: s1, depth: depth)
        if result.count >= maxSamples - 1 {
            break
        }
    }

    result.append(1.0)
    let deduped = dedupeSorted(result, epsilon: 1.0e-9)
    return capSamples(deduped, maxSamples: maxSamples)
}

private func lerpPoint(_ a: Point, _ b: Point, _ t: Double) -> Point {
    Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

private func dedupeSorted(_ values: [Double], epsilon: Double) -> [Double] {
    guard !values.isEmpty else { return [] }
    let sorted = values.sorted()
    var result: [Double] = [sorted[0]]
    for value in sorted.dropFirst() {
        if abs(value - result.last!) > epsilon {
            result.append(value)
        }
    }
    if result.first != 0.0 {
        result.insert(0.0, at: 0)
    }
    if result.last != 1.0 {
        result.append(1.0)
    }
    return result
}

private func capSamples(_ values: [Double], maxSamples: Int) -> [Double] {
    guard values.count > maxSamples else { return values }
    if maxSamples <= 2 { return [0.0, 1.0] }
    let head = Array(values.prefix(maxSamples - 1))
    if head.last == 1.0 {
        return head
    }
    return head + [1.0]
}

private func ensureMinSamples(_ values: [Double], minCount: Int) -> [Double] {
    guard values.count < minCount else { return values }
    if minCount <= 2 { return [0.0, 1.0] }
    let step = 1.0 / Double(minCount - 1)
    return (0..<minCount).map { Double($0) * step }
}

private func parseAngleMode(_ text: String) throws -> AngleMode {
    let normalized = text.lowercased()
    switch normalized {
    case "absolute", "abs":
        return .absolute
    case "relative", "tangent", "relative-to-tangent":
        return .tangentRelative
    default:
        throw CLIError.invalidArguments("--angle-mode must be absolute|relative")
    }
}

private func parseSize(_ text: String) throws -> CGSize {
    let parts = text.split(separator: "x", omittingEmptySubsequences: false)
    guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) else {
        throw CLIError.invalidArguments("--svg-size must be formatted as WxH")
    }
    return CGSize(width: width, height: height)
}

private func dumpSamplesCSV(samples: [Sample], spec: StrokeSpec, to path: String) throws {
    var lines: [String] = ["index,u_grid,u_geom,t_progress,t_eval_used_for_tracks,x,y,width_eval,height_eval,theta_eval,theta_internal,offset_eval,alpha_eval"]
    lines.reserveCapacity(samples.count + 1)
    let evaluator = DefaultParamEvaluator()
    for (index, sample) in samples.enumerated() {
        let offsetValue = spec.offset.map { evaluator.evaluate($0, at: sample.t) } ?? 0.0
        let alphaValue = sample.alpha
        let line = "\(index),\(formatCSVNumber(sample.uGrid)),\(formatCSVNumber(sample.uGeom)),\(formatCSVNumber(sample.t)),\(formatCSVNumber(sample.t)),\(formatCSVNumber(sample.point.x)),\(formatCSVNumber(sample.point.y)),\(formatCSVNumber(sample.width)),\(formatCSVNumber(sample.height)),\(formatCSVNumber(sample.theta)),\(formatCSVNumber(sample.effectiveRotation)),\(formatCSVNumber(offsetValue)),\(formatCSVNumber(alphaValue))"
        lines.append(line)
    }
    try writeCSV(lines: lines, to: path)
}

private func writeCSV(lines: [String], to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()
    if !dir.path.isEmpty, dir.path != "." {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    let content = lines.joined(separator: "\n") + "\n"
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func formatCSVNumber(_ value: Double) -> String {
    String(format: "%.6f", value)
}

private func outputTranslation(for spec: StrokeSpec, polyline: PathPolyline) -> Point {
    let mode = spec.output?.coordinateMode ?? .normalized
    guard mode == .normalized, let origin = polyline.points.first else { return Point(x: 0, y: 0) }
    return Point(x: -origin.x, y: -origin.y)
}

private func makeAlphaChart(track: ParamTrack, tProbe: Double, trackLabel: String, alphaOverride: Double?) -> SVGPathBuilder.AlphaDebugChart? {
    let keyframes = track.keyframes
    guard keyframes.count >= 2 else { return nil }
    let clampedProbe = ScalarMath.clamp01(tProbe)

    var a = keyframes[0]
    var b = keyframes[1]
    for index in 0..<(keyframes.count - 1) {
        let current = keyframes[index]
        let next = keyframes[index + 1]
        if clampedProbe <= next.t {
            a = current
            b = next
            break
        }
    }

    let alphaRaw = alphaOverride ?? (a.interpolationToNext?.alpha ?? 0.0)
    let alphaUsed: Double
    let dMid: Double
    if let alphaOverride {
        let sign = alphaOverride >= 0 ? 1.0 : -1.0
        var magnitude = max(0.0, min(4.0, abs(alphaOverride)))
        var computed = DefaultParamEvaluator.biasCurveValue(0.5, bias: sign * magnitude)
        var deviation = abs(computed - 0.5)
        let minDeviation = 0.20
        let maxMagnitude = 4.0
        while deviation < minDeviation && magnitude < maxMagnitude {
            magnitude = min(maxMagnitude, magnitude + 0.05)
            computed = DefaultParamEvaluator.biasCurveValue(0.5, bias: sign * magnitude)
            deviation = abs(computed - 0.5)
        }
        if deviation < minDeviation {
            fatalError("alpha-demo failed: alpha=\(alphaOverride) f(0.5)=\(computed) dMid=\(deviation)")
        }
        alphaUsed = sign * magnitude
        dMid = deviation
    } else {
        alphaUsed = alphaRaw
        dMid = abs(DefaultParamEvaluator.biasCurveValue(0.5, bias: alphaUsed) - 0.5)
    }

    let sampleCount = 64
    var biasSamples: [Point] = []
    var valueSamples: [Point] = []
    biasSamples.reserveCapacity(sampleCount)
    valueSamples.reserveCapacity(sampleCount)

    let valueMin = min(a.value, b.value)
    let valueMax = max(a.value, b.value)
    let valueSpan = valueMax - valueMin

    for i in 0..<sampleCount {
        let u = Double(i) / Double(sampleCount - 1)
        let uBiased = DefaultParamEvaluator.biasCurveValue(u, bias: alphaUsed)
        biasSamples.append(Point(x: u, y: uBiased))
        if valueSpan > 1.0e-12 {
            let value = a.value + (b.value - a.value) * uBiased
            let normalized = ScalarMath.clamp01((value - valueMin) / valueSpan)
            valueSamples.append(Point(x: u, y: normalized))
        }
    }

    let t0 = alphaOverride == nil ? a.t : 0.0
    let t1 = alphaOverride == nil ? b.t : 1.0

    return SVGPathBuilder.AlphaDebugChart(
        alphaRaw: alphaRaw,
        alphaUsed: alphaUsed,
        t0: t0,
        t1: t1,
        trackLabel: trackLabel,
        biasSamples: biasSamples,
        valueSamples: valueSamples,
        valueMin: valueMin,
        valueMax: valueMax,
        startValue: a.value,
        endValue: b.value,
        dMid: dMid
    )
}

private enum CLIError: LocalizedError {
    case invalidArguments(String)
    case runtime(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .runtime(let message):
            return message
        }
    }
}

func makeDebugOverlay(spec: StrokeSpec, options: CLIOptions) -> SVGDebugOverlay {
    let policy = spec.samplingPolicy ?? SamplingPolicy.fromSamplingSpec(spec.sampling)
    let polyline = DefaultPathSampler().makePolyline(path: spec.path, tolerance: policy.flattenTolerance)
    let translation = outputTranslation(for: spec, polyline: polyline)
    let applyTranslation: (Point) -> Point = { point in
        Point(x: point.x + translation.x, y: point.y + translation.y)
    }
    let samples = GenerateStrokeOutlineUseCase(
        sampler: DefaultPathSampler(),
        evaluator: DefaultParamEvaluator(),
        unioner: PassthroughPolygonUnioner()
    ).generateSamples(for: spec)

    let stamping = CounterpointStamping()
    let stampRings = samples.map { stamping.ring(for: $0, shape: spec.counterpointShape) }

    var bridgeRings: [Ring] = []
    if stampRings.count > 1 {
        let builder = BridgeBuilder()
        for i in 0..<(stampRings.count - 1) {
            if let bridges = try? builder.bridgeRings(from: stampRings[i], to: stampRings[i + 1]) {
                bridgeRings.append(contentsOf: bridges)
            }
        }
    }

    var samplePoints = samples.map { $0.point }
    var tangentRays: [(Point, Point)] = []
    var angleRays: [(Point, Point)] = []
    var envelopeLeft: [Point] = []
    var envelopeRight: [Point] = []
    var envelopeOutline: Ring = []
    let showEnvelope = options.showEnvelope ?? options.debugSamples
    let showUnionOutline = options.showEnvelopeUnion
    let showRays = options.showRays ?? options.debugSamples

    if options.exampleName == "global-angle-scurve" {
        let samplesPerSegment = (options.quality == "final") ? 200 : 60
        let domain = PathDomain(path: spec.path, samplesPerSegment: samplesPerSegment)
        let angleField = ParamField.linearDegrees(startDeg: 10.0, endDeg: 75.0)
        let bounds = domain.samples.reduce(CGRect.null) { rect, sample in
            rect.union(CGRect(x: sample.point.x, y: sample.point.y, width: 0, height: 0))
        }
        let diag = hypot(bounds.width, bounds.height)
        let rayLength = max(8.0, diag * 0.05)
        samplePoints = domain.samples.map { applyTranslation($0.point) }
        if showRays {
            tangentRays = domain.samples.map { sample in
                let origin = applyTranslation(sample.point)
                let end = applyTranslation(sample.point + sample.unitTangent * rayLength)
                return (origin, end)
            }
            angleRays = domain.samples.map { sample in
                let angle = angleField.evaluate(sample.s)
                let dir = AngleMath.directionVector(unitTangent: sample.unitTangent, angleDegrees: angle, mode: spec.angleMode)
                let origin = applyTranslation(sample.point)
                let end = applyTranslation(sample.point + dir * rayLength)
                return (origin, end)
            }
        }

        if showEnvelope {
            let evaluator = DefaultParamEvaluator()
            for sample in domain.samples {
                let angle = angleField.evaluate(sample.s)
                let dir = AngleMath.directionVector(unitTangent: sample.unitTangent, angleDegrees: angle, mode: spec.angleMode)
                let dirUnit = dir.normalized() ?? Point(x: 1, y: 0)
                let normal = dirUnit.leftNormal()

                let width = evaluator.evaluate(spec.width, at: sample.s)
                let height = evaluator.evaluate(spec.height, at: sample.s)
                let halfWidth = width * 0.5
                let halfHeight = height * 0.5

                let leftOffset: Point
                let rightOffset: Point
                switch spec.counterpointShape {
                case .ellipse:
                    leftOffset = orientedEllipseSupportPoint(direction: normal, axis: dirUnit, normal: normal, a: halfWidth, b: halfHeight)
                    rightOffset = orientedEllipseSupportPoint(direction: normal * -1.0, axis: dirUnit, normal: normal, a: halfWidth, b: halfHeight)
                case .rectangle:
                    let radius = max(halfWidth, halfHeight)
                    leftOffset = normal * radius
                    rightOffset = normal * -radius
                }

                envelopeLeft.append(applyTranslation(sample.point + leftOffset))
                envelopeRight.append(applyTranslation(sample.point + rightOffset))
            }

            if !envelopeLeft.isEmpty && envelopeRight.count == envelopeLeft.count {
                envelopeOutline = envelopeLeft + envelopeRight.reversed()
                envelopeOutline = closeRingIfNeeded(envelopeOutline)
            }
        }
    }

    let alphaChart = options.showAlpha ? makeAlphaChart(track: spec.width, tProbe: options.alphaProbeT ?? 0.5, trackLabel: "width", alphaOverride: options.alphaDemo) : nil

    return SVGDebugOverlay(
        skeleton: polyline.points.map { applyTranslation($0) },
        stamps: stampRings,
        bridges: bridgeRings,
        samplePoints: samplePoints,
        tangentRays: tangentRays,
        angleRays: angleRays,
        offsetRays: [],
        envelopeLeft: envelopeLeft,
        envelopeRight: envelopeRight,
        envelopeOutline: envelopeOutline,
        capPoints: [],
        junctionPatches: [],
        junctionCorridors: [],
        junctionControlPoints: [],
        showUnionOutline: showUnionOutline,
        unionPolygons: nil,
        alphaChart: alphaChart
    )
}

private func ellipseSupportPoint(direction: Point, a: Double, b: Double) -> Point {
    let dx = direction.x
    let dy = direction.y
    let denom = sqrt((a * dx) * (a * dx) + (b * dy) * (b * dy))
    guard denom > 1.0e-12 else { return Point(x: 0, y: 0) }
    return Point(x: (a * a * dx) / denom, y: (b * b * dy) / denom)
}

private func orientedEllipseSupportPoint(direction: Point, axis: Point, normal: Point, a: Double, b: Double) -> Point {
    let dx = direction.dot(axis)
    let dy = direction.dot(normal)
    let denom = sqrt((a * dx) * (a * dx) + (b * dy) * (b * dy))
    guard denom > 1.0e-12 else { return Point(x: 0, y: 0) }
    let local = Point(x: (a * a * dx) / denom, y: (b * b * dy) / denom)
    return axis * local.x + normal * local.y
}

private func supportRadius(direction: Point, axis: Point, normal: Point, width: Double, height: Double, shape: CounterpointShape) -> Double {
    let halfWidth = width * 0.5
    let halfHeight = height * 0.5
    switch shape {
    case .ellipse:
        let offset = orientedEllipseSupportPoint(direction: direction, axis: axis, normal: normal, a: halfWidth, b: halfHeight)
        return offset.length
    case .rectangle:
        return max(halfWidth, halfHeight)
    }
}

func defaultFitTolerance(polygons: PolygonSet) -> Double {
    var minX = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for polygon in polygons {
        for point in polygon.outer {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        for hole in polygon.holes {
            for point in hole {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
        }
    }
    if !minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite {
        return 0.5
    }
    let diag = hypot(maxX - minX, maxY - minY)
    return max(0.5, diag * 0.001)
}

private func traceEpsilon(unionSimplifyTolerance: Double) -> Double {
    max(0.01, unionSimplifyTolerance * 0.01)
}

func outlineCornerThresholdDegrees(for joinStyle: JoinStyle) -> Double {
    switch joinStyle {
    case .round:
        return 60.0
    case .bevel, .miter:
        return 25.0
    }
}

private func renderGlyphDocument(_ document: GlyphDocument, options: CLIOptions, inputPath: String?) throws {
    guard let svgPath = options.svgOutputPath else {
        throw CLIError.invalidArguments("Glyph documents require --svg output.")
    }
    let outputURL = URL(fileURLWithPath: svgPath)
    let outputDir = outputURL.deletingLastPathComponent()
    if !outputDir.path.isEmpty, outputDir.path != "." {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    let referenceRender: SVGPathBuilder.BackgroundGlyphRender?
    if let reference = document.derived?.reference {
        let resolvedPath = resolveReferencePath(reference.source, inputPath: inputPath)
        guard let source = SVGPathBuilder.loadBackgroundGlyph(from: resolvedPath) else {
            throw CLIError.runtime("Failed to load reference SVG at: \(resolvedPath)")
        }
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
    let builder = SVGPathBuilder()
    let centerlines: [String]
    let strokePreviewPolygons: PolygonSet
    let authoredPolygons: PolygonSet
    let authoredFittedPaths: [FittedPath]?
    let debugOverlay: SVGDebugOverlay?
    if options.centerlineOnly {
        let pathById = Dictionary(uniqueKeysWithValues: document.inputs.geometry.paths.map { ($0.id, $0) })
        var rendered: [String] = []
        rendered.reserveCapacity(document.inputs.geometry.ink.count)
        for item in document.inputs.geometry.ink {
            switch item {
            case .path(let path):
                let element = builder.centerlinePathElement(for: path.segments, stroke: "#111111", strokeWidth: 1.0)
                if !element.isEmpty { rendered.append(element) }
            case .stroke(let stroke):
                for skeleton in stroke.skeletons {
                    if let path = pathById[skeleton] {
                        let element = builder.centerlinePathElement(for: path.segments, stroke: "#111111", strokeWidth: 1.0)
                        if !element.isEmpty { rendered.append(element) }
                    }
                }
            case .unknown:
                continue
            }
        }
        centerlines = rendered
        strokePreviewPolygons = []
        authoredPolygons = []
        authoredFittedPaths = nil
        debugOverlay = nil
    } else if options.strokePreview {
        centerlines = []
        strokePreviewPolygons = buildStrokePreviewPolygons(document: document, options: options)
        authoredPolygons = []
        authoredFittedPaths = nil
        debugOverlay = nil
    } else {
        centerlines = []
        strokePreviewPolygons = []
        let authored = try buildAuthoredStrokePolygons(document: document, options: options)
        authoredPolygons = authored.polygons
        authoredFittedPaths = authored.fittedPaths
        var overlay: SVGDebugOverlay? = nil
        if options.showJunctions,
           !authored.junctionPatches.isEmpty || !authored.junctionControlPoints.isEmpty {
            overlay = SVGDebugOverlay(
                skeleton: [],
                stamps: [],
                bridges: [],
                samplePoints: [],
                tangentRays: [],
                angleRays: [],
                offsetRays: [],
                envelopeLeft: [],
                envelopeRight: [],
                envelopeOutline: [],
                capPoints: [],
                junctionPatches: authored.junctionPatches,
                junctionCorridors: authored.junctionCorridors,
                junctionControlPoints: authored.junctionControlPoints,
                showUnionOutline: false,
                unionPolygons: nil
            )
        }
        if options.showRefDiff, options.finalEnvelopeMode == .direct,
           let referenceRender {
            let resolution = options.diffResolution ?? 1024
            if let diffOverlay = buildReferenceDiffOverlay(
                current: authoredPolygons,
                reference: referenceRender,
                generatedBounds: frameBounds,
                resolution: resolution,
                builder: builder,
                verbose: options.verbose
            ) {
                if overlay == nil {
                    overlay = SVGDebugOverlay(
                        skeleton: [],
                        stamps: [],
                        bridges: [],
                        samplePoints: [],
                        tangentRays: [],
                        angleRays: [],
                        offsetRays: [],
                        envelopeLeft: [],
                        envelopeRight: [],
                        envelopeOutline: [],
                        capPoints: [],
                        junctionPatches: [],
                        junctionCorridors: [],
                        junctionControlPoints: [],
                        showUnionOutline: false,
                        unionPolygons: nil
                    )
                }
                overlay?.refDiff = diffOverlay
            }
        }
        debugOverlay = overlay
    }
    let debugRects = traceDebugRects(polygons: authoredPolygons, options: options)
    let svg = builder.svgDocumentForGlyphReference(
        frameBounds: frameBounds,
        size: options.svgSize,
        padding: options.padding,
        reference: referenceRender,
        centerlinePaths: centerlines,
        polygons: strokePreviewPolygons + authoredPolygons,
        fittedPaths: authoredFittedPaths,
        debugRects: debugRects,
        debugOverlay: debugOverlay
    )
    try svg.write(to: outputURL, atomically: true, encoding: .utf8)
}

private func buildReferenceDiffOverlay(
    current: PolygonSet,
    reference: SVGPathBuilder.BackgroundGlyphRender,
    generatedBounds: CGRect,
    resolution: Int,
    builder: SVGPathBuilder,
    verbose: Bool
) -> SVGPathBuilder.RefDiffOverlay? {
    let referencePolygons = builder.referencePolygons(from: reference, generatedBounds: generatedBounds, sampleSteps: 16)
    guard let bounds = unionPolygonBounds(current, referencePolygons) else { return nil }
    let maxDim = max(bounds.width, bounds.height)
    let pixelSize = max(maxDim / Double(resolution), 1.0e-4)
    let width = max(1, Int(ceil(bounds.width / pixelSize)))
    let height = max(1, Int(ceil(bounds.height / pixelSize)))
    let fixedBounds = Rasterizer.RasterBounds(
        minX: bounds.minX,
        minY: bounds.minY,
        maxX: bounds.minX + Double(width) * pixelSize,
        maxY: bounds.minY + Double(height) * pixelSize
    )

    let currentResult = Rasterizer.rasterizeFixed(polygons: current, bounds: fixedBounds, pixelSize: pixelSize)
    let referenceResult = Rasterizer.rasterizeFixed(polygons: referencePolygons, bounds: fixedBounds, pixelSize: pixelSize)
    let count = currentResult.grid.width * currentResult.grid.height
    var data: [UInt8] = Array(repeating: 0, count: count)
    var matchCount = 0
    var missingCount = 0
    var excessCount = 0

    for idx in 0..<count {
        let ref = referenceResult.grid.data[idx] != 0
        let cur = currentResult.grid.data[idx] != 0
        if ref && cur {
            data[idx] = 1
            matchCount += 1
        } else if ref && !cur {
            data[idx] = 2
            missingCount += 1
        } else if !ref && cur {
            data[idx] = 3
            excessCount += 1
        }
    }

    if verbose {
        let pixelArea = pixelSize * pixelSize
        let matchArea = Double(matchCount) * pixelArea
        let missingArea = Double(missingCount) * pixelArea
        let excessArea = Double(excessCount) * pixelArea
        print("ref-diff resolution=\(resolution) pixelSize=\(String(format: "%.4f", pixelSize)) grid=\(width)x\(height)")
        print("ref-diff areas match=\(String(format: "%.2f", matchArea)) missing=\(String(format: "%.2f", missingArea)) excess=\(String(format: "%.2f", excessArea))")
    }

    return SVGPathBuilder.RefDiffOverlay(
        origin: currentResult.origin,
        pixelSize: currentResult.pixelSize,
        width: currentResult.grid.width,
        height: currentResult.grid.height,
        data: data,
        matchCount: matchCount,
        missingCount: missingCount,
        excessCount: excessCount
    )
}

private func unionPolygonBounds(_ a: PolygonSet, _ b: PolygonSet) -> CGRect? {
    guard let boundsA = polygonBounds(a) else { return polygonBounds(b) }
    guard let boundsB = polygonBounds(b) else { return boundsA }
    return boundsA.union(boundsB)
}

private func polygonBounds(_ polygons: PolygonSet) -> CGRect? {
    var minX = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for polygon in polygons {
        for point in polygon.outer {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        for hole in polygon.holes {
            for point in hole {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
        }
    }
    guard minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { return nil }
    return CGRect(x: minX, y: minY, width: max(0.0, maxX - minX), height: max(0.0, maxY - minY))
}

private func traceDebugRects(polygons: PolygonSet, options: CLIOptions) -> [SVGPathBuilder.DebugRect] {
    guard options.verbose, options.finalUnionMode == .trace else { return [] }
    guard polygons.count > 1 else { return [] }
    let areas = polygons.enumerated().map { index, polygon in
        (index: index, area: abs(signedArea(polygon.outer)))
    }.sorted { $0.area > $1.area }
    guard let main = areas.first,
          let mainBox = boundingBox(polygons[main.index].outer) else {
        return []
    }
    var rects: [SVGPathBuilder.DebugRect] = [
        SVGPathBuilder.DebugRect(min: mainBox.min, max: mainBox.max, stroke: "#e53935", strokeWidth: 0.8)
    ]
    if let candidate = areas.dropFirst().first,
       let candidateBox = boundingBox(polygons[candidate.index].outer) {
        rects.append(SVGPathBuilder.DebugRect(min: candidateBox.min, max: candidateBox.max, stroke: "#1e88e5", strokeWidth: 0.8))
    }
    return rects
}

private func resolveReferencePath(_ source: String, inputPath: String?) -> String {
    if source.hasPrefix("/") { return source }
    let fm = FileManager.default
    if let inputPath {
        let base = URL(fileURLWithPath: inputPath).deletingLastPathComponent()
        let candidate = base.appendingPathComponent(source).path
        if fm.fileExists(atPath: candidate) { return candidate }
        let references = base.appendingPathComponent("references").appendingPathComponent(source).path
        if fm.fileExists(atPath: references) { return references }
        let siblingReferences = base.deletingLastPathComponent().appendingPathComponent("references").appendingPathComponent(source).path
        if fm.fileExists(atPath: siblingReferences) { return siblingReferences }
    }
    let cwdReferences = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("references")
        .appendingPathComponent(source)
        .path
    if fm.fileExists(atPath: cwdReferences) { return cwdReferences }
    return source
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

private func buildStrokePreviewPolygons(document: GlyphDocument, options: CLIOptions) -> PolygonSet {
    var polygons: PolygonSet = []
    polygons.reserveCapacity(document.inputs.geometry.paths.count)

    let width = options.previewWidth ?? 24.0
    let height = options.previewHeight ?? 8.0
    let angleMode = options.previewAngleMode ?? .absolute
    let angleOffset = (options.previewAngleDeg ?? 30.0) * .pi / 180.0
    let nibRotate = (options.previewNibRotateDeg ?? 0.0) * .pi / 180.0
    let baseRotation = nibRotate + angleOffset
    let samplesPerSegment = max(2, options.previewSamples ?? defaultPreviewSamples(for: options.previewQuality))
    let sampler = DefaultPathSampler()

    let stamping = CounterpointStamping()
    let builder = BridgeBuilder()
    let previewUnionMaxRings = 200

    for path in document.inputs.geometry.paths {
        let segments = path.segments.compactMap { segment -> CubicBezier? in
            if case .cubic(let cubic) = segment { return cubic }
            return nil
        }
        if segments.isEmpty { continue }

        let bezierPath = BezierPath(segments: segments)
        let tolerance = previewFlattenTolerance(for: options.previewQuality)
        let polyline = sampler.makePolyline(path: bezierPath, tolerance: tolerance)
        let totalSamples = max(2, samplesPerSegment * segments.count)
        let spacing = polyline.totalLength > 0 ? polyline.totalLength / Double(max(1, totalSamples - 1)) : 1.0
        let parameters = polyline.sampleParameters(spacing: spacing, maxSamples: totalSamples)
        let samples: [Sample] = parameters.map { s in
            let point = polyline.point(at: s)
            let tangentAngle = polyline.tangentAngle(at: s, fallbackAngle: 0.0)
            let effectiveRotation: Double
            switch angleMode {
            case .absolute:
                effectiveRotation = baseRotation
            case .tangentRelative:
                effectiveRotation = tangentAngle + baseRotation - (.pi / 2.0)
            }
            return Sample(
                uGeom: s,
                uGrid: s,
                t: s,
                point: point,
                tangentAngle: tangentAngle,
                width: width,
                height: height,
                theta: angleOffset,
                effectiveRotation: effectiveRotation,
                alpha: 0.0
            )
        }

        let rings = samples.map { stamping.ring(for: $0, shape: .rectangle) }
        var bridges: [Ring] = []
        if rings.count > 1 {
            for i in 0..<(rings.count - 1) {
                if let segmentBridges = try? builder.bridgeRings(from: rings[i], to: rings[i + 1]) {
                    bridges.append(contentsOf: segmentBridges)
                }
            }
        }
        let allRings = rings + bridges
        let unionMode = options.previewUnionMode ?? .never
        let useUnion: Bool
        switch unionMode {
        case .never:
            useUnion = false
        case .always:
            useUnion = true
        case .auto:
            useUnion = allRings.count <= previewUnionMaxRings
            if options.verbose {
                let chosen = useUnion ? "always" : "never"
                print("stroke-preview \(path.id) union auto -> \(chosen) (rings \(allRings.count))")
            }
        }
        let unioner: PolygonUnioning = useUnion ? IOverlayPolygonUnionAdapter() : PassthroughPolygonUnioner()
        if let outline = try? unioner.union(subjectRings: allRings) {
            polygons.append(contentsOf: outline)
        } else {
            polygons.append(contentsOf: allRings.map { Polygon(outer: $0) })
        }

        if options.verbose, samples.count > 1 {
            var minDistance = Double.greatestFiniteMagnitude
            for i in 1..<samples.count {
                let d = (samples[i].point - samples[i - 1].point).length
                minDistance = min(minDistance, d)
            }
            let minDisplay = minDistance.isFinite ? minDistance : 0.0
            print("stroke-preview \(path.id) samples \(samples.count) minSegment \(String(format: "%.3f", minDisplay))")
        }
    }

    return polygons
}

struct AuthoredStrokeRender {
    let polygons: PolygonSet
    let fittedPaths: [FittedPath]?
    let junctionPatches: [Ring]
    let junctionCorridors: [Ring]
    let junctionControlPoints: [Point]
    let junctionDiagnostics: [DirectSilhouetteTracer.JunctionDiagnostic]
}

func buildAuthoredStrokePolygons(document: GlyphDocument, options: CLIOptions) throws -> AuthoredStrokeRender {
    let pathById = Dictionary(uniqueKeysWithValues: document.inputs.geometry.paths.map { ($0.id, $0) })
    let quality = options.quality ?? "preview"
    let isFinal = quality == "final"
    let useDirectEnvelope = options.finalEnvelopeMode == .direct
    let unionMode: FinalUnionMode
    if isFinal {
        unionMode = options.finalUnionMode ?? .auto
    } else {
        unionMode = FinalUnionMode(rawValue: options.previewUnionMode?.rawValue ?? "never") ?? .never
    }
    let unionSimplifyTolerance = options.unionSimplifyTolerance ?? 0.75
    let unionMaxVertices = options.unionMaxVertices ?? 5000
    let unionBatchSize = max(1, options.unionBatchSize ?? 50)
    let unionAreaEps = options.unionAreaEps ?? 1.0e-6
    let unionWeldEps = options.unionWeldEps ?? 1.0e-5
    let unionEdgeEps = options.unionEdgeEps ?? 1.0e-5
    let unionMinRingArea = options.unionMinRingArea ?? 5.0
    let unionAutoTimeBudgetMs = options.unionAutoTimeBudgetMs ?? 1500
    let unionInputFilter = options.unionInputFilter ?? .none
    let unionSilhouetteK = max(1, options.unionSilhouetteK ?? 60)
    let unionSilhouetteDropContained = options.unionSilhouetteDropContained ?? true
    let unionDumpInputPath = options.unionDumpInputPath

    let sampler = DefaultPathSampler()
    let evaluator = DefaultParamEvaluator()
    var polygons: PolygonSet = []
    polygons.reserveCapacity(document.inputs.geometry.strokes.count)
    var directFittedPaths: [FittedPath] = []
    var junctionPatches: [Ring] = []
    var junctionCorridors: [Ring] = []
    var junctionControlPoints: [Point] = []
    var junctionDiagnostics: [DirectSilhouetteTracer.JunctionDiagnostic] = []

    for stroke in document.inputs.geometry.strokes {
        guard let spec = strokeSpec(from: stroke, paths: pathById, quality: quality) else { continue }
        if useDirectEnvelope {
            let skeletonPaths = stroke.skeletons.compactMap { pathById[$0] }.compactMap(bezierPath(from:))
            if !skeletonPaths.isEmpty {
                let useCase = GenerateStrokeOutlineUseCase(sampler: sampler, evaluator: evaluator, unioner: PassthroughPolygonUnioner())
                let concatenated = useCase.generateConcatenatedSamplesWithJunctions(for: spec, paths: skeletonPaths)
                let junctions = concatenated.junctionPairs.enumerated().compactMap { index, pair -> DirectSilhouetteTracer.JunctionContext? in
                    guard pair.0 >= 0, pair.1 >= 0,
                          pair.0 < concatenated.samples.count,
                          pair.1 < concatenated.samples.count else { return nil }
                    let prev = pair.0 > 0 ? concatenated.samples[pair.0 - 1] : nil
                    let next = pair.1 + 1 < concatenated.samples.count ? concatenated.samples[pair.1 + 1] : nil
                    return DirectSilhouetteTracer.JunctionContext(
                        joinIndex: index,
                        prev: prev,
                        a: concatenated.samples[pair.0],
                        b: concatenated.samples[pair.1],
                        next: next
                    )
                }
                let railTolerance = spec.samplingPolicy?.envelopeTolerance ?? 0.5
                let traceWindow: DirectSilhouetteTraceWindow?
                if let tMin = options.traceTMin, let tMax = options.traceTMax {
                    let label = options.traceStrokeId ?? stroke.id
                    traceWindow = DirectSilhouetteTraceWindow(tMin: tMin, tMax: tMax, label: label)
                } else {
                    traceWindow = nil
                }

                if let window = traceWindow, options.traceStrokeId == nil || options.traceStrokeId == stroke.id {
                    print("direct-trace stroke=\(stroke.id) window [\(String(format: "%.6f", window.tMin))..\((String(format: "%.6f", window.tMax)))]")
                    for sample in concatenated.samples where window.contains(sample.t) {
                        if let debug = evaluator.debugEvaluate(spec.width, at: sample.t) {
                            let linear = debug.v0 + (debug.v1 - debug.v0) * debug.uRaw
                            let alphaNote = debug.alphaWasNil ? "alphaSource=nil" : "alphaSource=keyframe"
                            let alphaStart = debug.alphaFromStart.map { String(format: "%.3f", $0) } ?? "nil"
                            let alphaEnd = debug.alphaFromEnd.map { String(format: "%.3f", $0) } ?? "nil"
                            let alphaReason: String
                            if debug.alphaFromStart != nil {
                                alphaReason = "alphaFromStart"
                            } else if debug.alphaFromEnd != nil {
                                alphaReason = "alphaOnEndKeyframe"
                            } else {
                                alphaReason = "alphaMissing"
                            }
                            print("[EVAL width] t=\(String(format: "%.6f", debug.t)) seg=\(debug.segmentIndex) [\(String(format: "%.6f", debug.t0))..\((String(format: "%.6f", debug.t1)))] v0=\(String(format: "%.3f", debug.v0)) v1=\(String(format: "%.3f", debug.v1)) alpha=\(String(format: "%.3f", debug.alphaUsed)) \(alphaNote) uRaw=\(String(format: "%.6f", debug.uRaw)) uBiased=\(String(format: "%.6f", debug.uBiased)) wLinear=\(String(format: "%.3f", linear)) wEased=\(String(format: "%.3f", debug.value))")
                            print("[EVAL width segPick] t=\(String(format: "%.6f", debug.t)) i0=\(debug.segmentIndex) i1=\(debug.segmentIndex + 1) alphaFromStart=\(alphaStart) alphaFromEnd=\(alphaEnd) reason=\(alphaReason)")
                        }
                        if let debug = evaluator.debugEvaluate(spec.height, at: sample.t) {
                            print("[EVAL height] t=\(String(format: "%.6f", debug.t)) v=\(String(format: "%.3f", debug.value))")
                        }
                        if let debug = evaluator.debugEvaluate(spec.theta, at: sample.t) {
                            print("[EVAL theta] t=\(String(format: "%.6f", debug.t)) theta=\(String(format: "%.6f", debug.value))")
                        }
                    }
                }

                let paramsProvider: DirectSilhouetteTracer.DirectSilhouetteParamProvider = { t, tangentAngle in
                    let width = evaluator.evaluate(spec.width, at: t)
                    let height = evaluator.evaluate(spec.height, at: t)
                    let theta = evaluator.evaluateAngle(spec.theta, at: t)
                    let alpha = spec.alpha.map { evaluator.evaluate($0, at: t) } ?? 0.0
                    let effectiveRotation: Double
                    switch spec.angleMode {
                    case .absolute:
                        effectiveRotation = theta
                    case .tangentRelative:
                        effectiveRotation = tangentAngle + theta
                    }
                    return (width, height, theta, effectiveRotation, alpha)
                }
                let directResult = DirectSilhouetteTracer.trace(
                    samples: concatenated.samples,
                    junctions: junctions,
                    capStyle: spec.capStyle,
                    railTolerance: railTolerance,
                    paramsProvider: paramsProvider,
                    traceWindow: (options.traceStrokeId == nil || options.traceStrokeId == stroke.id) ? traceWindow : nil,
                    verbose: options.verbose
                )
                if !directResult.outline.isEmpty {
                    polygons.append(Polygon(outer: directResult.outline))
                    if let fitted = directFittedPath(from: directResult) {
                        directFittedPaths.append(fitted)
                    }
                    for patch in directResult.junctionPatches {
                        polygons.append(Polygon(outer: patch))
                        if let patchPath = catmullRomFittedPath(from: patch) {
                            directFittedPaths.append(patchPath)
                        }
                    }
                    junctionPatches.append(contentsOf: directResult.junctionPatches)
                    junctionCorridors.append(contentsOf: directResult.junctionCorridors)
                    junctionControlPoints.append(contentsOf: directResult.junctionControlPoints)
                    junctionDiagnostics.append(contentsOf: directResult.junctionDiagnostics)
                    continue
                } else if options.verbose {
                    print("authored-stroke \(stroke.id) direct envelope empty; falling back to union")
                }
            }
        }
        let estimator = GenerateStrokeOutlineUseCase(sampler: sampler, evaluator: evaluator, unioner: PassthroughPolygonUnioner())
        let sampleCount = estimator.generateSamples(for: spec).count
        if options.verbose {
            print("authored-stroke \(stroke.id) stamps \(sampleCount)")
        }
        let unioner: PolygonUnioning
        switch unionMode {
        case .never:
            unioner = PassthroughPolygonUnioner()
        case .always:
            unioner = SimplifyingUnioner(
                base: IOverlayPolygonUnionAdapter(),
                simplifyTolerance: unionSimplifyTolerance,
                maxVertices: unionMaxVertices,
                areaEps: unionAreaEps,
                minRingArea: unionMinRingArea,
                weldEps: unionWeldEps,
                edgeEps: unionEdgeEps,
                batchSize: unionBatchSize,
                inputFilter: unionInputFilter,
                silhouetteK: unionSilhouetteK,
                silhouetteDropContained: unionSilhouetteDropContained,
                dumpInputPath: unionDumpInputPath,
                verbose: options.verbose,
                label: "authored-stroke \(stroke.id)"
            )
        case .auto:
            unioner = AutoUnioner(
                base: IOverlayPolygonUnionAdapter(),
                simplifyTolerance: unionSimplifyTolerance,
                maxVertices: unionMaxVertices,
                areaEps: unionAreaEps,
                minRingArea: unionMinRingArea,
                weldEps: unionWeldEps,
                edgeEps: unionEdgeEps,
                batchSize: unionBatchSize,
                autoTimeBudgetMs: unionAutoTimeBudgetMs,
                inputFilter: unionInputFilter,
                silhouetteK: unionSilhouetteK,
                silhouetteDropContained: unionSilhouetteDropContained,
                dumpInputPath: unionDumpInputPath,
                verbose: options.verbose,
                label: "authored-stroke \(stroke.id)"
            )
        case .trace:
            unioner = PassthroughPolygonUnioner()
        }

        let useCase = GenerateStrokeOutlineUseCase(sampler: sampler, evaluator: evaluator, unioner: unioner)
        var outline: PolygonSet
        do {
            outline = try useCase.generateOutline(for: spec, includeBridges: options.useBridges)
        } catch {
            if case .auto = unionMode, isFinal {
                if options.verbose {
                    print("authored-stroke \(stroke.id) union skipped due to error: \(error)")
                }
                let fallback = GenerateStrokeOutlineUseCase(sampler: sampler, evaluator: evaluator, unioner: PassthroughPolygonUnioner())
                outline = try fallback.generateOutline(for: spec, includeBridges: options.useBridges)
            } else {
                throw error
            }
        }
        if case .trace = unionMode {
            let epsilon = traceEpsilon(unionSimplifyTolerance: unionSimplifyTolerance)
            let closingPasses = (quality == "final") ? 2 : 1
            print("authored-stroke \(stroke.id) trace silhouette epsilon=\(String(format: "%.6f", epsilon)) closingPasses=\(closingPasses)")
            outline = OutlineTracer.traceSilhouette(outline, epsilon: epsilon, closingPasses: closingPasses)
        }
        polygons.append(contentsOf: outline)
    }

    guard !polygons.isEmpty else {
        return AuthoredStrokeRender(
            polygons: [],
            fittedPaths: nil,
            junctionPatches: junctionPatches,
            junctionCorridors: junctionCorridors,
            junctionControlPoints: junctionControlPoints,
            junctionDiagnostics: junctionDiagnostics
        )
    }

    if useDirectEnvelope, !directFittedPaths.isEmpty {
        return AuthoredStrokeRender(
            polygons: polygons,
            fittedPaths: directFittedPaths,
            junctionPatches: junctionPatches,
            junctionCorridors: junctionCorridors,
            junctionControlPoints: junctionControlPoints,
            junctionDiagnostics: junctionDiagnostics
        )
    }

    let outlineFit = options.outlineFit ?? .none
    let fitTolerance = options.fitTolerance ?? defaultFitTolerance(polygons: polygons)
    let simplifyTolerance = options.simplifyTolerance ?? (fitTolerance * 1.5)
    let cornerThreshold = 60.0
    switch outlineFit {
    case .none:
        return AuthoredStrokeRender(
            polygons: polygons,
            fittedPaths: nil,
            junctionPatches: junctionPatches,
            junctionCorridors: junctionCorridors,
            junctionControlPoints: junctionControlPoints,
            junctionDiagnostics: junctionDiagnostics
        )
    case .simplify:
        let simplifier = BezierFitter(tolerance: simplifyTolerance, cornerThresholdDegrees: cornerThreshold)
        let simplified = polygons.map { polygon in
            let outer = simplifier.simplifyRing(polygon.outer, closed: true)
            let holes = polygon.holes.map { simplifier.simplifyRing($0, closed: true) }
            return Polygon(outer: outer, holes: holes)
        }
        return AuthoredStrokeRender(
            polygons: simplified,
            fittedPaths: nil,
            junctionPatches: junctionPatches,
            junctionCorridors: junctionCorridors,
            junctionControlPoints: junctionControlPoints,
            junctionDiagnostics: junctionDiagnostics
        )
    case .bezier:
        let simplifier = BezierFitter(tolerance: simplifyTolerance, cornerThresholdDegrees: cornerThreshold)
        let simplified = polygons.map { polygon in
            let outer = simplifier.simplifyRing(polygon.outer, closed: true)
            let holes = polygon.holes.map { simplifier.simplifyRing($0, closed: true) }
            return Polygon(outer: outer, holes: holes)
        }
        let fitter = BezierFitter(tolerance: fitTolerance, cornerThresholdDegrees: cornerThreshold)
        let fitted = fitter.fitPolygonSet(simplified)
        return AuthoredStrokeRender(
            polygons: [],
            fittedPaths: fitted,
            junctionPatches: junctionPatches,
            junctionCorridors: junctionCorridors,
            junctionControlPoints: junctionControlPoints,
            junctionDiagnostics: junctionDiagnostics
        )
    }
}

func bezierPath(from path: PathGeometry) -> BezierPath? {
    let segments = path.segments.compactMap { segment -> CubicBezier? in
        if case .cubic(let cubic) = segment { return cubic }
        return nil
    }
    guard !segments.isEmpty else { return nil }
    return BezierPath(segments: segments)
}

func strokeSpec(from stroke: StrokeGeometry, paths: [String: PathGeometry], quality: String) -> StrokeSpec? {
    let skeletonSegments = stroke.skeletons.compactMap { paths[$0] }.flatMap { path in
        path.segments.compactMap { segment -> CubicBezier? in
            if case .cubic(let cubic) = segment { return cubic }
            return nil
        }
    }
    guard !skeletonSegments.isEmpty else { return nil }

    let samplingPolicy = stroke.samplingPolicy ?? ((quality == "final") ? .final : .preview)
    let samplingSpec = SamplingSpec()
    let width = paramTrack(from: stroke.params.width)
    let height = paramTrack(from: stroke.params.height)
    let theta = paramTrack(from: stroke.params.theta)
    let offset = stroke.params.offset.map { paramTrack(from: $0) }
    let alpha = stroke.params.alpha.map { paramTrack(from: $0) }
    let angleMode = stroke.params.angleMode ?? .absolute
    let capStyle = stroke.joins?.capStyle ?? .butt
    let joinStyle = stroke.joins?.joinStyle ?? .round

    return StrokeSpec(
        path: BezierPath(segments: skeletonSegments),
        width: width,
        height: height,
        theta: theta,
        offset: offset,
        alpha: alpha,
        angleMode: angleMode,
        capStyle: capStyle,
        joinStyle: joinStyle,
        counterpointShape: .rectangle,
        sampling: samplingSpec,
        samplingPolicy: samplingPolicy,
        output: OutputSpec(coordinateMode: .raw)
    )
}

private func paramTrack(from curve: ParamCurve) -> ParamTrack {
    let frames = curve.keyframes.map { Keyframe(t: $0.t, value: $0.value, interpolationToNext: $0.interpolationToNext) }
    return ParamTrack(keyframes: frames)
}

private func dumpDecodedKeyframes(document: GlyphDocument, options: CLIOptions) {
    let targetId = options.traceStrokeId
    for stroke in document.inputs.geometry.strokes {
        if let targetId, stroke.id != targetId { continue }
        print("decoded-keyframes stroke=\(stroke.id) track=width")
        for (index, keyframe) in stroke.params.width.keyframes.enumerated() {
            let alphaText: String
            if let alpha = keyframe.interpolationToNext?.alpha {
                alphaText = String(format: "%.6f", alpha)
            } else {
                alphaText = "nil"
            }
            print("  [\(index)] t=\(String(format: "%.6f", keyframe.t)) value=\(String(format: "%.6f", keyframe.value)) alpha=\(alphaText)")
        }
    }
}

struct CleanupStats {
    let preRingCount: Int
    let preVertexCount: Int
    let cleanedRingCount: Int
    let cleanedVertexCount: Int
    let sliverRingCount: Int
    let sliverVertexCount: Int
    let tinyRingCount: Int
    let tinyVertexCount: Int
    let dedupRingCount: Int
    let dedupVertexCount: Int
}

private func logCleanupStats(label: String, stats: CleanupStats) {
    print("\(label) union cleanup rings \(stats.preRingCount) verts \(stats.preVertexCount) -> \(stats.cleanedRingCount)/\(stats.cleanedVertexCount)")
    print("\(label) union sliver drop \(stats.cleanedRingCount - stats.sliverRingCount) remaining \(stats.sliverRingCount)")
    let tinyDropped = stats.sliverRingCount - stats.tinyRingCount
    print("\(label) union tiny drop \(tinyDropped) remaining \(stats.tinyRingCount)")
    print("\(label) union droppedTinyRings \(tinyDropped) remaining \(stats.tinyRingCount)")
    print("\(label) union dedup drop \(stats.tinyRingCount - stats.dedupRingCount) remaining \(stats.dedupRingCount)")
}

struct SilhouetteStats {
    let inputCount: Int
    let keptCount: Int
    let containedDropCount: Int
}

private func logSilhouetteStats(label: String, k: Int, stats: SilhouetteStats) {
    print("\(label) union silhouette keep K=\(k) from \(stats.inputCount) -> \(stats.keptCount)")
    if stats.containedDropCount > 0 {
        print("\(label) union silhouette contained drop \(stats.containedDropCount) remaining \(stats.keptCount)")
    }
}

private struct RingMetrics {
    let ringCount: Int
    let totalVerts: Int
    let maxRingVerts: Int
}

private func ringMetrics(_ rings: [Ring]) -> RingMetrics {
    var total = 0
    var maxVerts = 0
    for ring in rings {
        let count = ring.count
        total += count
        if count > maxVerts { maxVerts = count }
    }
    return RingMetrics(ringCount: rings.count, totalVerts: total, maxRingVerts: maxVerts)
}

private func logUnionAdapterCall(label: String, batch: Int, metrics: RingMetrics) {
    print("\(label) union calling adapter batch \(batch): inputRings=\(metrics.ringCount) totalVerts=\(metrics.totalVerts) maxRingVerts=\(metrics.maxRingVerts)")
}

private struct RingValidationResult {
    let isValid: Bool
    let reason: String?
}

private func validateRingForUnion(_ ring: Ring, epsilon: Double) -> RingValidationResult {
    guard ring.count >= 3 else { return RingValidationResult(isValid: false, reason: "vertexCount<3") }
    for point in ring {
        if !point.x.isFinite || !point.y.isFinite {
            return RingValidationResult(isValid: false, reason: "nonFinite")
        }
    }
    let area = abs(ringArea(ring))
    if area <= epsilon {
        return RingValidationResult(isValid: false, reason: "area<=eps")
    }
    var prev = ring[0]
    for index in 1..<ring.count {
        let current = ring[index]
        if (current - prev).length < epsilon {
            return RingValidationResult(isValid: false, reason: "duplicatePoint")
        }
        prev = current
    }
    if ringSelfIntersects(ring, epsilon: epsilon) {
        return RingValidationResult(isValid: false, reason: "selfIntersect")
    }
    return RingValidationResult(isValid: true, reason: nil)
}

private func logInvalidRing(label: String, index: Int, ring: Ring, reason: String) {
    let area = abs(ringArea(ring))
    let bounds = ringBounds(ring)
    print("\(label) union invalid ring idx=\(index) reason=\(reason) verts=\(ring.count) area=\(String(format: "%.3f", area)) bbox=\(String(format: "%.3f", bounds.width))x\(String(format: "%.3f", bounds.height))")
}

private func filterInvalidRings(label: String, rings: [Ring], epsilon: Double, dropInvalid: Bool) -> [Ring] {
    var filtered: [Ring] = []
    filtered.reserveCapacity(rings.count)
    for (index, ring) in rings.enumerated() {
        let result = validateRingForUnion(ring, epsilon: epsilon)
        if result.isValid {
            filtered.append(ring)
        } else if let reason = result.reason {
            logInvalidRing(label: label, index: index, ring: ring, reason: reason)
            if !dropInvalid {
                filtered.append(ring)
            }
        }
    }
    return filtered
}

private func ringSelfIntersects(_ ring: Ring, epsilon: Double) -> Bool {
    let count = ring.count
    guard count >= 4 else { return false }
    for i in 0..<(count - 1) {
        let a1 = ring[i]
        let a2 = ring[(i + 1) % count]
        let start = i + 2
        let end = count - 1
        if start > end { continue }
        for j in start..<end {
            if i == 0 && j == count - 2 { continue }
            let b1 = ring[j]
            let b2 = ring[(j + 1) % count]
            if segmentsIntersect(a1, a2, b1, b2, epsilon: epsilon) {
                return true
            }
        }
    }
    return false
}

private func segmentsIntersect(_ p1: Point, _ p2: Point, _ q1: Point, _ q2: Point, epsilon: Double) -> Bool {
    func orientation(_ a: Point, _ b: Point, _ c: Point) -> Double {
        (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
    }
    let o1 = orientation(p1, p2, q1)
    let o2 = orientation(p1, p2, q2)
    let o3 = orientation(q1, q2, p1)
    let o4 = orientation(q1, q2, p2)
    if abs(o1) < epsilon && abs(o2) < epsilon && abs(o3) < epsilon && abs(o4) < epsilon {
        return false
    }
    return (o1 * o2 < 0) && (o3 * o4 < 0)
}

private func dumpUnionInputRings(_ rings: [Ring], to path: String) {
    var payload: [[ [String: Double] ]] = []
    payload.reserveCapacity(rings.count)
    for ring in rings {
        var points: [[String: Double]] = []
        points.reserveCapacity(ring.count)
        for point in ring {
            points.append(["x": point.x, "y": point.y])
        }
        payload.append(points)
    }
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

private func dumpUnionInputOnce(_ rings: [Ring], to path: String) {
    if FileManager.default.fileExists(atPath: path) { return }
    dumpUnionInputRings(rings, to: path)
}

private func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0.0 }
    let sorted = values.sorted()
    let clamped = max(0.0, min(1.0, p))
    let index = Int(round(clamped * Double(sorted.count - 1)))
    return sorted[index]
}

private func ringStatsReport(label: String, rings: [Ring]) {
    guard !rings.isEmpty else {
        print("\(label) union stats: no rings")
        return
    }
    var areas: [Double] = []
    var slivers: [Double] = []
    var widths: [Double] = []
    var heights: [Double] = []
    var verts: [Double] = []
    areas.reserveCapacity(rings.count)
    slivers.reserveCapacity(rings.count)
    widths.reserveCapacity(rings.count)
    heights.reserveCapacity(rings.count)
    verts.reserveCapacity(rings.count)
    var entries: [(area: Double, width: Double, height: Double, verts: Int)] = []
    entries.reserveCapacity(rings.count)
    for ring in rings {
        let area = abs(ringArea(ring))
        let bbox = ringBounds(ring)
        let width = bbox.width
        let height = bbox.height
        let bboxArea = max(width * height, 1.0e-9)
        let sliverRatio = area / bboxArea
        areas.append(area)
        slivers.append(sliverRatio)
        widths.append(width)
        heights.append(height)
        verts.append(Double(ring.count))
        entries.append((area: area, width: width, height: height, verts: ring.count))
    }
    let areaMin = areas.min() ?? 0.0
    let areaMax = areas.max() ?? 0.0
    let widthMin = widths.min() ?? 0.0
    let widthMax = widths.max() ?? 0.0
    let heightMin = heights.min() ?? 0.0
    let heightMax = heights.max() ?? 0.0
    let vertsMin = verts.min() ?? 0.0
    let vertsMax = verts.max() ?? 0.0
    print("\(label) union stats rings \(rings.count)")
    print("\(label) union area min \(String(format: "%.3f", areaMin)) p50 \(String(format: "%.3f", percentile(areas, 0.5))) p90 \(String(format: "%.3f", percentile(areas, 0.9))) p99 \(String(format: "%.3f", percentile(areas, 0.99))) max \(String(format: "%.3f", areaMax))")
    print("\(label) union sliver min \(String(format: "%.4f", slivers.min() ?? 0.0)) p50 \(String(format: "%.4f", percentile(slivers, 0.5))) p90 \(String(format: "%.4f", percentile(slivers, 0.9))) p99 \(String(format: "%.4f", percentile(slivers, 0.99))) max \(String(format: "%.4f", slivers.max() ?? 0.0))")
    print("\(label) union bboxW min \(String(format: "%.3f", widthMin)) p50 \(String(format: "%.3f", percentile(widths, 0.5))) p99 \(String(format: "%.3f", percentile(widths, 0.99))) max \(String(format: "%.3f", widthMax))")
    print("\(label) union bboxH min \(String(format: "%.3f", heightMin)) p50 \(String(format: "%.3f", percentile(heights, 0.5))) p99 \(String(format: "%.3f", percentile(heights, 0.99))) max \(String(format: "%.3f", heightMax))")
    print("\(label) union verts min \(String(format: "%.0f", vertsMin)) p50 \(String(format: "%.0f", percentile(verts, 0.5))) p99 \(String(format: "%.0f", percentile(verts, 0.99))) max \(String(format: "%.0f", vertsMax))")

    let largest = entries.sorted { $0.area > $1.area }.prefix(10)
    let smallest = entries.sorted { $0.area < $1.area }.prefix(10)
    print("\(label) union largest rings:")
    for entry in largest {
        print("  area \(String(format: "%.3f", entry.area)) bbox \(String(format: "%.3f", entry.width))x\(String(format: "%.3f", entry.height)) verts \(entry.verts)")
    }
    print("\(label) union smallest rings:")
    for entry in smallest {
        print("  area \(String(format: "%.3f", entry.area)) bbox \(String(format: "%.3f", entry.width))x\(String(format: "%.3f", entry.height)) verts \(entry.verts)")
    }
}

func cleanupRingsForUnion(
    _ rings: [Ring],
    areaEps: Double,
    minRingArea: Double,
    weldEps: Double,
    edgeEps: Double
) -> (rings: [Ring], stats: CleanupStats) {
    let bboxEps = 0.5
    let sliverRatioMin = 0.01
    let sliverRatioLoose = 0.02
    let sliverVertexCap = 5
    let sliverTinyEps = 1.0e-9
    let dedupeTolerance = 0.05
    let preRingCount = rings.count
    let preVertexCount = rings.reduce(0) { $0 + $1.count }
    var cleaned: [Ring] = []
    cleaned.reserveCapacity(rings.count)
    var cleanedVerts = 0
    for ring in rings {
        guard let result = cleanupRing(ring, areaEps: areaEps, weldEps: weldEps, edgeEps: edgeEps) else {
            continue
        }
        cleanedVerts += result.count
        cleaned.append(result)
    }
    var sliverFiltered: [Ring] = []
    sliverFiltered.reserveCapacity(cleaned.count)
    var sliverVerts = 0
    for ring in cleaned {
        let area = abs(ringArea(ring))
        let bbox = ringBounds(ring)
        let bboxArea = max(bbox.width * bbox.height, sliverTinyEps)
        let sliverRatio = area / bboxArea
        if sliverRatio < sliverRatioMin || (sliverRatio < sliverRatioLoose && ring.count <= sliverVertexCap) {
            continue
        }
        sliverVerts += ring.count
        sliverFiltered.append(ring)
    }
    var tinyFiltered: [Ring] = []
    tinyFiltered.reserveCapacity(sliverFiltered.count)
    var tinyVerts = 0
    for ring in sliverFiltered {
        let area = abs(ringArea(ring))
        if area < minRingArea {
            continue
        }
        let bbox = ringBounds(ring)
        if bbox.width < bboxEps && bbox.height < bboxEps {
            continue
        }
        tinyVerts += ring.count
        tinyFiltered.append(ring)
    }
    let deduped = dedupeRingsByQuantizedPoints(tinyFiltered, tolerance: dedupeTolerance)
    let dedupVertexCount = deduped.rings.reduce(0) { $0 + $1.count }
    let stats = CleanupStats(
        preRingCount: preRingCount,
        preVertexCount: preVertexCount,
        cleanedRingCount: cleaned.count,
        cleanedVertexCount: cleanedVerts,
        sliverRingCount: sliverFiltered.count,
        sliverVertexCount: sliverVerts,
        tinyRingCount: tinyFiltered.count,
        tinyVertexCount: tinyVerts,
        dedupRingCount: deduped.rings.count,
        dedupVertexCount: dedupVertexCount
    )
    return (deduped.rings, stats)
}

func simplifyRingsForUnion(
    _ rings: [Ring],
    baseTolerance: Double,
    maxVertices: Int,
    areaEps: Double,
    minRingArea: Double,
    weldEps: Double,
    edgeEps: Double,
    inputFilter: UnionInputFilter,
    silhouetteK: Int,
    silhouetteDropContained: Bool
) throws -> (rings: [Ring], preCount: Int, postCount: Int, cleanup: CleanupStats, silhouette: SilhouetteStats?) {
    let cleaned = cleanupRingsForUnion(
        rings,
        areaEps: areaEps,
        minRingArea: minRingArea,
        weldEps: weldEps,
        edgeEps: edgeEps
    )
    let preCount = cleaned.stats.preVertexCount
    var ringsForSimplify = cleaned.rings
    var silhouetteStats: SilhouetteStats?
    if inputFilter == .silhouette {
        let filtered = applySilhouetteFilter(
            cleaned.rings,
            k: silhouetteK,
            dropContained: silhouetteDropContained
        )
        ringsForSimplify = filtered.rings
        silhouetteStats = filtered.stats
    }
    var postCount = 0
    var simplified: [Ring] = []
    simplified.reserveCapacity(ringsForSimplify.count)
    for ring in ringsForSimplify {
        var tolerance = baseTolerance
        var simplifiedRing = ring
        var success = false
        for _ in 0..<8 {
            let fitter = BezierFitter(tolerance: tolerance, cornerThresholdDegrees: 60.0)
            simplifiedRing = fitter.simplifyRing(ring, closed: true)
            if simplifiedRing.count <= maxVertices {
                success = true
                break
            }
            tolerance *= 1.5
        }
        if !success {
            throw CLIError.runtime("Union ring exceeded max vertices (\(maxVertices)) even after simplification.")
        }
        postCount += simplifiedRing.count
        simplified.append(simplifiedRing)
    }
    return (simplified, preCount, postCount, cleaned.stats, silhouetteStats)
}

private struct SimplifyingUnioner: PolygonUnioning {
    let base: PolygonUnioning
    let simplifyTolerance: Double
    let maxVertices: Int
    let areaEps: Double
    let minRingArea: Double
    let weldEps: Double
    let edgeEps: Double
    let batchSize: Int
    let inputFilter: UnionInputFilter
    let silhouetteK: Int
    let silhouetteDropContained: Bool
    let dumpInputPath: String?
    let verbose: Bool
    let label: String

    func union(subjectRings: [Ring]) throws -> PolygonSet {
        let start = Date()
        let validated = filterInvalidRings(label: label, rings: subjectRings, epsilon: 1.0e-6, dropInvalid: false)
        let simplified = try simplifyRingsForUnion(
            validated,
            baseTolerance: simplifyTolerance,
            maxVertices: maxVertices,
            areaEps: areaEps,
            minRingArea: minRingArea,
            weldEps: weldEps,
            edgeEps: edgeEps,
            inputFilter: inputFilter,
            silhouetteK: silhouetteK,
            silhouetteDropContained: silhouetteDropContained
        )
        if verbose {
            logCleanupStats(label: label, stats: simplified.cleanup)
            if let silhouetteStats = simplified.silhouette {
                logSilhouetteStats(label: label, k: silhouetteK, stats: silhouetteStats)
            }
            print("\(label) union simplify verts \(simplified.cleanup.tinyVertexCount) -> \(simplified.postCount)")
        }
        let cleanedCount = simplified.rings.count
        let batches = batchedUnion(
            rings: simplified.rings,
            batchSize: batchSize,
            unioner: base,
            dumpPath: dumpInputPath,
            verbose: verbose,
            label: label
        )
        if verbose {
            print("\(label) union batches \(cleanedCount) -> \(batches.count)")
        }
        let finalMetrics = ringMetrics(batches)
        logUnionAdapterCall(label: label, batch: 0, metrics: finalMetrics)
        if let dumpInputPath {
            dumpUnionInputOnce(batches, to: dumpInputPath)
        }
        let result = try base.union(subjectRings: batches)
        if verbose {
            let elapsed = Date().timeIntervalSince(start)
            print("\(label) union time \(String(format: "%.3f", elapsed))s")
        }
        return result
    }
}

private struct AutoUnioner: PolygonUnioning {
    let base: PolygonUnioning
    let simplifyTolerance: Double
    let maxVertices: Int
    let areaEps: Double
    let minRingArea: Double
    let weldEps: Double
    let edgeEps: Double
    let batchSize: Int
    let autoTimeBudgetMs: Int
    let inputFilter: UnionInputFilter
    let silhouetteK: Int
    let silhouetteDropContained: Bool
    let dumpInputPath: String?
    let verbose: Bool
    let label: String

    func union(subjectRings: [Ring]) throws -> PolygonSet {
        let cleaned = cleanupRingsForUnion(
            subjectRings,
            areaEps: areaEps,
            minRingArea: minRingArea,
            weldEps: weldEps,
            edgeEps: edgeEps
        )
        var unionInput = cleaned.rings
        var silhouetteStats: SilhouetteStats?
        if inputFilter == .silhouette {
            let filtered = applySilhouetteFilter(
                unionInput,
                k: silhouetteK,
                dropContained: silhouetteDropContained
            )
            unionInput = filtered.rings
            silhouetteStats = filtered.stats
        }
        let effectiveBatchSize = min(batchSize, 50)
        if verbose {
            logCleanupStats(label: label, stats: cleaned.stats)
            ringStatsReport(label: label, rings: unionInput)
            if let silhouetteStats {
                logSilhouetteStats(label: label, k: silhouetteK, stats: silhouetteStats)
            }
        }
        if unionInput.count > 250 {
            let baseRings = cleaned.rings
            let primary = applySilhouetteFilter(
                baseRings,
                k: silhouetteK,
                dropContained: silhouetteDropContained
            )
            if verbose {
                logSilhouetteStats(label: label, k: silhouetteK, stats: primary.stats)
            }
            unionInput = primary.rings
            if unionInput.count > 250 {
                let retryK = min(30, unionInput.count)
                let retry = applySilhouetteFilter(
                    baseRings,
                    k: retryK,
                    dropContained: silhouetteDropContained
                )
                if verbose {
                    logSilhouetteStats(label: label, k: retryK, stats: retry.stats)
                }
                unionInput = retry.rings
            }
            if unionInput.count > 250 {
                if verbose {
                    print("\(label) auto union skipped: ringCountCap")
                }
                return cleaned.rings.map { Polygon(outer: $0) }
            }
        }
        unionInput = filterInvalidRings(label: label, rings: unionInput, epsilon: 1.0e-6, dropInvalid: true)
        let coincidentCleanup = cleanupCoincidentEdges(
            rings: unionInput.enumerated().map { IndexedRing(index: $0.offset, ring: $0.element) },
            snapTol: 1.0e-3,
            minRemainingCount: 120
        )
        logCoincidentEdgeCleanup(label: label, result: coincidentCleanup)
        let minKeep = 6
        let maxDrops = min(40, max(0, coincidentCleanup.rings.count - minKeep))
        let touchCleanup = cleanupTouchingEdges(
            rings: coincidentCleanup.rings,
            epsilon: 5.0e-4,
            minKeep: minKeep,
            maxDrops: maxDrops,
            verbose: verbose
        )
        logTouchingCleanup(label: label, result: touchCleanup)
        unionInput = touchCleanup.rings.map { $0.ring }
        if touchCleanup.pairCount > 0 || touchCleanup.dropped.count >= maxDrops {
            print("\(label) auto union skipped: touchingPairsRemaining pairs=\(touchCleanup.pairCount) remaining=\(unionInput.count)")
            print("\(label) auto union preflight rings=\(unionInput.count) pairs=\(touchCleanup.pairCount) action=skip")
            return cleaned.rings.map { Polygon(outer: $0) }
        }
        print("\(label) auto union preflight rings=\(unionInput.count) pairs=\(touchCleanup.pairCount) action=union")
        let safeMaxRingsAuto = 120
        let safeMaxTotalVertsAuto = 3000
        let safeMaxRingVertsAuto = 128
        let metrics = ringMetrics(unionInput)
        if metrics.ringCount > safeMaxRingsAuto
            || metrics.totalVerts > safeMaxTotalVertsAuto
            || metrics.maxRingVerts > safeMaxRingVertsAuto {
            if verbose {
                print("\(label) auto union skipped: safeCaps (rings=\(metrics.ringCount), totalVerts=\(metrics.totalVerts), maxRingVerts=\(metrics.maxRingVerts))")
            }
            return cleaned.rings.map { Polygon(outer: $0) }
        }
        let ringCount = metrics.ringCount
        let totalVerts = metrics.totalVerts
        let estimatedCost = Double(ringCount) * Double(max(1, totalVerts))
        let maxVertsCap = maxVertices
        let shouldUnion = totalVerts <= (maxVertsCap * 2)
        if verbose {
            print("\(label) union auto inputs rings \(ringCount) verts \(totalVerts) maxVertsCap \(maxVertsCap) simplifyTol \(simplifyTolerance) batch \(effectiveBatchSize) estCost \(String(format: "%.0f", estimatedCost))")
        }
        if !shouldUnion {
            if verbose {
                print("\(label) union auto -> never (reason: totalVerts \(totalVerts) > maxVertsCap * 2)")
            }
            return cleaned.rings.map { Polygon(outer: $0) }
        }
        if verbose {
            print("\(label) union auto -> always")
        }
        let isSilhouetteAttempt = (inputFilter == .silhouette) || (unionInput.count != cleaned.rings.count)
        let unioner = SimplifyingUnioner(
            base: base,
            simplifyTolerance: simplifyTolerance,
            maxVertices: maxVertices,
            areaEps: areaEps,
            minRingArea: minRingArea,
            weldEps: weldEps,
            edgeEps: edgeEps,
            batchSize: batchSize,
            inputFilter: inputFilter,
            silhouetteK: silhouetteK,
            silhouetteDropContained: silhouetteDropContained,
            dumpInputPath: dumpInputPath,
            verbose: verbose,
            label: label
        )
        if autoTimeBudgetMs <= 0 {
            return try unioner.union(subjectRings: unionInput)
        }
        let simplified = try simplifyRingsForUnion(
            unionInput,
            baseTolerance: (isSilhouetteAttempt ? 0.0 : simplifyTolerance),
            maxVertices: maxVertices,
            areaEps: areaEps,
            minRingArea: minRingArea,
            weldEps: weldEps,
            edgeEps: edgeEps,
            inputFilter: .none,
            silhouetteK: silhouetteK,
            silhouetteDropContained: silhouetteDropContained
        )
        if verbose {
            logCleanupStats(label: label, stats: simplified.cleanup)
            print("\(label) union simplify verts \(simplified.cleanup.tinyVertexCount) -> \(simplified.postCount)")
        }
        let batchResult = batchedUnionWithBudget(
            rings: simplified.rings,
            batchSize: effectiveBatchSize,
            unioner: base,
            overallBudgetMs: max(1, autoTimeBudgetMs),
            perBatchBudgetMs: 250,
            dumpPath: dumpInputPath,
            verbose: verbose,
            label: label
        )
        switch batchResult.reason {
        case .none:
            break
        case .batchTimeExceeded(let batch, let ms):
            if verbose {
                print("\(label) auto union bailed at batch \(batch): batchTime=\(String(format: "%.3f", Double(ms) / 1000.0))s")
            }
            return simplified.rings.map { Polygon(outer: $0) }
        case .overallBudgetExceeded:
            if verbose {
                print("\(label) auto union bailed: timeBudget")
            }
            return simplified.rings.map { Polygon(outer: $0) }
        }
        if batchResult.elapsedMs > autoTimeBudgetMs {
            if verbose {
                print("\(label) auto union bailed: timeBudget")
            }
            return simplified.rings.map { Polygon(outer: $0) }
        }
        let finalMetrics = ringMetrics(batchResult.rings)
        logUnionAdapterCall(label: label, batch: 0, metrics: finalMetrics)
        if let dumpInputPath {
            dumpUnionInputOnce(batchResult.rings, to: dumpInputPath)
        }
        return try base.union(subjectRings: batchResult.rings)
    }
}

private func cleanupRing(_ ring: Ring, areaEps: Double, weldEps: Double, edgeEps: Double) -> Ring? {
    var points = closeRingIfNeeded(ring)
    if points.count < 4 { return nil }
    points = weldPoints(points, epsilon: weldEps)
    points = removeShortEdges(points, epsilon: edgeEps)
    points = closeRingIfNeeded(points)
    if points.count < 4 { return nil }
    let area = abs(ringArea(points))
    if area < areaEps { return nil }
    return points
}

private func weldPoints(_ ring: Ring, epsilon: Double) -> Ring {
    guard let first = ring.first else { return ring }
    var result: [Point] = [first]
    result.reserveCapacity(ring.count)
    for point in ring.dropFirst() {
        if (point - result[result.count - 1]).length >= epsilon {
            result.append(point)
        }
    }
    if let last = result.last, (last - first).length < epsilon {
        result[result.count - 1] = first
    }
    return result
}

private func removeShortEdges(_ ring: Ring, epsilon: Double) -> Ring {
    guard ring.count >= 4 else { return ring }
    var result: [Point] = []
    result.reserveCapacity(ring.count)
    for index in 0..<ring.count {
        let prev = ring[(index - 1 + ring.count) % ring.count]
        let current = ring[index]
        if (current - prev).length >= epsilon || result.isEmpty {
            result.append(current)
        }
    }
    return result
}

private func ringArea(_ ring: Ring) -> Double {
    guard ring.count >= 3 else { return 0.0 }
    var sum = 0.0
    for i in 0..<(ring.count - 1) {
        let a = ring[i]
        let b = ring[i + 1]
        sum += (a.x * b.y) - (b.x * a.y)
    }
    return 0.5 * sum
}

private func ringBounds(_ ring: Ring) -> CGRect {
    guard let first = ring.first else { return .null }
    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y
    for point in ring.dropFirst() {
        minX = min(minX, point.x)
        maxX = max(maxX, point.x)
        minY = min(minY, point.y)
        maxY = max(maxY, point.y)
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

private func bboxContains(_ outer: CGRect, _ inner: CGRect, epsilon: Double) -> Bool {
    return inner.minX >= outer.minX - epsilon
        && inner.maxX <= outer.maxX + epsilon
        && inner.minY >= outer.minY - epsilon
        && inner.maxY <= outer.maxY + epsilon
}

private struct DedupeResult {
    let rings: [Ring]
    let droppedCount: Int
    let droppedVertexCount: Int
    let totalVertexCount: Int
}

func applySilhouetteFilter(
    _ rings: [Ring],
    k: Int,
    dropContained: Bool
) -> (rings: [Ring], stats: SilhouetteStats) {
    guard !rings.isEmpty else {
        return ([], SilhouetteStats(inputCount: 0, keptCount: 0, containedDropCount: 0))
    }
    let keepCount = max(1, min(k, rings.count))
    let sorted = rings.enumerated().sorted { lhs, rhs in
        let lhsArea = ringBounds(lhs.element).width * ringBounds(lhs.element).height
        let rhsArea = ringBounds(rhs.element).width * ringBounds(rhs.element).height
        if lhsArea == rhsArea { return lhs.offset < rhs.offset }
        return lhsArea > rhsArea
    }
    let kept = sorted.prefix(keepCount).map { $0.element }
    if !dropContained {
        return (kept, SilhouetteStats(inputCount: rings.count, keptCount: kept.count, containedDropCount: 0))
    }
    var filtered: [Ring] = []
    filtered.reserveCapacity(kept.count)
    var keptBounds: [CGRect] = []
    var containedDrop = 0
    for ring in kept {
        let candidateBounds = ringBounds(ring)
        var isContained = false
        for bounds in keptBounds {
            if bboxContains(bounds, candidateBounds, epsilon: 0.01) {
                isContained = true
                break
            }
        }
        if isContained {
            containedDrop += 1
            continue
        }
        filtered.append(ring)
        keptBounds.append(candidateBounds)
    }
    return (filtered, SilhouetteStats(inputCount: rings.count, keptCount: filtered.count, containedDropCount: containedDrop))
}

private func dedupeRingsByQuantizedPoints(_ rings: [Ring], tolerance: Double) -> DedupeResult {
    guard !rings.isEmpty else {
        return DedupeResult(rings: [], droppedCount: 0, droppedVertexCount: 0, totalVertexCount: 0)
    }
    var seen: Set<String> = []
    var deduped: [Ring] = []
    deduped.reserveCapacity(rings.count)
    var dropped = 0
    var droppedVerts = 0
    let totalVerts = rings.reduce(0) { $0 + $1.count }
    for ring in rings {
        let canonical = canonicalizeRing(ring, tolerance: tolerance)
        let key = canonical.key
        if seen.contains(key) {
            dropped += 1
            droppedVerts += ring.count
            continue
        }
        seen.insert(key)
        deduped.append(canonical.ring)
    }
    return DedupeResult(rings: deduped, droppedCount: dropped, droppedVertexCount: droppedVerts, totalVertexCount: totalVerts)
}

private func canonicalizeRing(_ ring: Ring, tolerance: Double) -> (ring: Ring, key: String) {
    var points = ring
    if points.count >= 3, points.first == points.last {
        points.removeLast()
    }
    if ringArea(points) > 0 {
        points.reverse()
    }
    var quantized: [(x: Int, y: Int)] = []
    quantized.reserveCapacity(points.count)
    for point in points {
        let qx = Int(round(point.x / tolerance))
        let qy = Int(round(point.y / tolerance))
        quantized.append((x: qx, y: qy))
    }
    var startIndex = 0
    if let first = quantized.first {
        var best = first
        for (index, value) in quantized.enumerated() {
            if value.x < best.x || (value.x == best.x && value.y < best.y) {
                best = value
                startIndex = index
            }
        }
    }
    let rotated = (0..<quantized.count).map { quantized[(startIndex + $0) % quantized.count] }
    var keyParts: [String] = []
    keyParts.reserveCapacity(rotated.count + 1)
    keyParts.append(String(rotated.count))
    for value in rotated {
        keyParts.append("\(value.x),\(value.y)")
    }
    let key = keyParts.joined(separator: ";")
    let rotatedPoints = (0..<points.count).map { points[(startIndex + $0) % points.count] }
    let closed = closeRingIfNeeded(rotatedPoints)
    return (closed, key)
}

private func batchedUnion(rings: [Ring], batchSize: Int, unioner: PolygonUnioning, dumpPath: String?, verbose: Bool = false, label: String = "") -> [Ring] {
    guard rings.count > batchSize else { return rings }
    var intermediates: [Ring] = []
    intermediates.reserveCapacity((rings.count / batchSize) + 1)
    var index = 0
    var batchIndex = 0
    while index < rings.count {
        let end = min(rings.count, index + batchSize)
        let chunk = Array(rings[index..<end])
        if let dumpPath, batchIndex == 0 {
            dumpUnionInputOnce(chunk, to: dumpPath)
        }
        let metrics = ringMetrics(chunk)
        logUnionAdapterCall(label: label, batch: batchIndex + 1, metrics: metrics)
        let batchStart = Date()
        if let unioned = try? unioner.union(subjectRings: chunk) {
            intermediates.append(contentsOf: unioned.map { $0.outer })
        } else {
            intermediates.append(contentsOf: chunk)
        }
        if verbose {
            let elapsed = Date().timeIntervalSince(batchStart)
            print("\(label) union batch \(batchIndex + 1) time \(String(format: "%.3f", elapsed))s -> \(intermediates.count) rings")
        }
        index = end
        batchIndex += 1
    }
    return intermediates
}

private enum AutoUnionBailReason {
    case none
    case batchTimeExceeded(batch: Int, ms: Int)
    case overallBudgetExceeded(ms: Int)
}

private func batchedUnionWithBudget(
    rings: [Ring],
    batchSize: Int,
    unioner: PolygonUnioning,
    overallBudgetMs: Int,
    perBatchBudgetMs: Int,
    dumpPath: String?,
    verbose: Bool = false,
    label: String = ""
) -> (rings: [Ring], reason: AutoUnionBailReason, batchesUsed: Int, elapsedMs: Int) {
    guard rings.count > batchSize else { return (rings, .none, 0, 0) }
    var intermediates: [Ring] = []
    intermediates.reserveCapacity((rings.count / batchSize) + 1)
    var index = 0
    var batchIndex = 0
    let overallStart = Date()
    while index < rings.count {
        let overallElapsedMs = Int(Date().timeIntervalSince(overallStart) * 1000.0)
        if overallElapsedMs > overallBudgetMs {
            return (rings, .overallBudgetExceeded(ms: overallElapsedMs), batchIndex, overallElapsedMs)
        }
        let end = min(rings.count, index + batchSize)
        let chunk = Array(rings[index..<end])
        if let dumpPath, batchIndex == 0 {
            dumpUnionInputOnce(chunk, to: dumpPath)
        }
        let metrics = ringMetrics(chunk)
        logUnionAdapterCall(label: label, batch: batchIndex + 1, metrics: metrics)
        let batchStart = Date()
        if let unioned = try? unioner.union(subjectRings: chunk) {
            intermediates.append(contentsOf: unioned.map { $0.outer })
        } else {
            intermediates.append(contentsOf: chunk)
        }
        let batchElapsedMs = Int(Date().timeIntervalSince(batchStart) * 1000.0)
        if verbose {
            print("\(label) union batch \(batchIndex + 1) time \(String(format: "%.3f", Double(batchElapsedMs) / 1000.0))s -> \(intermediates.count) rings")
        }
        if batchElapsedMs > perBatchBudgetMs {
            let overallElapsedMs = Int(Date().timeIntervalSince(overallStart) * 1000.0)
            return (rings, .batchTimeExceeded(batch: batchIndex + 1, ms: batchElapsedMs), batchIndex + 1, overallElapsedMs)
        }
        index = end
        batchIndex += 1
    }
    let totalElapsedMs = Int(Date().timeIntervalSince(overallStart) * 1000.0)
    return (intermediates, .none, batchIndex, totalElapsedMs)
}

private func defaultPreviewSamples(for quality: String?) -> Int {
    guard let quality else { return 256 }
    return (quality == "final") ? 512 : 256
}

private func previewFlattenTolerance(for quality: String?) -> Double {
    guard let quality else { return 1.0 }
    return (quality == "final") ? 0.25 : 1.0
}

do {
    try CLI().run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
    let stderr = FileHandle.standardError
    stderr.write(Data(("counterpoint-cli error: \(message)\n").utf8))
    stderr.write(Data("Usage: counterpoint-cli <path-to-spec.json>|- [--example [s-curve]] [--svg <outputPath>] [--svg-size WxH] [--padding N] [--quiet] [--bridges|--no-bridges] [--debug-samples|--debug-overlay] [--dump-samples <path>] [--centerline-only] [--stroke-preview] [--preview-samples N] [--preview-quality preview|final] [--preview-angle-mode absolute|relative] [--preview-angle-deg N] [--preview-width N] [--preview-height N] [--preview-nib-rotate-deg N] [--preview-union auto|never|always] [--final-union auto|never|always|trace] [--final-envelope direct] [--union-simplify-tol N] [--union-max-verts N] [--union-batch-size N] [--union-area-eps N] [--union-weld-eps N] [--union-edge-eps N] [--union-min-ring-area N] [--union-auto-time-budget-ms N] [--union-input-filter none|silhouette] [--union-silhouette-k N] [--union-silhouette-drop-contained 0|1] [--union-dump-input <path>] [--outline-fit none|simplify|bezier] [--fit-tolerance N] [--simplify-tolerance N] [--show-envelope] [--show-envelope-union] [--show-rays|--no-rays] [--view envelope,samples,rays,rails,caps,junctions,union,centerline,offset,alpha,ref-diff|all|none] [--alpha-probe-t N] [--alpha-demo N] [--alpha-debug] [--diff-resolution N] [--trace-alpha-window tmin tmax] [--trace-stroke <id>] [--trace-tmin N] [--trace-tmax N] [--dump-keyframes] [--cp-size N] [--angle-mode absolute|relative] [--quality preview|final] [--envelope-tol N] [--flatten-tol N] [--max-samples N]\n".utf8))
    stderr.write(Data("       counterpoint-cli scurve --svg <outputPath> [--angle-start N] [--angle-end N] [--size-start N] [--size-end N] [--aspect-start N] [--aspect-end N] [--offset-start N] [--offset-end N] [--width-start N] [--width-end N] [--height-start N] [--height-end N] [--alpha-start N] [--alpha-end N] [--angle-mode absolute|relative] [--samples N] [--quality preview|final] [--envelope-mode rails|union|direct] [--envelope-sides N] [--join round|bevel|miter] [--miter-limit N] [--outline-fit none|simplify|bezier] [--fit-tolerance N] [--simplify-tolerance N] [--view envelope,samples,rays,rails,caps,junctions,union,centerline,offset,alpha,ref-diff|all|none] [--dump-samples <path>] [--kink] [--no-centerline] [--verbose]\n".utf8))
    stderr.write(Data("       counterpoint-cli line --svg <outputPath> [--angle-start N] [--angle-end N] [--size-start N] [--size-end N] [--aspect-start N] [--aspect-end N] [--offset-start N] [--offset-end N] [--width-start N] [--width-end N] [--height-start N] [--height-end N] [--alpha-start N] [--alpha-end N] [--angle-mode absolute|relative] [--samples N] [--quality preview|final] [--envelope-mode rails|union|direct] [--envelope-sides N] [--join round|bevel|miter] [--miter-limit N] [--outline-fit none|simplify|bezier] [--fit-tolerance N] [--simplify-tolerance N] [--view envelope,samples,rays,rails,caps,junctions,union,centerline,offset,alpha,ref-diff|all|none] [--dump-samples <path>] [--kink] [--no-centerline] [--verbose]\n".utf8))
    stderr.write(Data("       counterpoint-cli showcase --out <dir> [--quality preview|final]\n".utf8))
    stderr.write(Data("       counterpoint-cli union-dump <input.json> [--svg out.svg] [--out out.json] [--keep-first N] [--drop-original-index N] [--drop-index N] [--keep-indices 0,1,2-5] [--cleanup-coincident-edges 0|1] [--cleanup-touching-edges 0|1] [--snap-tol N] [--touch-eps N] [--no-union|--cleanup-only] [--dump-after-cleanup <path>] [--dry-run] [--print-ring-original-index N]\n".utf8))
    exit(1)
}
