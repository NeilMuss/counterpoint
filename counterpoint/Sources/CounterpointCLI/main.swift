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

        let decoder = JSONDecoder()
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
        let outline = try useCase.generateOutline(for: spec, includeBridges: options.useBridges)

        if let svgPath = options.svgOutputPath {
            let builder = SVGPathBuilder()
            let debugOverlay = options.debugSamples ? makeDebugOverlay(spec: spec, options: options) : nil
            let svg = builder.svgDocument(for: outline, size: options.svgSize, padding: options.padding, debugOverlay: debugOverlay)
            do {
                try svg.write(to: URL(fileURLWithPath: svgPath), atomically: true, encoding: .utf8)
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

        let polygons: PolygonSet
        if config.view.contains(.envelope) {
            if config.envelopeMode == .union {
                polygons = geometry.unionPolygons
            } else {
                polygons = geometry.envelopeOutline.isEmpty ? [] : [Polygon(outer: geometry.envelopeOutline)]
            }
        } else {
            polygons = []
        }

        let overlay = SVGDebugOverlay(
            skeleton: geometry.centerline,
            stamps: config.view.contains(.samples) ? geometry.stampRings : [],
            bridges: [],
            samplePoints: geometry.samplePoints,
            tangentRays: geometry.tangentRays,
            angleRays: geometry.angleRays,
            envelopeLeft: config.view.contains(.rails) ? geometry.envelopeLeft : [],
            envelopeRight: config.view.contains(.rails) ? geometry.envelopeRight : [],
            envelopeOutline: config.view.contains(.envelope) ? geometry.envelopeOutline : [],
            showUnionOutline: config.view.contains(.union),
            unionPolygons: geometry.unionPolygons
        )

        let builder = SVGPathBuilder()
        let svg = builder.svgDocument(for: polygons, size: config.svgSize, padding: config.padding, debugOverlay: overlay)
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
    var quality: String?
    var showEnvelope: Bool?
    var showEnvelopeUnion: Bool
    var showRays: Bool?
    var counterpointSize: Double?
    var angleModeOverride: AngleMode?
    var envelopeTolerance: Double?
    var flattenTolerance: Double?
    var maxSamples: Int?
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
    var widthStart: Double?
    var widthEnd: Double?
    var heightStart: Double?
    var heightEnd: Double?
    var alphaStart: Double
    var alphaEnd: Double
    var angleMode: AngleMode
    var samplesPerSegment: Int
    var ellipseSegments: Int
    var envelopeSegments: Int
    var view: Set<ScurveView>
    var envelopeMode: EnvelopeMode
}

enum ScurveView: String {
    case envelope
    case samples
    case rays
    case rails
    case union
    case centerline
}

enum EnvelopeMode: String {
    case rails
    case union
}

struct ScurveGeometry {
    var envelopeLeft: [Point]
    var envelopeRight: [Point]
    var envelopeOutline: Ring
    var unionPolygons: PolygonSet
    var stampRings: [Ring]
    var samplePoints: [Point]
    var tangentRays: [(Point, Point)]
    var angleRays: [(Point, Point)]
    var centerline: [Point]
}

private func parseOptions(_ args: [String]) throws -> CLIOptions {
    var options = CLIOptions(inputPath: nil, exampleName: nil, svgOutputPath: nil, svgSize: nil, padding: 10.0, quiet: false, useBridges: true, debugSamples: false, quality: nil, showEnvelope: nil, showEnvelopeUnion: false, showRays: nil, counterpointSize: nil, angleModeOverride: nil, envelopeTolerance: nil, flattenTolerance: nil, maxSamples: nil)
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
        case "--bridges":
            options.useBridges = true
        case "--no-bridges":
            options.useBridges = false
        case "--debug-samples":
            options.debugSamples = true
        case "--debug-overlay":
            options.debugSamples = true
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
    var widthStart: Double?
    var widthEnd: Double?
    var heightStart: Double?
    var heightEnd: Double?
    var alphaStart = 0.0
    var alphaEnd = 0.0
    var angleMode: AngleMode = .absolute
    var samplesPerSegment: Int?
    var quality: String?
    var view: Set<ScurveView> = [.envelope, .centerline]
    var envelopeMode: EnvelopeMode = .union
    var envelopeSegments: Int = 48

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
            samplesPerSegment = value
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
            guard index + 1 < args.count else { throw CLIError.invalidArguments("--envelope-mode requires rails|union") }
            let mode = args[index + 1].lowercased()
            guard let parsed = EnvelopeMode(rawValue: mode) else {
                throw CLIError.invalidArguments("--envelope-mode must be rails|union")
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
        default:
            break
        }
        index += 1
    }

    let resolvedSamples: Int
    let ellipseSegments: Int
    if let samplesPerSegment {
        resolvedSamples = max(4, samplesPerSegment)
        ellipseSegments = 24
    } else if quality == "final" {
        resolvedSamples = 200
        ellipseSegments = 64
    } else {
        resolvedSamples = 60
        ellipseSegments = 24
    }

    guard let svgOutputPath else {
        throw CLIError.invalidArguments("scurve requires --svg <outputPath>")
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
        widthStart: widthStart,
        widthEnd: widthEnd,
        heightStart: heightStart,
        heightEnd: heightEnd,
        alphaStart: alphaStart,
        alphaEnd: alphaEnd,
        angleMode: angleMode,
        samplesPerSegment: resolvedSamples,
        ellipseSegments: ellipseSegments,
        envelopeSegments: envelopeSegments,
        view: view,
        envelopeMode: envelopeMode
    )
}

private func parseViewModes(_ text: String) throws -> Set<ScurveView> {
    let raw = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    if raw.contains("all") {
        return Set([.envelope, .samples, .rays, .rails, .union, .centerline])
    }
    if raw.contains("none") {
        return []
    }
    var result: Set<ScurveView> = []
    for item in raw where !item.isEmpty {
        guard let mode = ScurveView(rawValue: item) else {
            throw CLIError.invalidArguments("--view must be envelope|samples|rays|rails|union|centerline|all|none")
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
    let path = globalScurvePath()
    let domain = PathDomain(path: path, samplesPerSegment: config.samplesPerSegment)
    let angleField = ParamField.linearDegrees(startDeg: config.angleStart, endDeg: config.angleEnd)

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
    var samplePoints: [Point] = []
    var tangentRays: [(Point, Point)] = []
    var angleRays: [(Point, Point)] = []
    var stampRings: [Ring] = []

    let bounds = domain.samples.reduce(CGRect.null) { rect, sample in
        rect.union(CGRect(x: sample.point.x, y: sample.point.y, width: 0, height: 0))
    }
    let diag = hypot(bounds.width, bounds.height)
    let rayLength = max(8.0, diag * 0.05)

    let showRays = config.view.contains(.rays)
    let showSamples = config.view.contains(.samples)
    let showRails = config.view.contains(.rails)
    let showEnvelope = config.view.contains(.envelope)
    let envelopeUsesUnion = config.envelopeMode == .union
    let needsStamps = showSamples || config.view.contains(.union) || (showEnvelope && envelopeUsesUnion)

    let stamping = CounterpointStamping()
    for sample in domain.samples {
        let biasedS = applyBias(s: sample.s, alphaStart: config.alphaStart, alphaEnd: config.alphaEnd)
        let angleDeg = angleField.evaluate(biasedS)
        let dir = AngleMath.directionVector(unitTangent: sample.unitTangent, angleDegrees: angleDeg, mode: config.angleMode)
        let dirUnit = dir.normalized() ?? Point(x: 1, y: 0)
        let normal = dirUnit.leftNormal()

        let width = widthField.evaluate(biasedS)
        let height = heightField.evaluate(biasedS)
        let halfWidth = width * 0.5
        let halfHeight = height * 0.5

        if showEnvelope || showRails {
            let leftOffset = orientedEllipseSupportPoint(direction: normal, axis: dirUnit, normal: normal, a: halfWidth, b: halfHeight)
            let rightOffset = orientedEllipseSupportPoint(direction: normal * -1.0, axis: dirUnit, normal: normal, a: halfWidth, b: halfHeight)
            envelopeLeft.append(sample.point + leftOffset)
            envelopeRight.append(sample.point + rightOffset)
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
                    t: sample.s,
                    point: sample.point,
                    tangentAngle: tangentAngle,
                    width: width,
                    height: height,
                    theta: angleRadians,
                    effectiveRotation: effectiveRotation
                ),
                shape: .ellipse(segments: segments)
            )
            stampRings.append(stamped)
        }

        if config.view.contains(.centerline) {
            samplePoints.append(sample.point)
        }
        if showRays {
            let angleEnd = sample.point + dirUnit * rayLength
            let tangentEnd = sample.point + sample.unitTangent * rayLength
            angleRays.append((sample.point, angleEnd))
            tangentRays.append((sample.point, tangentEnd))
        }
    }

    var envelopeOutline: Ring = []
    if showEnvelope, !envelopeLeft.isEmpty, envelopeLeft.count == envelopeRight.count {
        envelopeOutline = closeRingIfNeeded(envelopeLeft + envelopeRight.reversed())
    }

    var unionPolygons: PolygonSet = []
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
        unionPolygons: unionPolygons,
        stampRings: stampRings,
        samplePoints: samplePoints,
        tangentRays: tangentRays,
        angleRays: angleRays,
        centerline: centerline
    )
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
        samplePoints = domain.samples.map { $0.point }
        if showRays {
            tangentRays = domain.samples.map { sample in
                let end = sample.point + sample.unitTangent * rayLength
                return (sample.point, end)
            }
            angleRays = domain.samples.map { sample in
                let angle = angleField.evaluate(sample.s)
                let dir = AngleMath.directionVector(unitTangent: sample.unitTangent, angleDegrees: angle, mode: spec.angleMode)
                let end = sample.point + dir * rayLength
                return (sample.point, end)
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

                envelopeLeft.append(sample.point + leftOffset)
                envelopeRight.append(sample.point + rightOffset)
            }

            if !envelopeLeft.isEmpty && envelopeRight.count == envelopeLeft.count {
                envelopeOutline = envelopeLeft + envelopeRight.reversed()
                envelopeOutline = closeRingIfNeeded(envelopeOutline)
            }
        }
    }

    return SVGDebugOverlay(
        skeleton: polyline.points,
        stamps: stampRings,
        bridges: bridgeRings,
        samplePoints: samplePoints,
        tangentRays: tangentRays,
        angleRays: angleRays,
        envelopeLeft: envelopeLeft,
        envelopeRight: envelopeRight,
        envelopeOutline: envelopeOutline,
        showUnionOutline: showUnionOutline,
        unionPolygons: nil
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

do {
    try CLI().run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
    let stderr = FileHandle.standardError
    stderr.write(Data(("counterpoint-cli error: \(message)\n").utf8))
    stderr.write(Data("Usage: counterpoint-cli <path-to-spec.json>|- [--example [s-curve]] [--svg <outputPath>] [--svg-size WxH] [--padding N] [--quiet] [--bridges|--no-bridges] [--debug-samples|--debug-overlay] [--show-envelope] [--show-envelope-union] [--show-rays|--no-rays] [--cp-size N] [--angle-mode absolute|relative] [--quality preview|final] [--envelope-tol N] [--flatten-tol N] [--max-samples N]\n".utf8))
    stderr.write(Data("       counterpoint-cli scurve --svg <outputPath> [--angle-start N] [--angle-end N] [--size-start N] [--size-end N] [--aspect-start N] [--aspect-end N] [--width-start N] [--width-end N] [--height-start N] [--height-end N] [--alpha-start N] [--alpha-end N] [--angle-mode absolute|relative] [--samples N] [--quality preview|final] [--envelope-mode rails|union] [--envelope-sides N] [--view envelope,samples,rays,rails,union,centerline] [--no-centerline]\n".utf8))
    exit(1)
}
