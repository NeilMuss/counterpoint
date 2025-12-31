import Foundation
import Domain
import UseCases
import Adapters

struct CLI {
    func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let inputData: Data

        if args.contains("--example") {
            inputData = exampleSpecData()
        } else if let path = args.first, path != "-" {
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
        let outline = useCase.generateOutline(for: spec)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = try encoder.encode(outline)

        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private func readStdin() -> Data {
        let stdin = FileHandle.standardInput
        return stdin.readDataToEndOfFile()
    }

    private func exampleSpecData() -> Data {
        let json = """
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
        return Data(json.utf8)
    }
}

do {
    try CLI().run()
} catch {
    let message = (error as NSError).localizedDescription
    let stderr = FileHandle.standardError
    stderr.write(Data(("counterpoint-cli error: \(message)\n").utf8))
    stderr.write(Data("Usage: counterpoint-cli <path-to-spec.json>|- [--example]\n".utf8))
    exit(1)
}
