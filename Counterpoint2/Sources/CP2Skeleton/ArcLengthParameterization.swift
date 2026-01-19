import CP2Geometry

public struct ArcLengthParameterization {
    private struct Sample {
        let u: Double
        let point: Vec2
        let cumulative: Double
    }

    private let samples: [Sample]
    public let totalLength: Double

    public init(path: SkeletonPath, samplesPerSegment: Int = 256) {
        let count = max(2, samplesPerSegment)
        var table: [Sample] = []
        table.reserveCapacity(count)
        var cumulative = 0.0
        var previous = path.evaluate(0.0)
        for i in 0..<count {
            let u = Double(i) / Double(count - 1)
            let point = path.evaluate(u)
            if i > 0 {
                cumulative += (point - previous).length
            }
            table.append(Sample(u: u, point: point, cumulative: cumulative))
            previous = point
        }
        totalLength = max(cumulative, Epsilon.defaultValue)
        samples = table
    }

    public func position(atS s: Double, path: SkeletonPath) -> Vec2 {
        let clamped = max(0.0, min(1.0, s))
        let target = clamped * totalLength
        if target <= samples.first?.cumulative ?? 0.0 {
            return samples.first?.point ?? Vec2(0, 0)
        }
        if target >= samples.last?.cumulative ?? 0.0 {
            return samples.last?.point ?? Vec2(0, 0)
        }
        var low = 0
        var high = samples.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if samples[mid].cumulative < target {
                low = mid
            } else {
                high = mid
            }
        }
        let a = samples[low]
        let b = samples[high]
        let span = max(Epsilon.defaultValue, b.cumulative - a.cumulative)
        let t = (target - a.cumulative) / span
        return a.point.lerp(to: b.point, t: t)
    }

    public func u(atDistance s: Double) -> Double {
        if totalLength <= Epsilon.defaultValue {
            return 0.0
        }
        let clamped = max(0.0, min(totalLength, s))
        if clamped <= samples.first?.cumulative ?? 0.0 {
            return 0.0
        }
        if clamped >= samples.last?.cumulative ?? 0.0 {
            return 1.0
        }
        var low = 0
        var high = samples.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if samples[mid].cumulative < clamped {
                low = mid
            } else {
                high = mid
            }
        }
        let a = samples[low]
        let b = samples[high]
        let span = max(Epsilon.defaultValue, b.cumulative - a.cumulative)
        let t = (clamped - a.cumulative) / span
        return a.u + (b.u - a.u) * t
    }

    public func sampleTable() -> [Vec2] {
        samples.map { $0.point }
    }

    public func uTable() -> [Double] {
        samples.map { $0.u }
    }
}
