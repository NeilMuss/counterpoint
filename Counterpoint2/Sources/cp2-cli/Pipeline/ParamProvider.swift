import Foundation

struct StrokeParamFuncs {
    var alphaStartGT: Double
    var alphaEndValue: Double
    var widthAtT: (Double) -> Double
    var widthLeftAtT: (Double) -> Double
    var widthRightAtT: (Double) -> Double
    var widthLeftSegmentAlphaAtT: (Double) -> Double
    var widthRightSegmentAlphaAtT: (Double) -> Double
    var thetaAtT: (Double) -> Double
    var offsetAtT: (Double) -> Double
    var alphaAtT: (Double) -> Double
    var usesVariableWidthAngleAlpha: Bool
    var angleMode: AngleMode
}

protocol StrokeParamProvider {
    func makeParamFuncs(options: CLIOptions, exampleName: String?, sweepWidth: Double) -> StrokeParamFuncs
}
