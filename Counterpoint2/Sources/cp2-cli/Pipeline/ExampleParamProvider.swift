import Foundation
import CP2Geometry

struct ExampleParamProvider: StrokeParamProvider {
    func makeParamFuncs(options: CLIOptions, exampleName: String?, sweepWidth: Double) -> StrokeParamFuncs {
        let alphaStartGT = options.alphaStartGT
        let example = exampleName?.lowercased()
        
        let alphaEndValue: Double = {
            if example == "j" {
                return options.alphaEnd ?? -0.35
            }
            if example == "line_end_ramp" {
                return options.alphaEnd ?? 0.0
            }
            return options.alphaEnd ?? 0.0
        }()

        let widthAtT: (Double) -> Double
        let thetaAtT: (Double) -> Double
        let alphaAtT: (Double) -> Double

        if example == "j" || example == "j_serif_only" {
            widthAtT = { t in
                let clamped = max(0.0, min(1.0, t))
                let midT = 0.45
                let start = 16.0
                let mid = 22.0
                let end = 16.0
                if clamped <= midT {
                    let u = clamped / midT
                    return start + (mid - start) * u
                }
                let u = (clamped - midT) / (1.0 - midT)
                return mid + (end - mid) * u
            }
            thetaAtT = { t in
                let clamped = max(0.0, min(1.0, t))
                let midT = 0.5
                let start = 12.0
                let mid = 4.0
                let end = 0.0
                let deg: Double
                if clamped <= midT {
                    let u = clamped / midT
                    deg = start + (mid - start) * u
                } else {
                    let u = (clamped - midT) / (1.0 - midT)
                    deg = mid + (end - mid) * u
                }
                return deg * Double.pi / 180.0
            }
            alphaAtT = { t in
                if t < alphaStartGT {
                    return 0.0
                }
                let phase = (t - alphaStartGT) / max(1.0e-12, 1.0 - alphaStartGT)
                return alphaEndValue * max(0.0, min(1.0, phase))
            }
        } else if example == "line_end_ramp" {
            let rampStart = options.widthRampStartGT
            let start = options.widthStart
            let end = options.widthEnd
            widthAtT = { t in
                if t < rampStart {
                    return start
                }
                let phase = (t - rampStart) / max(1.0e-12, 1.0 - rampStart)
                return start + (end - start) * max(0.0, min(1.0, phase))
            }
            thetaAtT = { _ in 0.0 }
            alphaAtT = { t in
                if t < alphaStartGT {
                    return 0.0
                }
                let phase = (t - alphaStartGT) / max(1.0e-12, 1.0 - alphaStartGT)
                return alphaEndValue * max(0.0, min(1.0, phase))
            }
        } else if example == "poly3" {
            widthAtT = { t in
                let clamped = max(0.0, min(1.0, t))
                let midT = 0.5
                let start = 16.0
                let mid = 28.0
                let end = 16.0
                if clamped <= midT {
                    let u = clamped / midT
                    return start + (mid - start) * u
                }
                let u = (clamped - midT) / (1.0 - midT)
                return mid + (end - mid) * u
            }
            thetaAtT = { _ in 0.0 }
            alphaAtT = { t in
                if t < alphaStartGT {
                    return 0.0
                }
                let phase = (t - alphaStartGT) / max(1.0e-12, 1.0 - alphaStartGT)
                return alphaEndValue * max(0.0, min(1.0, phase))
            }
        } else {
            widthAtT = { _ in sweepWidth }
            thetaAtT = { _ in 0.0 }
            alphaAtT = { _ in 0.0 }
        }

        let usesVariableWidthAngleAlpha = (example == "j" || example == "j_serif_only" || example == "poly3" || example == "line_end_ramp")

        return StrokeParamFuncs(
            alphaStartGT: alphaStartGT,
            alphaEndValue: alphaEndValue,
            widthAtT: widthAtT,
            thetaAtT: thetaAtT,
            alphaAtT: alphaAtT,
            usesVariableWidthAngleAlpha: usesVariableWidthAngleAlpha
        )
    }
}
