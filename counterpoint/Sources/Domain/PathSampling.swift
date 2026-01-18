import Foundation

public protocol PathSampling {
    func makePolyline(path: BezierPath, tolerance: Double) -> PathPolyline
}

public struct PathPolyline: Equatable {
    public let points: [Point]
    public let cumulativeLengths: [Double]
    public let totalLength: Double

    public init(points: [Point]) {
        self.points = points
        var lengths: [Double] = []
        lengths.reserveCapacity(points.count)
        var total = 0.0
        lengths.append(0.0)
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            total += hypot(dx, dy)
            lengths.append(total)
        }
        self.cumulativeLengths = lengths
        self.totalLength = total
    }

    public func point(at normalizedT: Double) -> Point {
        guard points.count > 1 else { return points.first ?? Point(x: 0, y: 0) }
        let t = max(0.0, min(1.0, normalizedT))
        let target = t * totalLength
        let index = segmentIndex(for: target)
        let startLength = cumulativeLengths[index]
        let endLength = cumulativeLengths[index + 1]
        let segmentLength = endLength - startLength
        if segmentLength == 0 { return points[index] }
        let localT = (target - startLength) / segmentLength
        let a = points[index]
        let b = points[index + 1]
        return Point(
            x: a.x + (b.x - a.x) * localT,
            y: a.y + (b.y - a.y) * localT
        )
    }

    public func tangentAngle(at normalizedT: Double, fallbackAngle: Double) -> Double {
        guard points.count > 1 else { return fallbackAngle }
        let t = max(0.0, min(1.0, normalizedT))
        let target = t * totalLength
        let index = segmentIndex(for: target)
        if let angle = nonZeroAngle(fromIndex: index) {
            return angle
        }
        let chord = points[points.count - 1] - points[0]
        if hypot(chord.x, chord.y) > 0 {
            return atan2(chord.y, chord.x)
        }
        return fallbackAngle
    }

    public func sampleParameters(spacing: Double, maxSamples: Int) -> [Double] {
        guard totalLength > 0, spacing > 0 else { return [0.0, 1.0] }
        let cappedMax = max(2, maxSamples)
        var parameters: [Double] = [0.0]
        var current = spacing
        while current < totalLength {
            parameters.append(current / totalLength)
            current += spacing
            if parameters.count >= cappedMax - 1 {
                break
            }
        }
        if parameters.last != 1.0 {
            parameters.append(1.0)
        }
        return parameters
    }

    private func segmentIndex(for targetLength: Double) -> Int {
        var index = 0
        while index + 1 < cumulativeLengths.count && cumulativeLengths[index + 1] < targetLength {
            index += 1
        }
        return min(index, max(0, cumulativeLengths.count - 2))
    }

    private func nonZeroAngle(fromIndex index: Int) -> Double? {
        let forward = angleForSegment(startIndex: index)
        if let forward { return forward }
        if index > 0 {
            return angleForSegment(startIndex: index - 1)
        }
        return nil
    }

    private func angleForSegment(startIndex: Int) -> Double? {
        guard startIndex >= 0, startIndex + 1 < points.count else { return nil }
        let a = points[startIndex]
        let b = points[startIndex + 1]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        if length == 0 { return nil }
        return atan2(dy, dx)
    }
}

public struct DefaultPathSampler: PathSampling {
    public init() {}

    public func makePolyline(path: BezierPath, tolerance: Double) -> PathPolyline {
        var points: [Point] = []
        for segment in path.segments {
            let flattened = flatten(segment, tolerance: tolerance)
            if points.isEmpty {
                points.append(contentsOf: flattened)
            } else {
                points.append(contentsOf: flattened.dropFirst())
            }
        }
        if points.count < 2, let first = points.first {
            points.append(first)
        }
        return PathPolyline(points: points)
    }

    private func flatten(_ segment: CubicBezier, tolerance: Double) -> [Point] {
        var result: [Point] = []

        func subdivide(_ cubic: CubicBezier) {
            if cubic.flatness() <= tolerance {
                if result.isEmpty { result.append(cubic.p0) }
                result.append(cubic.p3)
            } else {
                let parts = cubic.subdivided()
                subdivide(parts.left)
                subdivide(parts.right)
            }
        }

        subdivide(segment)
        return result
    }
}
