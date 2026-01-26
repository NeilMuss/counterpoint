import Foundation

public struct StrokeSpec: Codable, Equatable {
    public var id: String
    public var type: StrokeSpecType
    public var ink: String
    public var params: StrokeParams?

    public init(id: String, type: StrokeSpecType, ink: String, params: StrokeParams? = nil) {
        self.id = id
        self.type = type
        self.ink = ink
        self.params = params
    }
}

public enum StrokeSpecType: String, Codable, Equatable {
    case stroke
}

public struct StrokeParams: Codable, Equatable {
    public var angleMode: AngleMode?
    public var theta: KeyframedScalar?
    public var width: KeyframedScalar?
    public var widthLeft: KeyframedScalar?
    public var widthRight: KeyframedScalar?
    public var offset: KeyframedScalar?
    public var alpha: KeyframedScalar?   // optional for now

    public init(
        angleMode: AngleMode? = nil,
        theta: KeyframedScalar? = nil,
        width: KeyframedScalar? = nil,
        widthLeft: KeyframedScalar? = nil,
        widthRight: KeyframedScalar? = nil,
        offset: KeyframedScalar? = nil,
        alpha: KeyframedScalar? = nil
    ) {
        self.angleMode = angleMode
        self.theta = theta
        self.width = width
        self.widthLeft = widthLeft
        self.widthRight = widthRight
        self.offset = offset
        self.alpha = alpha
    }
}

public enum AngleMode: String, Codable, Equatable {
    case absolute
    case relative
}

public struct Keyframe: Codable, Equatable {
    public var t: Double
    public var value: Double
    public var interpToNext: InterpToNext?
    public init(t: Double, value: Double, interpToNext: InterpToNext? = nil) {
        self.t = t
        self.value = value
        self.interpToNext = interpToNext
    }
}

public struct InterpToNext: Codable, Equatable {
    public var alpha: Double
    public init(alpha: Double) { self.alpha = alpha }
}

public struct KeyframedScalar: Codable, Equatable {
    public var keyframes: [Keyframe]
    public init(keyframes: [Keyframe]) { self.keyframes = keyframes }

    public func eval(t: Double) -> Double {
        value(at: t)
    }

    public func value(at t: Double) -> Double {
        guard !keyframes.isEmpty else { return 0.0 }
        let kfs = keyframes.sorted { $0.t < $1.t }
        if t <= kfs[0].t { return kfs[0].value }
        if t >= kfs[kfs.count - 1].t { return kfs[kfs.count - 1].value }

        for i in 0..<(kfs.count - 1) {
            let a = kfs[i], b = kfs[i + 1]
            if t >= a.t && t <= b.t {
                let denom = (b.t - a.t)
                if denom == 0 { return b.value }
                let u = (t - a.t) / denom
                let alpha = a.interpToNext?.alpha ?? 0.0
                let uWarp = warpU(u: u, alpha: alpha)
                return a.value + (b.value - a.value) * uWarp
            }
        }
        return kfs[kfs.count - 1].value
    }

    public func segmentAlpha(at t: Double) -> Double {
        guard keyframes.count >= 2 else { return 0.0 }
        let kfs = keyframes.sorted { $0.t < $1.t }
        if t <= kfs[0].t { return kfs[0].interpToNext?.alpha ?? 0.0 }
        if t >= kfs[kfs.count - 1].t { return 0.0 }
        for i in 0..<(kfs.count - 1) {
            let a = kfs[i], b = kfs[i + 1]
            if t >= a.t && t <= b.t {
                return a.interpToNext?.alpha ?? 0.0
            }
        }
        return 0.0
    }

    private func warpU(u: Double, alpha: Double) -> Double {
        let clampedU = max(0.0, min(1.0, u))
        let exponent = exp(alpha)
        let warped = pow(clampedU, exponent)
        return max(0.0, min(1.0, warped))
    }
}
