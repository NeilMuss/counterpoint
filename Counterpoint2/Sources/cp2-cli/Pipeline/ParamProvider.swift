import Foundation

struct StrokeParamFuncs {
    var alphaStartGT: Double
    var alphaEndValue: Double
    var widthAtT: (Double) -> Double
    var thetaAtT: (Double) -> Double
    var alphaAtT: (Double) -> Double
    var usesVariableWidthAngleAlpha: Bool
}

protocol StrokeParamProvider {
    func makeParamFuncs(options: CLIOptions, exampleName: String?, sweepWidth: Double) -> StrokeParamFuncs
}
