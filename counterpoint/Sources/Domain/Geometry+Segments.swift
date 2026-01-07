import Foundation

public struct Segment: Equatable {
    public let a: Point
    public let b: Point

    public init(a: Point, b: Point) {
        self.a = a
        self.b = b
    }

    public var bbox: (min: Point, max: Point) {
        let minPoint = Point(x: min(a.x, b.x), y: min(a.y, b.y))
        let maxPoint = Point(x: max(a.x, b.x), y: max(a.y, b.y))
        return (min: minPoint, max: maxPoint)
    }
}

public enum SegmentIntersection: Equatable {
    case none
    case proper(Point)
    case endpoint(Point)
    case collinearOverlap(Segment)
}

public func segments(from ring: Ring, ensureClosed: Bool = true) -> [Segment] {
    let cleaned = removeConsecutiveDuplicates(ring, tol: 0)
    let closed = ensureClosed ? closeRingIfNeeded(cleaned, tol: 0) : cleaned
    let points = removeConsecutiveDuplicates(closed, tol: 0)
    guard points.count >= 2 else { return [] }
    var result: [Segment] = []
    result.reserveCapacity(max(0, points.count - 1))
    for i in 0..<(points.count - 1) {
        let a = points[i]
        let b = points[i + 1]
        if a != b {
            result.append(Segment(a: a, b: b))
        }
    }
    return result
}

public func segments(from polygon: Polygon) -> [Segment] {
    var result = segments(from: polygon.outer, ensureClosed: true)
    for hole in polygon.holes {
        result.append(contentsOf: segments(from: hole, ensureClosed: true))
    }
    return result
}

public func segments(from polygons: PolygonSet) -> [Segment] {
    polygons.flatMap { segments(from: $0) }
}

public func intersect(_ s1: Segment, _ s2: Segment, tol: Double = 0) -> SegmentIntersection {
    let p = s1.a
    let r = s1.b - s1.a
    let q = s2.a
    let s = s2.b - s2.a

    let rxs = cross(r, s)
    let qmp = q - p
    let qmpxr = cross(qmp, r)

    let eps = max(0.0, tol)
    if nearZero(rxs, tol: eps) && nearZero(qmpxr, tol: eps) {
        return collinearIntersection(s1, s2, tol: eps)
    }
    if nearZero(rxs, tol: eps) && !nearZero(qmpxr, tol: eps) {
        return .none
    }

    let t = cross(qmp, s) / rxs
    let u = cross(qmp, r) / rxs
    if within(t, 0.0, 1.0, tol: eps) && within(u, 0.0, 1.0, tol: eps) {
        let intersection = Point(x: p.x + t * r.x, y: p.y + t * r.y)
        if isEndpointIntersection(intersection, s1, s2, tol: eps) {
            return .endpoint(intersection)
        }
        return .proper(intersection)
    }
    return .none
}

private func isEndpointIntersection(_ point: Point, _ s1: Segment, _ s2: Segment, tol: Double) -> Bool {
    pointsEqual(point, s1.a, tol: tol)
        || pointsEqual(point, s1.b, tol: tol)
        || pointsEqual(point, s2.a, tol: tol)
        || pointsEqual(point, s2.b, tol: tol)
}

private func collinearIntersection(_ s1: Segment, _ s2: Segment, tol: Double) -> SegmentIntersection {
    let axis = dominantAxis(s1.a, s1.b)
    let (s1Min, s1Max) = axisRange(s1, axis: axis)
    let (s2Min, s2Max) = axisRange(s2, axis: axis)
    let overlapMin = max(s1Min, s2Min)
    let overlapMax = min(s1Max, s2Max)
    if overlapMax < overlapMin - tol {
        return .none
    }
    if abs(overlapMax - overlapMin) <= tol {
        let point = pointOnSegment(s1, axis: axis, value: overlapMin)
        return .endpoint(point)
    }
    let a = pointOnSegment(s1, axis: axis, value: overlapMin)
    let b = pointOnSegment(s1, axis: axis, value: overlapMax)
    let ordered = orderedSegment(a, b)
    return .collinearOverlap(ordered)
}

private enum Axis {
    case x
    case y
}

private func dominantAxis(_ a: Point, _ b: Point) -> Axis {
    let dx = abs(b.x - a.x)
    let dy = abs(b.y - a.y)
    return dx >= dy ? .x : .y
}

private func axisRange(_ segment: Segment, axis: Axis) -> (Double, Double) {
    switch axis {
    case .x:
        return (min(segment.a.x, segment.b.x), max(segment.a.x, segment.b.x))
    case .y:
        return (min(segment.a.y, segment.b.y), max(segment.a.y, segment.b.y))
    }
}

private func pointOnSegment(_ segment: Segment, axis: Axis, value: Double) -> Point {
    let a = segment.a
    let b = segment.b
    switch axis {
    case .x:
        if abs(b.x - a.x) <= 0.0 {
            return Point(x: a.x, y: a.y)
        }
        let t = (value - a.x) / (b.x - a.x)
        return Point(x: value, y: a.y + (b.y - a.y) * t)
    case .y:
        if abs(b.y - a.y) <= 0.0 {
            return Point(x: a.x, y: a.y)
        }
        let t = (value - a.y) / (b.y - a.y)
        return Point(x: a.x + (b.x - a.x) * t, y: value)
    }
}

private func orderedSegment(_ a: Point, _ b: Point) -> Segment {
    if (a.x < b.x) || (a.x == b.x && a.y <= b.y) {
        return Segment(a: a, b: b)
    }
    return Segment(a: b, b: a)
}

private func cross(_ a: Point, _ b: Point) -> Double {
    a.x * b.y - a.y * b.x
}

private func nearZero(_ value: Double, tol: Double) -> Bool {
    abs(value) <= tol
}

private func within(_ value: Double, _ minValue: Double, _ maxValue: Double, tol: Double) -> Bool {
    value >= minValue - tol && value <= maxValue + tol
}

private func pointsEqual(_ a: Point, _ b: Point, tol: Double) -> Bool {
    if tol <= 0 {
        return a == b
    }
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy) <= (tol * tol)
}
