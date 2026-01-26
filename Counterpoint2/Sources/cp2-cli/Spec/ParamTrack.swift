import Foundation

public enum KnotType: String, Codable, Equatable {
    case smooth
    case cusp
    case hold
    case snap
}

public enum InterpMode: Equatable {
    case linear
    case hermite
    case hermiteMonotone
}

public struct ParamKeyframe: Equatable {
    public let t: Double
    public let value: Double
    public let knot: KnotType
    public let outTangentScale: Double
    public let segmentAlpha: Double

    public init(t: Double, value: Double, knot: KnotType = .smooth, outTangentScale: Double = 1.0, segmentAlpha: Double = 0.0) {
        self.t = t
        self.value = value
        self.knot = knot
        self.outTangentScale = outTangentScale
        self.segmentAlpha = segmentAlpha
    }
}

public struct ParamTrack: Equatable {
    public let keyframes: [ParamKeyframe]
    public let mode: InterpMode

    private let mIn: [Double]
    private let mOut: [Double]

    public init(keyframes: [ParamKeyframe], mode: InterpMode) {
        let sorted = keyframes.sorted { $0.t < $1.t }
        self.keyframes = sorted
        self.mode = mode
        let tangents = ParamTrack.computeTangents(keyframes: sorted, mode: mode)
        self.mIn = tangents.mIn
        self.mOut = tangents.mOut
    }

    public func value(at t: Double) -> Double {
        guard !keyframes.isEmpty else { return 0.0 }
        if keyframes.count == 1 { return keyframes[0].value }
        if t <= keyframes[0].t { return keyframes[0].value }
        if t >= keyframes[keyframes.count - 1].t { return keyframes[keyframes.count - 1].value }

        for i in 0..<(keyframes.count - 1) {
            let a = keyframes[i]
            let b = keyframes[i + 1]
            if t >= a.t && t <= b.t {
                let dt = b.t - a.t
                if dt <= 0 { return b.value }
                let u = (t - a.t) / dt
                if mode == .linear {
                    return a.value + (b.value - a.value) * u
                }
                let h00 = 2 * u * u * u - 3 * u * u + 1
                let h10 = u * u * u - 2 * u * u + u
                let h01 = -2 * u * u * u + 3 * u * u
                let h11 = u * u * u - u * u
                return h00 * a.value
                    + h10 * (dt * mOut[i])
                    + h01 * b.value
                    + h11 * (dt * mIn[i + 1])
            }
        }
        return keyframes[keyframes.count - 1].value
    }

    public func segmentAlpha(at t: Double) -> Double {
        guard keyframes.count >= 2 else { return 0.0 }
        if t <= keyframes[0].t { return keyframes[0].segmentAlpha }
        if t >= keyframes[keyframes.count - 1].t { return 0.0 }
        for i in 0..<(keyframes.count - 1) {
            let a = keyframes[i]
            let b = keyframes[i + 1]
            if t >= a.t && t <= b.t {
                return a.segmentAlpha
            }
        }
        return 0.0
    }

    public static func scaleFromAlpha(_ alpha: Double) -> Double {
        return pow(2.0, -alpha)
    }

    public static func fromKeyframedScalar(_ scalar: KeyframedScalar, mode: InterpMode) -> ParamTrack {
        let frames = scalar.keyframes.map { kf in
            let knot = kf.knot ?? .smooth
            let alpha = kf.interpToNext?.alpha ?? 0.0
            let scale = scaleFromAlpha(alpha)
            return ParamKeyframe(t: kf.t, value: kf.value, knot: knot, outTangentScale: scale, segmentAlpha: alpha)
        }
        return ParamTrack(keyframes: frames, mode: mode)
    }

    private static func computeTangents(keyframes: [ParamKeyframe], mode: InterpMode) -> (mIn: [Double], mOut: [Double]) {
        let n = keyframes.count
        var base: [Double] = Array(repeating: 0.0, count: n)
        if n >= 2 {
            for i in 0..<n {
                if i == 0 {
                    let dt = keyframes[1].t - keyframes[0].t
                    base[i] = dt <= 0 ? 0.0 : (keyframes[1].value - keyframes[0].value) / dt
                } else if i == n - 1 {
                    let dt = keyframes[n - 1].t - keyframes[n - 2].t
                    base[i] = dt <= 0 ? 0.0 : (keyframes[n - 1].value - keyframes[n - 2].value) / dt
                } else {
                    let dt = keyframes[i + 1].t - keyframes[i - 1].t
                    base[i] = dt <= 0 ? 0.0 : (keyframes[i + 1].value - keyframes[i - 1].value) / dt
                }
            }
        }

        var mIn = base
        var mOut = base
        for i in 0..<n {
            let knot = keyframes[i].knot
            switch knot {
            case .cusp:
                if i > 0 {
                    let dt = keyframes[i].t - keyframes[i - 1].t
                    mIn[i] = dt <= 0 ? 0.0 : (keyframes[i].value - keyframes[i - 1].value) / dt
                }
                if i < n - 1 {
                    let dt = keyframes[i + 1].t - keyframes[i].t
                    mOut[i] = dt <= 0 ? 0.0 : (keyframes[i + 1].value - keyframes[i].value) / dt
                }
            case .hold:
                mOut[i] = 0.0
            case .snap:
                mIn[i] = 0.0
            case .smooth:
                break
            }
            mOut[i] *= keyframes[i].outTangentScale
        }

        if mode == .hermiteMonotone {
            for i in 0..<(n - 1) {
                let dt = keyframes[i + 1].t - keyframes[i].t
                if dt <= 0 { continue }
                let delta = (keyframes[i + 1].value - keyframes[i].value) / dt
                if abs(delta) <= 1.0e-12 {
                    mOut[i] = 0.0
                    mIn[i + 1] = 0.0
                    continue
                }
                var a = mOut[i] / delta
                var b = mIn[i + 1] / delta
                if a < 0.0 {
                    mOut[i] = 0.0
                    a = 0.0
                }
                if b < 0.0 {
                    mIn[i + 1] = 0.0
                    b = 0.0
                }
                let sum = a * a + b * b
                if sum > 9.0 {
                    let scale = 3.0 / sqrt(sum)
                    mOut[i] = delta * a * scale
                    mIn[i + 1] = delta * b * scale
                }
            }
        }

        return (mIn, mOut)
    }
}
