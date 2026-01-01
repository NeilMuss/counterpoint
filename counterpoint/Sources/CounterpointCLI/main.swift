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
            inputData = exampleSpecData(named: exampleName.isEmpty ? nil : exampleName)
        } else if let path = options.inputPath, path != "-" {
            inputData = try Data(contentsOf: URL(fileURLWithPath: path))
        } else {
            inputData = readStdin()
        }

        let decoder = JSONDecoder()
        let spec = try decoder.decode(StrokeSpec.self, from: inputData)
        try StrokeSpecValidator().validate(spec)

        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: IOverlayPolygonUnionAdapter()
        )
        let outline = try useCase.generateOutline(for: spec, includeBridges: options.useBridges)

        if let svgPath = options.svgOutputPath {
            let builder = SVGPathBuilder()
            let svg = builder.svgDocument(for: outline, size: options.svgSize, padding: options.padding)
            try svg.write(to: URL(fileURLWithPath: svgPath), atomically: true, encoding: .utf8)
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
            "baseSpacing": 2.0,
            "flatnessTolerance": 0.5,
            "rotationThresholdDegrees": 5.0,
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
}

private struct CLIOptions {
    var inputPath: String?
    var exampleName: String?
    var svgOutputPath: String?
    var svgSize: CGSize?
    var padding: Double
    var quiet: Bool
    var useBridges: Bool
}

private func parseOptions(_ args: [String]) throws -> CLIOptions {
    var options = CLIOptions(inputPath: nil, exampleName: nil, svgOutputPath: nil, svgSize: nil, padding: 10.0, quiet: false, useBridges: true)
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

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        }
    }
}

do {
    try CLI().run()
} catch {
    let message = (error as NSError).localizedDescription
    let stderr = FileHandle.standardError
    stderr.write(Data(("counterpoint-cli error: \(message)\n").utf8))
    stderr.write(Data("Usage: counterpoint-cli <path-to-spec.json>|- [--example [s-curve]] [--svg <outputPath>] [--svg-size WxH] [--padding N] [--quiet] [--bridges|--no-bridges]\n".utf8))
    exit(1)
}
