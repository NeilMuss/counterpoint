import Foundation

public struct Keyframe: Codable, Equatable {
    public var t: Double
    public var value: Double

    public init(t: Double, value: Double) {
        self.t = t
        self.value = value
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

public struct DefaultParamEvaluator: ParamEvaluating {
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
                let alpha = span == 0 ? 0.0 : (t - a.t) / span
                return interp(a.value, b.value, alpha)
            }
        }
        return last.value
    }
}
