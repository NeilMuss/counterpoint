import Foundation
import CP2Geometry
import CP2Skeleton

struct SweepPlan {
    var sweepSampleCount: Int
    var sweepWidth: Double
    var sweepHeight: Double
    var sweepAngle: Double
    var paramSamplesPerSegment: Int
    var alphaStartGT: Double
    var alphaEndValue: Double
    var baselineWidth: Double
    var widthScale: Double
    var widthAtT: (Double) -> Double
    var thetaAtT: (Double) -> Double
    var alphaAtT: (Double) -> Double
    var warpT: (Double) -> Double
    var scaledWidthAtT: (Double) -> Double
    var sweepGT: [Double]
    var widths: [Double]
}

func makeSweepPlan(
    options: CLIOptions,
    exampleName: String?,
    baselineWidth: Double,
    sweepWidth: Double,
    sweepHeight: Double,
    sweepSampleCount: Int
) -> SweepPlan {
    let paramSamplesPerSegment = options.arcSamples
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

    let sweepGT: [Double] = (0..<sweepSampleCount).map {
        Double($0) / Double(max(1, sweepSampleCount - 1))
    }
    
    let warpT: (Double) -> Double = { t in
        let alphaValue = alphaAtT(t)
        if t <= alphaStartGT || abs(alphaValue) <= Epsilon.defaultValue {
            return t
        }
        let span = max(Epsilon.defaultValue, 1.0 - alphaStartGT)
        let phase = max(0.0, min(1.0, (t - alphaStartGT) / span))
        let exponent = max(0.05, 1.0 + alphaValue)
        let biased = pow(phase, exponent)
        return alphaStartGT + biased * span
    }
    
    let widths = sweepGT.map { widthAtT(warpT($0)) }
    let meanWidth = widths.reduce(0.0, +) / Double(max(1, widths.count))
    let widthScale = (options.normalizeWidth && options.example?.lowercased() == "j" && meanWidth > Epsilon.defaultValue)
        ? (baselineWidth / meanWidth)
        : 1.0
        
    let scaledWidthAtT: (Double) -> Double = { t in
        widthAtT(t) * widthScale
    }

    return SweepPlan(
        sweepSampleCount: sweepSampleCount,
        sweepWidth: sweepWidth,
        sweepHeight: sweepHeight,
        sweepAngle: 0.0,
        paramSamplesPerSegment: paramSamplesPerSegment,
        alphaStartGT: alphaStartGT,
        alphaEndValue: alphaEndValue,
        baselineWidth: baselineWidth,
        widthScale: widthScale,
        widthAtT: widthAtT,
        thetaAtT: thetaAtT,
        alphaAtT: alphaAtT,
        warpT: warpT,
        scaledWidthAtT: scaledWidthAtT,
        sweepGT: sweepGT,
        widths: widths
    )
}
