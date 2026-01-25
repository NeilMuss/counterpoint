import Foundation

struct SpecParamProvider: StrokeParamProvider {
    let params: StrokeParams

    func makeParamFuncs(options: CLIOptions, exampleName: String?, sweepWidth: Double) -> StrokeParamFuncs {
        let alphaStartGT = options.alphaStartGT
        let angleMode = params.angleMode ?? .relative
        let alphaEndValue = options.alphaEnd ?? 0.0

        let widthAtT: (Double) -> Double = { t in
            if let width = params.width { return width.eval(t: t) }
            return sweepWidth
        }
        let thetaAtT: (Double) -> Double = { t in
            if let theta = params.theta { return theta.eval(t: t) * Double.pi / 180.0 }
            return 0.0
        }
        let offsetAtT: (Double) -> Double = { t in
            if let offset = params.offset { return offset.eval(t: t) }
            return 0.0
        }
        let alphaAtT: (Double) -> Double = { t in
            if let alpha = params.alpha { return alpha.eval(t: t) }
            if t < alphaStartGT { return 0.0 }
            let phase = (t - alphaStartGT) / max(1.0e-12, 1.0 - alphaStartGT)
            return alphaEndValue * max(0.0, min(1.0, phase))
        }

        let usesVariableWidthAngleAlpha = params.width != nil || params.theta != nil || params.offset != nil || params.alpha != nil

        return StrokeParamFuncs(
            alphaStartGT: alphaStartGT,
            alphaEndValue: alphaEndValue,
            widthAtT: widthAtT,
            thetaAtT: thetaAtT,
            offsetAtT: offsetAtT,
            alphaAtT: alphaAtT,
            usesVariableWidthAngleAlpha: usesVariableWidthAngleAlpha,
            angleMode: angleMode
        )
    }
}
