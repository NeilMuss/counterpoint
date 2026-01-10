import Foundation

public struct Interpolation: Codable, Equatable {
    public var alpha: Double

    public init(alpha: Double) {
        self.alpha = alpha
    }
}

public struct Keyframe: Codable, Equatable {
    public var t: Double
    public var value: Double
    public var interpolationToNext: Interpolation?

    public init(t: Double, value: Double, interpolationToNext: Interpolation? = nil) {
        self.t = t
        self.value = value
        self.interpolationToNext = interpolationToNext
    }
}

public struct ParamTrack: Codable, Equatable {
    public var keyframes: [Keyframe]

    public init(keyframes: [Keyframe]) {
        self.keyframes = keyframes.sorted { $0.t < $1.t }
    }

    public static func constant(_ value: Double) -> ParamTrack {
        ParamTrack(keyframes: [Keyframe(t: 0.0, value: value), Keyframe(t: 1.0, value: value)])
    }

    public var minValue: Double? {
        keyframes.map { $0.value }.min()
    }
}

public protocol ParamEvaluating {
    func evaluate(_ track: ParamTrack, at t: Double) -> Double
    func evaluateAngle(_ track: ParamTrack, at t: Double) -> Double
}

public struct ParamEvaluationDebug: Equatable {
    public let t: Double
    public let segmentIndex: Int
    public let t0: Double
    public let t1: Double
    public let v0: Double
    public let v1: Double
    public let alphaFromStart: Double?
    public let alphaFromEnd: Double?
    public let alphaUsed: Double
    public let alphaWasNil: Bool
    public let uRaw: Double
    public let uBiased: Double
    public let value: Double
}

public struct DefaultParamEvaluator: ParamEvaluating {
    public static var enableAlphaMonotonicityCheck = false
    public static var alphaMonotonicityVerbose = false

    public init() {}

    public func evaluate(_ track: ParamTrack, at t: Double) -> Double {
        interpolate(track, at: t) { start, end, alpha in
            start + (end - start) * alpha
        }
    }

    public func evaluateAngle(_ track: ParamTrack, at t: Double) -> Double {
        interpolate(track, at: t) { start, end, alpha in
            let delta = AngleMath.shortestDelta(from: start, to: end)
            return start + delta * alpha
        }
    }

    private func interpolate(_ track: ParamTrack, at t: Double, _ interp: (Double, Double, Double) -> Double) -> Double {
        guard let first = track.keyframes.first else { return 0.0 }
        if t <= first.t { return first.value }
        guard let last = track.keyframes.last else { return first.value }
        if t >= last.t { return last.value }

        for index in 0..<(track.keyframes.count - 1) {
            let a = track.keyframes[index]
            let b = track.keyframes[index + 1]
            if t >= a.t && t <= b.t {
                let span = b.t - a.t
                var alpha = span == 0 ? 0.0 : (t - a.t) / span
                let alphaFromStart = a.interpolationToNext?.alpha
                if let bias = alphaFromStart {
                    if DefaultParamEvaluator.enableAlphaMonotonicityCheck {
                        let report = DefaultParamEvaluator.biasSampleReport(bias: bias)
                        if !report.monotone {
                            if DefaultParamEvaluator.alphaMonotonicityVerbose {
                                let samples = report.samples.map { String(format: "%.6f", $0) }.joined(separator: ", ")
                                DefaultParamEvaluator.writeWarning("alpha bias non-monotone; falling back to linear. bias=\(String(format: "%.6f", bias)) samples=[\(samples)] min=\(String(format: "%.6f", report.minValue)) max=\(String(format: "%.6f", report.maxValue))")
                            }
                        } else {
                            alpha = biasCurve(alpha, bias: bias)
                        }
                    } else {
                        alpha = biasCurve(alpha, bias: bias)
                    }
                }
                return interp(a.value, b.value, alpha)
            }
        }
        return last.value
    }

    public func debugEvaluate(_ track: ParamTrack, at t: Double) -> ParamEvaluationDebug? {
        guard let first = track.keyframes.first else { return nil }
        if t <= first.t {
            return ParamEvaluationDebug(
                t: t,
                segmentIndex: 0,
                t0: first.t,
                t1: first.t,
                v0: first.value,
                v1: first.value,
                alphaFromStart: nil,
                alphaFromEnd: nil,
                alphaUsed: 0.0,
                alphaWasNil: true,
                uRaw: 0.0,
                uBiased: 0.0,
                value: first.value
            )
        }
        guard let last = track.keyframes.last else { return nil }
        if t >= last.t {
            let index = max(0, track.keyframes.count - 1)
            return ParamEvaluationDebug(
                t: t,
                segmentIndex: index,
                t0: last.t,
                t1: last.t,
                v0: last.value,
                v1: last.value,
                alphaFromStart: nil,
                alphaFromEnd: nil,
                alphaUsed: 0.0,
                alphaWasNil: true,
                uRaw: 1.0,
                uBiased: 1.0,
                value: last.value
            )
        }

        for index in 0..<(track.keyframes.count - 1) {
            let a = track.keyframes[index]
            let b = track.keyframes[index + 1]
            if t >= a.t && t <= b.t {
                let span = b.t - a.t
                let uRaw = span == 0 ? 0.0 : (t - a.t) / span
                let alphaFromStart = a.interpolationToNext?.alpha
                let alphaFromEnd = b.interpolationToNext?.alpha
                let alphaUsed = alphaFromStart ?? 0.0
                let alphaWasNil = alphaFromStart == nil
                let uBiased = alphaWasNil ? uRaw : biasCurve(uRaw, bias: alphaUsed)
                let value = a.value + (b.value - a.value) * uBiased
                return ParamEvaluationDebug(
                    t: t,
                    segmentIndex: index,
                    t0: a.t,
                    t1: b.t,
                    v0: a.value,
                    v1: b.value,
                    alphaFromStart: alphaFromStart,
                    alphaFromEnd: alphaFromEnd,
                    alphaUsed: alphaUsed,
                    alphaWasNil: alphaWasNil,
                    uRaw: uRaw,
                    uBiased: uBiased,
                    value: value
                )
            }
        }
        return nil
    }

    private func biasCurve(_ t: Double, bias: Double) -> Double {
        DefaultParamEvaluator.biasCurveValue(t, bias: bias)
    }

    public static func biasCurveValue(_ t: Double, bias: Double) -> Double {
        let maxAlpha = 4.0
        let clampedBias = max(-maxAlpha, min(maxAlpha, bias))
        if abs(clampedBias) < 1.0e-9 { return t }

        let clampedT = ScalarMath.clamp01(t)
        let magnitude = abs(clampedBias)
        let exponent: Double
        if magnitude <= 1.0 {
            exponent = 1.0 + magnitude * 0.25
        } else {
            exponent = 1.25 + (magnitude - 1.0) * 1.5
        }

        if clampedBias > 0.0 {
            return pow(clampedT, exponent)
        }
        return 1.0 - pow(1.0 - clampedT, exponent)
    }

    private static func biasSampleReport(bias: Double) -> BiasSampleReport {
        let sampleUs: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let samples = sampleUs.map { biasCurveValue($0, bias: bias) }
        var monotone = true
        let minValue = samples.min() ?? 0.0
        let maxValue = samples.max() ?? 0.0
        let epsilon = 1.0e-9
        for index in 1..<samples.count {
            if samples[index] + epsilon < samples[index - 1] {
                monotone = false
                break
            }
        }
        if minValue < -epsilon || maxValue > 1.0 + epsilon {
            monotone = false
        }
        return BiasSampleReport(samples: samples, monotone: monotone, minValue: minValue, maxValue: maxValue)
    }

    private static func writeWarning(_ message: String) {
        FileHandle.standardError.write(Data("[WARN] \(message)\n".utf8))
    }
}

private struct BiasSampleReport {
    let samples: [Double]
    let monotone: Bool
    let minValue: Double
    let maxValue: Double
}
