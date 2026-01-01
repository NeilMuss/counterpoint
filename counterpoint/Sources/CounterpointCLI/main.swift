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
        showUnionOutline: showUnionOutline
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
    exit(1)
}
