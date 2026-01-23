public struct Keyframe: Codable, Equatable {
    public var t: Double
    public var value: Double
    public init(t: Double, value: Double) { self.t = t; self.value = value }
}

public struct KeyframedScalar: Codable, Equatable {
    public var keyframes: [Keyframe]
    public init(keyframes: [Keyframe]) { self.keyframes = keyframes }

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
                return a.value + (b.value - a.value) * u
            }
        }
        return kfs[kfs.count - 1].value
    }
}

