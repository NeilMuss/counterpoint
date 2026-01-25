import Foundation
import CP2Geometry
import CP2Skeleton

struct SweepPlan {
    var sweepSampleCount: Int
    var sweepWidth: Double
    var sweepHeight: Double
    var sweepAngle: Double
    var usesVariableWidthAngleAlpha: Bool
    var paramSamplesPerSegment: Int
    var alphaStartGT: Double
    var alphaEndValue: Double
    var baselineWidth: Double
    var widthScale: Double
    var widthAtT: (Double) -> Double
    var widthLeftAtT: (Double) -> Double
    var widthRightAtT: (Double) -> Double
    var thetaAtT: (Double) -> Double
    var offsetAtT: (Double) -> Double
    var alphaAtT: (Double) -> Double
    var warpT: (Double) -> Double
    var scaledWidthAtT: (Double) -> Double
    var scaledWidthLeftAtT: (Double) -> Double
    var scaledWidthRightAtT: (Double) -> Double
    var sweepGT: [Double]
    var widths: [Double]
    var angleMode: AngleMode
}

func makeSweepPlan(
    options: CLIOptions,
    funcs: StrokeParamFuncs,
    baselineWidth: Double,
    sweepWidth: Double,
    sweepHeight: Double,
    sweepSampleCount: Int
) -> SweepPlan {
    let sweepGT: [Double] = (0..<sweepSampleCount).map {
        Double($0) / Double(max(1, sweepSampleCount - 1))
    }
    
    let warpT: (Double) -> Double = { t in
        let alphaValue = funcs.alphaAtT(t)
        if t <= funcs.alphaStartGT || abs(alphaValue) <= Epsilon.defaultValue {
            return t
        }
        let span = max(Epsilon.defaultValue, 1.0 - funcs.alphaStartGT)
        let phase = max(0.0, min(1.0, (t - funcs.alphaStartGT) / span))
        let exponent = max(0.05, 1.0 + alphaValue)
        let biased = pow(phase, exponent)
        return funcs.alphaStartGT + biased * span
    }
    
    let widths = sweepGT.map { funcs.widthAtT(warpT($0)) }
    let meanWidth = widths.reduce(0.0, +) / Double(max(1, widths.count))
    let widthScale = (options.normalizeWidth && options.example?.lowercased() == "j" && meanWidth > Epsilon.defaultValue)
        ? (baselineWidth / meanWidth)
        : 1.0
        
    let scaledWidthAtT: (Double) -> Double = { t in
        funcs.widthAtT(t) * widthScale
    }
    let scaledWidthLeftAtT: (Double) -> Double = { t in
        funcs.widthLeftAtT(t) * widthScale
    }
    let scaledWidthRightAtT: (Double) -> Double = { t in
        funcs.widthRightAtT(t) * widthScale
    }

    return SweepPlan(
        sweepSampleCount: sweepSampleCount,
        sweepWidth: sweepWidth,
        sweepHeight: sweepHeight,
        sweepAngle: 0.0,
        usesVariableWidthAngleAlpha: funcs.usesVariableWidthAngleAlpha,
        paramSamplesPerSegment: options.arcSamples,
        alphaStartGT: funcs.alphaStartGT,
        alphaEndValue: funcs.alphaEndValue,
        baselineWidth: baselineWidth,
        widthScale: widthScale,
        widthAtT: funcs.widthAtT,
        widthLeftAtT: funcs.widthLeftAtT,
        widthRightAtT: funcs.widthRightAtT,
        thetaAtT: funcs.thetaAtT,
        offsetAtT: funcs.offsetAtT,
        alphaAtT: funcs.alphaAtT,
        warpT: warpT,
        scaledWidthAtT: scaledWidthAtT,
        scaledWidthLeftAtT: scaledWidthLeftAtT,
        scaledWidthRightAtT: scaledWidthRightAtT,
        sweepGT: sweepGT,
        widths: widths,
        angleMode: funcs.angleMode
    )
}
