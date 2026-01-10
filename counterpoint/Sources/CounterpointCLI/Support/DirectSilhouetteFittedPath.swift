import Foundation
import Domain
import UseCases

func directFittedPath(from result: DirectSilhouetteResult, epsilon: Double = 1.0e-9) -> FittedPath? {
    let left = removeConsecutiveDuplicates(result.leftRail, tol: epsilon)
    let right = removeConsecutiveDuplicates(result.rightRail, tol: epsilon)
    guard left.count >= 2, right.count >= 2 else { return nil }

    let leftSegments = catmullRomSegments(points: left, closed: false)
    let endCapSegments = cubicLineSegments(from: result.endCap)
    let rightSegments = catmullRomSegments(points: right.reversed(), closed: false)
    let startCapSegments = cubicLineSegments(from: result.startCap)

    let segments = leftSegments
        + endCapSegments
        + rightSegments
        + startCapSegments

    guard !segments.isEmpty else { return nil }
    return FittedPath(subpaths: [FittedSubpath(segments: segments)])
}

private func catmullRomSegments(points: [Point], closed: Bool) -> [CubicBezier] {
    let count = points.count
    guard count >= 2 else { return [] }
    var segments: [CubicBezier] = []
    segments.reserveCapacity(closed ? count : max(0, count - 1))

    let lastIndex = count - 1
    let segmentCount = closed ? count : (count - 1)
    for i in 0..<segmentCount {
        let p1 = points[i]
        let p2 = points[(i + 1) % count]
        let p0: Point
        let p3: Point
        if i == 0 {
            let next = points[min(1, lastIndex)]
            p0 = p1 - (next - p1)
        } else {
            p0 = points[i - 1]
        }
        if i + 2 <= lastIndex {
            p3 = points[i + 2]
        } else {
            let prev = points[lastIndex]
            p3 = p2 + (p2 - prev)
        }
        let c1 = p1 + (p2 - p0) * (1.0 / 6.0)
        let c2 = p2 - (p3 - p1) * (1.0 / 6.0)
        segments.append(CubicBezier(p0: p1, p1: c1, p2: c2, p3: p2))
    }
    return segments
}

private func cubicLineSegments(from points: [Point]) -> [CubicBezier] {
    guard points.count >= 2 else { return [] }
    var segments: [CubicBezier] = []
    segments.reserveCapacity(points.count - 1)
    for i in 0..<(points.count - 1) {
        let a = points[i]
        let b = points[i + 1]
        segments.append(lineToCubic(from: a, to: b))
    }
    return segments
}

private func lineToCubic(from a: Point, to b: Point) -> CubicBezier {
    let c1 = a + (b - a) * (1.0 / 3.0)
    let c2 = a + (b - a) * (2.0 / 3.0)
    return CubicBezier(p0: a, p1: c1, p2: c2, p3: b)
}
