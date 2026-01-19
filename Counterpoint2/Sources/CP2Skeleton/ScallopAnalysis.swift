import Foundation
import CP2Geometry

public struct ScallopMetrics: Equatable {
    public let turnExtremaCount: Int
    public let chordPeakCount: Int
    public let maxChordDeviation: Double
    public let normalizedMaxChordDeviation: Double

    public init(turnExtremaCount: Int, chordPeakCount: Int, maxChordDeviation: Double, normalizedMaxChordDeviation: Double) {
        self.turnExtremaCount = turnExtremaCount
        self.chordPeakCount = chordPeakCount
        self.maxChordDeviation = maxChordDeviation
        self.normalizedMaxChordDeviation = normalizedMaxChordDeviation
    }
}

public struct ScallopAnalysis: Equatable {
    public let centerIndex: Int
    public let windowSize: Int
    public let raw: ScallopMetrics
    public let filtered: ScallopMetrics

    public init(centerIndex: Int, windowSize: Int, raw: ScallopMetrics, filtered: ScallopMetrics) {
        self.centerIndex = centerIndex
        self.windowSize = windowSize
        self.raw = raw
        self.filtered = filtered
    }
}

public func analyzeScallops(
    points: [Vec2],
    width: Double,
    halfWindow: Int,
    epsilon: Double,
    cornerThreshold: Double,
    capTrim: Int
) -> ScallopAnalysis {
    guard points.count >= 3 else {
        let zero = ScallopMetrics(turnExtremaCount: 0, chordPeakCount: 0, maxChordDeviation: 0.0, normalizedMaxChordDeviation: 0.0)
        return ScallopAnalysis(centerIndex: 0, windowSize: 0, raw: zero, filtered: zero)
    }
    var angles: [Double] = []
    angles.reserveCapacity(points.count)
    angles.append(0.0)
    for i in 1..<(points.count - 1) {
        let v0 = points[i] - points[i - 1]
        let v1 = points[i + 1] - points[i]
        let cross = v0.x * v1.y - v0.y * v1.x
        let dot = v0.dot(v1)
        angles.append(atan2(cross, dot))
    }
    angles.append(0.0)
    var maxIndex = 0
    var maxAngle = 0.0
    for i in 1..<(angles.count - 1) {
        let value = abs(angles[i])
        if value > maxAngle {
            maxAngle = value
            maxIndex = i
        }
    }
    let start = max(1, maxIndex - halfWindow)
    let end = min(points.count - 2, maxIndex + halfWindow)
    let windowSize = max(0, end - start + 1)

    let raw = scallopMetrics(
        points: points,
        angles: angles,
        start: start,
        end: end,
        width: width,
        epsilon: epsilon,
        cornerThreshold: Double.greatestFiniteMagnitude,
        capTrim: 0
    )
    let filtered = scallopMetrics(
        points: points,
        angles: angles,
        start: start,
        end: end,
        width: width,
        epsilon: epsilon,
        cornerThreshold: cornerThreshold,
        capTrim: capTrim
    )

    return ScallopAnalysis(centerIndex: maxIndex, windowSize: windowSize, raw: raw, filtered: filtered)
}

private func scallopMetrics(
    points: [Vec2],
    angles: [Double],
    start: Int,
    end: Int,
    width: Double,
    epsilon: Double,
    cornerThreshold: Double,
    capTrim: Int
) -> ScallopMetrics {
    guard points.count >= 3, start <= end else {
        return ScallopMetrics(turnExtremaCount: 0, chordPeakCount: 0, maxChordDeviation: 0.0, normalizedMaxChordDeviation: 0.0)
    }
    let minIndex = max(1, capTrim)
    let maxIndex = min(points.count - 2, points.count - 1 - capTrim)

    var turnExtrema = 0
    var lastSign = 0
    for i in start...end where i >= minIndex && i <= maxIndex {
        let angle = angles[i]
        if abs(angle) > cornerThreshold {
            continue
        }
        let sign: Int
        if abs(angle) <= epsilon {
            continue
        } else if angle > 0 {
            sign = 1
        } else {
            sign = -1
        }
        if lastSign != 0, sign != lastSign {
            turnExtrema += 1
        }
        lastSign = sign
    }

    var chordPeakCount = 0
    var maxDeviation = 0.0
    if end - start >= 2 {
        for i in start...end where i >= minIndex && i <= maxIndex {
            let angle = angles[i]
            if abs(angle) > cornerThreshold {
                continue
            }
            let prev = points[i - 1]
            let next = points[i + 1]
            let d = distancePointToSegment(points[i], prev, next, epsilon: epsilon)
            if d > maxDeviation {
                maxDeviation = d
            }
            guard i >= 2, i + 2 < points.count else { continue }
            let prevD = distancePointToSegment(points[i - 1], points[i - 2], points[i], epsilon: epsilon)
            let nextD = distancePointToSegment(points[i + 1], points[i], points[i + 2], epsilon: epsilon)
            if d > epsilon, d >= prevD, d >= nextD {
                chordPeakCount += 1
            }
        }
    }

    let denom = max(epsilon, width)
    let normalized = maxDeviation / denom
    return ScallopMetrics(
        turnExtremaCount: turnExtrema,
        chordPeakCount: chordPeakCount,
        maxChordDeviation: maxDeviation,
        normalizedMaxChordDeviation: normalized
    )
}

private func distancePointToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2, epsilon: Double) -> Double {
    let ab = b - a
    let ap = p - a
    let denom = max(epsilon, ab.dot(ab))
    let t = max(0.0, min(1.0, ap.dot(ab) / denom))
    let proj = a + ab * t
    return (p - proj).length
}
