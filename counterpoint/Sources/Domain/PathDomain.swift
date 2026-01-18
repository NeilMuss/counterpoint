import Foundation

public struct PathDomain {
    public struct Sample: Equatable {
        public let segmentIndex: Int
        public let t: Double
        public let point: Point
        public let unitTangent: Point
        public let cumulativeLength: Double
        public let s: Double

        public var gt: Double { s }
    }

    private struct TableEntry {
        let segmentIndex: Int
        let t: Double
        let point: Point
        let cumulativeLength: Double
    }

    public let totalLength: Double
    public let samples: [Sample]
    private let entries: [TableEntry]

    public init(path: BezierPath, samplesPerSegment: Int) {
        let capped = max(2, samplesPerSegment)
        var table: [TableEntry] = []
        table.reserveCapacity(path.segments.count * capped)

        var cumulative = 0.0
        var previousPoint: Point?

        for (segIndex, segment) in path.segments.enumerated() {
            for i in 0..<capped {
                let t = Double(i) / Double(capped - 1)
                let point = segment.point(at: t)
                if let prev = previousPoint {
                    cumulative += (point - prev).length
                }
                table.append(TableEntry(segmentIndex: segIndex, t: t, point: point, cumulativeLength: cumulative))
                previousPoint = point
            }
        }

        let length = max(cumulative, 1.0e-9)
        totalLength = length
        entries = table
        samples = table.enumerated().map { index, entry in
            let s = entry.cumulativeLength / length
            let tangent = PathDomain.unitTangent(path: path, segmentIndex: entry.segmentIndex, t: entry.t, fallbackIndex: index, entries: table)
            return Sample(
                segmentIndex: entry.segmentIndex,
                t: entry.t,
                point: entry.point,
                unitTangent: tangent,
                cumulativeLength: entry.cumulativeLength,
                s: s
            )
        }
    }

    public func evalAtS(_ s: Double, path: BezierPath) -> Sample {
        let clamped = ScalarMath.clamp01(s)
        let target = clamped * totalLength
        guard let last = samples.last else {
            return Sample(segmentIndex: 0, t: 0.0, point: Point(x: 0, y: 0), unitTangent: Point(x: 1, y: 0), cumulativeLength: 0.0, s: clamped)
        }
        if target >= last.cumulativeLength {
            return Sample(segmentIndex: last.segmentIndex, t: last.t, point: last.point, unitTangent: last.unitTangent, cumulativeLength: last.cumulativeLength, s: clamped)
        }
        guard let first = samples.first else {
            return last
        }
        if target <= first.cumulativeLength {
            return Sample(segmentIndex: first.segmentIndex, t: first.t, point: first.point, unitTangent: first.unitTangent, cumulativeLength: first.cumulativeLength, s: clamped)
        }

        var upperIndex = samples.count - 1
        var lowerIndex = 0
        while lowerIndex + 1 < upperIndex {
            let mid = (lowerIndex + upperIndex) / 2
            if samples[mid].cumulativeLength < target {
                lowerIndex = mid
            } else {
                upperIndex = mid
            }
        }

        let a = samples[lowerIndex]
        let b = samples[upperIndex]
        let span = max(1.0e-9, b.cumulativeLength - a.cumulativeLength)
        let alpha = (target - a.cumulativeLength) / span
        let t = ScalarMath.lerp(a.t, b.t, alpha)
        let segIndex = a.segmentIndex
        let segment = path.segments[segIndex]
        let point = segment.point(at: t)
        let tangent = PathDomain.unitTangent(path: path, segmentIndex: segIndex, t: t, fallbackIndex: lowerIndex, entries: entries)
        return Sample(
            segmentIndex: segIndex,
            t: t,
            point: point,
            unitTangent: tangent,
            cumulativeLength: ScalarMath.lerp(a.cumulativeLength, b.cumulativeLength, alpha),
            s: clamped
        )
    }

    public func s(forSegment segmentIndex: Int, t: Double) -> Double {
        guard segmentIndex >= 0 else { return 0.0 }
        let clampedT = ScalarMath.clamp01(t)
        guard let entryIndex = samples.firstIndex(where: { $0.segmentIndex == segmentIndex && $0.t >= clampedT }) else {
            return 1.0
        }
        if entryIndex == 0 { return samples[0].s }
        let prev = samples[entryIndex - 1]
        let next = samples[entryIndex]
        let span = max(1.0e-9, next.t - prev.t)
        let alpha = (clampedT - prev.t) / span
        let length = ScalarMath.lerp(prev.cumulativeLength, next.cumulativeLength, alpha)
        return length / totalLength
    }

    private static func unitTangent(path: BezierPath, segmentIndex: Int, t: Double, fallbackIndex: Int, entries: [TableEntry]) -> Point {
        let segment = path.segments[segmentIndex]
        let derivative = segment.derivative(at: t)
        if let norm = derivative.normalized() {
            return norm
        }
        let forwardIndex = min(entries.count - 1, fallbackIndex + 1)
        if forwardIndex != fallbackIndex {
            let vec = entries[forwardIndex].point - entries[fallbackIndex].point
            if let norm = vec.normalized() { return norm }
        }
        if fallbackIndex > 0 {
            let vec = entries[fallbackIndex].point - entries[fallbackIndex - 1].point
            if let norm = vec.normalized() { return norm }
        }
        return Point(x: 1, y: 0)
    }
}
