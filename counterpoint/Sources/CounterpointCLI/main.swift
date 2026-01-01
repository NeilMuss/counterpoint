import Foundation
import CoreGraphics
import Domain
import UseCases
import Adapters

struct CLI {
    func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
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
        try StrokeSpecValidator().validate(spec)

        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: IOverlayPolygonUnionAdapter()
        )
        let outline = try useCase.generateOutline(for: spec, includeBridges: options.useBridges)

        if let svgPath = options.svgOutputPath {
            let builder = SVGPathBuilder()
            let debugOverlay = options.debugSamples ? makeDebugOverlay(spec: spec) : nil
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

    private func exampleSpecData(named name: String?) -> Data {
        let normalized = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized?.lowercased() {
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

private struct CLIOptions {
    var inputPath: String?
    var exampleName: String?
    var svgOutputPath: String?
    var svgSize: CGSize?
    var padding: Double
    var quiet: Bool
    var useBridges: Bool
    var debugSamples: Bool
    var quality: String?
    var envelopeTolerance: Double?
    var flattenTolerance: Double?
    var maxSamples: Int?
}

private func parseOptions(_ args: [String]) throws -> CLIOptions {
    var options = CLIOptions(inputPath: nil, exampleName: nil, svgOutputPath: nil, svgSize: nil, padding: 10.0, quiet: false, useBridges: true, debugSamples: false, quality: nil, envelopeTolerance: nil, flattenTolerance: nil, maxSamples: nil)
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

private func makeDebugOverlay(spec: StrokeSpec) -> SVGDebugOverlay {
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

    return SVGDebugOverlay(
        skeleton: polyline.points,
        stamps: stampRings,
        bridges: bridgeRings
    )
}

do {
    try CLI().run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
    let stderr = FileHandle.standardError
    stderr.write(Data(("counterpoint-cli error: \(message)\n").utf8))
    stderr.write(Data("Usage: counterpoint-cli <path-to-spec.json>|- [--example [s-curve]] [--svg <outputPath>] [--svg-size WxH] [--padding N] [--quiet] [--bridges|--no-bridges] [--debug-samples] [--quality preview|final] [--envelope-tol N] [--flatten-tol N] [--max-samples N]\n".utf8))
    exit(1)
}
