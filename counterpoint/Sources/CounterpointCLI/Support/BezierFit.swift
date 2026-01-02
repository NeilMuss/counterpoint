import Foundation
import Domain

struct FittedSubpath: Equatable {
    var segments: [CubicBezier]
}

struct FittedPath: Equatable {
    var subpaths: [FittedSubpath]
}

enum OutlineFitMode: String {
    case none
    case simplify
    case bezier
}

struct BezierFitter {
    let tolerance: Double
    let cornerThresholdDegrees: Double

    init(tolerance: Double, cornerThresholdDegrees: Double = 60.0) {
        self.tolerance = tolerance
        self.cornerThresholdDegrees = cornerThresholdDegrees
    }

    func fitPolygonSet(_ polygons: PolygonSet) -> [FittedPath] {
        polygons.map { polygon in
            let outer = fitRing(polygon.outer, closed: true)
            let holes = polygon.holes.map { fitRing($0, closed: true) }
            return FittedPath(subpaths: [outer] + holes)
        }
    }

    func fitRing(_ ring: Ring, closed: Bool) -> FittedSubpath {
        let points = normalizeRing(ring)
        guard points.count >= 2 else {
            return FittedSubpath(segments: [])
        }

        if closed {
            let rotated = rotateClosed(points)
            let chunks = splitAtCorners(rotated, thresholdDegrees: cornerThresholdDegrees)
            let segments = chunks.flatMap { chunk -> [CubicBezier] in
                let chunkPoints = closeChunk(chunk)
                return fitCurve(chunkPoints, error: tolerance)
            }
            return FittedSubpath(segments: segments)
        } else {
            let segments = fitCurve(points, error: tolerance)
            return FittedSubpath(segments: segments)
        }
    }

    func simplifyRing(_ ring: Ring, closed: Bool) -> Ring {
        let points = normalizeRing(ring)
        guard points.count >= 3 else { return points }
        let simplified = rdp(points, epsilon: tolerance)
        if closed {
            return closeRingIfNeeded(simplified)
        }
        return simplified
    }

    private func normalizeRing(_ ring: Ring) -> [Point] {
        guard let first = ring.first else { return [] }
        if ring.last == first {
            return Array(ring.dropLast())
        }
        return ring
    }

    private func rotateClosed(_ points: [Point]) -> [Point] {
        guard points.count >= 3 else { return points }
        let corners = cornerIndices(points, thresholdDegrees: cornerThresholdDegrees)
        let seamIndex: Int
        if corners.isEmpty {
            seamIndex = indexOfMinPoint(points)
        } else {
            seamIndex = corners.min { a, b in
                let pa = points[a]
                let pb = points[b]
                if pa.x == pb.x { return pa.y < pb.y }
                return pa.x < pb.x
            } ?? 0
        }
        return rotate(points, start: seamIndex)
    }

    private func splitAtCorners(_ points: [Point], thresholdDegrees: Double) -> [[Point]] {
        guard points.count >= 3 else { return [points] }
        let corners = Set(cornerIndices(points, thresholdDegrees: thresholdDegrees))
        var chunks: [[Point]] = []
        var current: [Point] = [points[0]]
        for i in 1..<points.count {
            current.append(points[i])
            if corners.contains(i) {
                chunks.append(current)
                current = [points[i]]
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private func closeChunk(_ chunk: [Point]) -> [Point] {
        guard let first = chunk.first, let last = chunk.last, first != last else { return chunk }
        return chunk + [first]
    }

    private func rotate(_ points: [Point], start: Int) -> [Point] {
        guard start > 0 else { return points }
        return Array(points[start...] + points[..<start])
    }

    private func indexOfMinPoint(_ points: [Point]) -> Int {
        var minIndex = 0
        for i in 1..<points.count {
            let a = points[minIndex]
            let b = points[i]
            if b.x < a.x || (b.x == a.x && b.y < a.y) {
                minIndex = i
            }
        }
        return minIndex
    }

    private func cornerIndices(_ points: [Point], thresholdDegrees: Double) -> [Int] {
        let threshold = thresholdDegrees * .pi / 180.0
        var result: [Int] = []
        let n = points.count
        for i in 0..<n {
            let prev = points[(i - 1 + n) % n]
            let curr = points[i]
            let next = points[(i + 1) % n]
            let v1 = (curr - prev).normalized()
            let v2 = (next - curr).normalized()
            if let v1, let v2 {
                let dot = max(-1.0, min(1.0, v1.dot(v2)))
                let angle = acos(dot)
                if angle > threshold {
                    result.append(i)
                }
            }
        }
        return result
    }

    private func rdp(_ points: [Point], epsilon: Double) -> [Point] {
        guard points.count >= 3 else { return points }
        let lineStart = points.first!
        let lineEnd = points.last!
        var maxDist = 0.0
        var index = 0
        for i in 1..<(points.count - 1) {
            let dist = distancePointToSegment(points[i], lineStart, lineEnd)
            if dist > maxDist {
                maxDist = dist
                index = i
            }
        }
        if maxDist > epsilon {
            let left = rdp(Array(points[0...index]), epsilon: epsilon)
            let right = rdp(Array(points[index...]), epsilon: epsilon)
            return left.dropLast() + right
        }
        return [lineStart, lineEnd]
    }
}

func fitUnionRails(
    _ polygons: PolygonSet,
    centerlineSamples: [PathDomain.Sample],
    simplifyTolerance: Double,
    fitTolerance: Double
) -> [FittedPath] {
    let simplifier = BezierFitter(tolerance: simplifyTolerance)
    let fitter = BezierFitter(tolerance: fitTolerance)
    return polygons.map { polygon in
        let isMonotone = isRingMonotoneInS(polygon.outer, centerlineSamples: centerlineSamples, epsilon: 1.0e-5)
        let combined: [CubicBezier]
        let (sideA, sideB) = splitRingForFitting(polygon.outer, centerlineSamples: centerlineSamples)
        let capInfo = detectCaps(sideA: sideA, sideB: sideB, centerlineSamples: centerlineSamples, fitTolerance: fitTolerance)
        if isMonotone && !capInfo.hasCaps {
            let simplified = simplifier.simplifyRing(polygon.outer, closed: true)
            combined = fitter.fitRing(simplified, closed: true).segments
        } else {
            var simplifiedA = simplifier.simplifyRing(sideA, closed: false)
            var simplifiedB = simplifier.simplifyRing(sideB, closed: false)
            alignEndpoints(&simplifiedA, &simplifiedB)

            let trimmedA = trimSide(simplifiedA, capInfo: capInfo, isStart: true, isEnd: true)
            let trimmedB = trimSide(simplifiedB, capInfo: capInfo, isStart: true, isEnd: true)
            let curvesA = fitMonotoneChain(trimmedA, centerlineSamples: centerlineSamples, tolerance: fitTolerance)
            let curvesB = fitMonotoneChain(trimmedB, centerlineSamples: centerlineSamples, tolerance: fitTolerance)
            combined = joinSidesWithCaps(
                curvesA,
                curvesB,
                capInfo: capInfo
            )
        }

        let tentative = FittedSubpath(segments: combined)
        let fallbackSegments: [CubicBezier]
        if outlineHasSelfIntersection([FittedPath(subpaths: [tentative])]) {
            let loopPoints = buildLoopFromSidesSimple(sideA: sideA, sideB: sideB)
            fallbackSegments = lineSegmentsFromLoop(loopPoints)
        } else {
            fallbackSegments = combined
        }

        let holePaths = polygon.holes.map { hole -> FittedSubpath in
            let simplified = simplifier.simplifyRing(hole, closed: true)
            return fitter.fitRing(simplified, closed: true)
        }

        return FittedPath(subpaths: [FittedSubpath(segments: fallbackSegments)] + holePaths)
    }
}

func outlineHasSelfIntersection(
    _ fittedPaths: [FittedPath],
    samplesPerCurve: Int = 24
) -> Bool {
    for path in fittedPaths {
        for subpath in path.subpaths {
            let cappedSamples = max(4, min(samplesPerCurve, maxSamplesPerCurve(for: subpath, targetPointCap: 2000)))
            let polyline = sampleSubpath(subpath, samplesPerCurve: cappedSamples)
            if polylineHasSelfIntersection(polyline, closed: true) {
                return true
            }
        }
    }
    return false
}

func isRingMonotoneInS(_ ring: Ring, centerlineSamples: [PathDomain.Sample], epsilon: Double) -> Bool {
    let points = normalizeRing(ring)
    guard points.count >= 3 else { return true }
    let sValues = points.map { projectToCenterlineS(point: $0, samples: centerlineSamples) }
    var signChanges = 0
    var lastSign = 0
    for i in 0..<points.count {
        let next = (i + 1) % points.count
        let ds = sValues[next] - sValues[i]
        let sign = ds > epsilon ? 1 : (ds < -epsilon ? -1 : 0)
        if sign != 0 {
            if lastSign == 0 {
                lastSign = sign
            } else if sign != lastSign {
                signChanges += 1
                lastSign = sign
            }
        }
    }
    return signChanges <= 2
}

private func splitRingForFitting(_ ring: Ring, centerlineSamples: [PathDomain.Sample]) -> ([Point], [Point]) {
    if isCenterlineStraight(centerlineSamples: centerlineSamples, thresholdDegrees: 2.0) {
        let split = splitRingBySignedDistance(ring, centerlineSamples: centerlineSamples)
        if split.0.count >= 2, split.1.count >= 2 {
            return split
        }
    }
    return splitRingByS(ring, centerlineSamples: centerlineSamples)
}

func splitRingByS(_ ring: Ring, centerlineSamples: [PathDomain.Sample]) -> ([Point], [Point]) {
    let points = normalizeRing(ring)
    guard points.count >= 2 else { return (points, points) }

    let sValues = points.map { projectToCenterlineS(point: $0, samples: centerlineSamples) }
    var minIndex = 0
    var maxIndex = 0
    for i in 1..<points.count {
        let s = sValues[i]
        let minS = sValues[minIndex]
        if s < minS || (s == minS && tieBreak(points[i], points[minIndex])) {
            minIndex = i
        }
        let maxS = sValues[maxIndex]
        if s > maxS || (s == maxS && tieBreak(points[i], points[maxIndex])) {
            maxIndex = i
        }
    }

    let chainForward = extractChain(points, start: minIndex, end: maxIndex, forward: true)
    let chainBackward = extractChain(points, start: minIndex, end: maxIndex, forward: false)

    let monotoneA = normalizeMonotone(chainForward, samples: centerlineSamples)
    let monotoneB = normalizeMonotone(chainBackward, samples: centerlineSamples)
    return (monotoneA, monotoneB)
}

private func splitRingBySignedDistance(_ ring: Ring, centerlineSamples: [PathDomain.Sample]) -> ([Point], [Point]) {
    let points = normalizeRing(ring)
    guard points.count >= 2 else { return (points, points) }
    guard let start = centerlineSamples.first?.point,
          let end = centerlineSamples.last?.point,
          let axis = (end - start).normalized() else {
        return (points, points)
    }
    let normal = axis.leftNormal()
    var positive: [(Double, Point)] = []
    var negative: [(Double, Point)] = []
    positive.reserveCapacity(points.count)
    negative.reserveCapacity(points.count)
    for point in points {
        let projection = projectPointToLine(point, origin: start, axis: axis)
        let s = (projection - start).dot(axis)
        let side = (point - projection).dot(normal)
        if side >= 0.0 {
            positive.append((s, point))
        } else {
            negative.append((s, point))
        }
    }
    let sortedPos = positive.sorted { $0.0 < $1.0 }.map { $0.1 }
    let sortedNeg = negative.sorted { $0.0 < $1.0 }.map { $0.1 }
    return (sortedPos, sortedNeg)
}

private func isCenterlineStraight(centerlineSamples: [PathDomain.Sample], thresholdDegrees: Double) -> Bool {
    guard centerlineSamples.count >= 2,
          let axis = (centerlineSamples.last!.point - centerlineSamples.first!.point).normalized() else {
        return false
    }
    let threshold = cos(thresholdDegrees * .pi / 180.0)
    for sample in centerlineSamples {
        let dot = max(-1.0, min(1.0, sample.unitTangent.dot(axis)))
        if dot < threshold {
            return false
        }
    }
    return true
}

private func normalizeRing(_ ring: Ring) -> [Point] {
    guard let first = ring.first else { return [] }
    if ring.last == first {
        return Array(ring.dropLast())
    }
    return ring
}

private func tieBreak(_ a: Point, _ b: Point) -> Bool {
    if a.x == b.x { return a.y < b.y }
    return a.x < b.x
}

private func extractChain(_ points: [Point], start: Int, end: Int, forward: Bool) -> [Point] {
    guard !points.isEmpty else { return [] }
    var result: [Point] = []
    var index = start
    while true {
        result.append(points[index])
        if index == end { break }
        if forward {
            index = (index + 1) % points.count
        } else {
            index = (index - 1 + points.count) % points.count
        }
    }
    return result
}

private func normalizeMonotone(_ points: [Point], samples: [PathDomain.Sample]) -> [Point] {
    guard points.count >= 2 else { return points }
    let epsilon = 1.0e-6
    let pairs = points.map { point in
        (point, projectToCenterlineS(point: point, samples: samples))
    }
    let sorted = pairs.sorted { lhs, rhs in
        if lhs.1 == rhs.1 { return tieBreak(lhs.0, rhs.0) }
        return lhs.1 < rhs.1
    }
    var result: [Point] = []
    var lastS = -Double.greatestFiniteMagnitude
    for (point, s) in sorted {
        if s + epsilon >= lastS {
            result.append(point)
            lastS = s
        }
    }
    return result
}

private func projectToCenterlineS(point: Point, samples: [PathDomain.Sample]) -> Double {
    guard samples.count >= 2 else { return samples.first?.s ?? 0.0 }
    var bestDist = Double.greatestFiniteMagnitude
    var bestS = samples[0].s
    for i in 0..<(samples.count - 1) {
        let a = samples[i].point
        let b = samples[i + 1].point
        let ab = b - a
        let denom = ab.dot(ab)
        let t = denom > 1.0e-9 ? max(0.0, min(1.0, (point - a).dot(ab) / denom)) : 0.0
        let proj = a + ab * t
        let dist = (point - proj).length
        if dist < bestDist {
            bestDist = dist
            bestS = ScalarMath.lerp(samples[i].s, samples[i + 1].s, t)
        }
    }
    return bestS
}

private func projectPointToLine(_ point: Point, origin: Point, axis: Point) -> Point {
    let t = (point - origin).dot(axis)
    return origin + axis * t
}

private func sampleSubpath(_ subpath: FittedSubpath, samplesPerCurve: Int) -> [Point] {
    var points: [Point] = []
    for curve in subpath.segments {
        for i in 0...samplesPerCurve {
            let t = Double(i) / Double(samplesPerCurve)
            points.append(evaluateBezier(curve, t))
        }
    }
    return points
}

private func maxSamplesPerCurve(for subpath: FittedSubpath, targetPointCap: Int) -> Int {
    let segmentCount = max(1, subpath.segments.count)
    let perCurve = targetPointCap / segmentCount
    return max(4, perCurve)
}

private func polylineHasSelfIntersection(_ points: [Point], closed: Bool) -> Bool {
    let count = points.count
    guard count >= 4 else { return false }
    let segmentCount = closed ? count : (count - 1)
    for i in 0..<segmentCount {
        let a1 = points[i]
        let a2 = points[(i + 1) % count]
        for j in (i + 1)..<segmentCount {
            if abs(i - j) <= 1 { continue }
            if closed && i == 0 && j == segmentCount - 1 { continue }
            let b1 = points[j]
            let b2 = points[(j + 1) % count]
            if segmentsIntersect(a1, a2, b1, b2) {
                return true
            }
        }
    }
    return false
}

private func segmentsIntersect(_ p1: Point, _ p2: Point, _ q1: Point, _ q2: Point) -> Bool {
    let o1 = orientation(p1, p2, q1)
    let o2 = orientation(p1, p2, q2)
    let o3 = orientation(q1, q2, p1)
    let o4 = orientation(q1, q2, p2)
    return (o1 * o2 < 0) && (o3 * o4 < 0)
}

private func orientation(_ a: Point, _ b: Point, _ c: Point) -> Double {
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

private func fitMonotoneChain(
    _ points: [Point],
    centerlineSamples: [PathDomain.Sample],
    tolerance: Double,
    depth: Int = 0
) -> [CubicBezier] {
    guard points.count >= 2 else { return [] }
    let curves = fitCurve(points, error: tolerance)
    if isMonotone(curves, centerlineSamples: centerlineSamples) || points.count <= 3 || depth >= 8 {
        return curves
    }
    let mid = points.count / 2
    let left = fitMonotoneChain(Array(points[0...mid]), centerlineSamples: centerlineSamples, tolerance: tolerance, depth: depth + 1)
    let right = fitMonotoneChain(Array(points[mid...]), centerlineSamples: centerlineSamples, tolerance: tolerance, depth: depth + 1)
    return left + right
}

private func isMonotone(_ curves: [CubicBezier], centerlineSamples: [PathDomain.Sample]) -> Bool {
    var lastS = -Double.greatestFiniteMagnitude
    let epsilon = 1.0e-6
    for curve in curves {
        for i in 0...6 {
            let t = Double(i) / 6.0
            let point = evaluateBezier(curve, t)
            let s = projectToCenterlineS(point: point, samples: centerlineSamples)
            if s + epsilon < lastS {
                return false
            }
            lastS = s
        }
    }
    return true
}

private func joinSides(_ sideA: [CubicBezier], _ sideB: [CubicBezier]) -> [CubicBezier] {
    var result: [CubicBezier] = []
    guard let startA = sideA.first?.p0 else { return sideA }
    let reversedB = reverseSegments(sideB)
    result.append(contentsOf: sideA)

    if let endA = result.last?.p3, let startB = reversedB.first?.p0 {
        if (endA - startB).length > 1.0e-6 {
            result.append(lineToCubic(from: endA, to: startB))
        }
    }
    result.append(contentsOf: reversedB)

    if let end = result.last?.p3 {
        if (end - startA).length > 1.0e-6 {
            result.append(lineToCubic(from: end, to: startA))
        }
    }
    return result
}

private struct CapInfo {
    var hasCaps: Bool
    var startCap: [Point]
    var endCap: [Point]
}

private func detectCaps(
    sideA: [Point],
    sideB: [Point],
    centerlineSamples: [PathDomain.Sample],
    fitTolerance: Double
) -> CapInfo {
    let capBand = 0.02
    let capWidth = max(0.5, fitTolerance * 2.0)
    let startCap = capPolyline(sideA: sideA, sideB: sideB, centerlineSamples: centerlineSamples, capBand: capBand, capWidth: capWidth, nearStart: true)
    let endCap = capPolyline(sideA: sideA, sideB: sideB, centerlineSamples: centerlineSamples, capBand: capBand, capWidth: capWidth, nearStart: false)
    let hasCaps = !startCap.isEmpty || !endCap.isEmpty
    return CapInfo(hasCaps: hasCaps, startCap: startCap, endCap: endCap)
}

private func capPolyline(
    sideA: [Point],
    sideB: [Point],
    centerlineSamples: [PathDomain.Sample],
    capBand: Double,
    capWidth: Double,
    nearStart: Bool
) -> [Point] {
    guard !sideA.isEmpty, !sideB.isEmpty else { return [] }
    let capA = capRange(sideA, centerlineSamples: centerlineSamples, capBand: capBand, capWidth: capWidth, nearStart: nearStart)
    let capB = capRange(sideB, centerlineSamples: centerlineSamples, capBand: capBand, capWidth: capWidth, nearStart: nearStart)
    if capA.isEmpty || capB.isEmpty { return [] }
    return capA + capB.reversed()
}

private func capRange(
    _ side: [Point],
    centerlineSamples: [PathDomain.Sample],
    capBand: Double,
    capWidth: Double,
    nearStart: Bool
) -> [Point] {
    var result: [Point] = []
    for point in side {
        let s = projectToCenterlineS(point: point, samples: centerlineSamples)
        let isCap = nearStart ? (s <= capBand) : (s >= 1.0 - capBand)
        if isCap {
            let offset = abs(offsetFromCenterline(point: point, samples: centerlineSamples))
            if offset <= capWidth {
                result.append(point)
            }
        }
    }
    return result
}

private func trimSide(_ side: [Point], capInfo: CapInfo, isStart: Bool, isEnd: Bool) -> [Point] {
    guard !side.isEmpty else { return side }
    var startIndex = 0
    var endIndex = side.count - 1
    if isStart, !capInfo.startCap.isEmpty {
        startIndex = min(side.count - 1, capInfo.startCap.count - 1)
    }
    if isEnd, !capInfo.endCap.isEmpty {
        endIndex = max(0, side.count - capInfo.endCap.count)
    }
    if startIndex >= endIndex {
        return [side.first!, side.last!]
    }
    return Array(side[startIndex...endIndex])
}

private func joinSidesWithCaps(_ sideA: [CubicBezier], _ sideB: [CubicBezier], capInfo: CapInfo) -> [CubicBezier] {
    var result: [CubicBezier] = []
    guard let startA = sideA.first?.p0 else { return sideA }
    let reversedB = reverseSegments(sideB)
    result.append(contentsOf: sideA)

    if let endA = result.last?.p3 {
        let capEnd = polylineToCubics(capInfo.endCap, from: endA, to: reversedB.first?.p0)
        result.append(contentsOf: capEnd)
    }
    result.append(contentsOf: reversedB)

    if let end = result.last?.p3 {
        let capStart = polylineToCubics(capInfo.startCap, from: end, to: startA)
        result.append(contentsOf: capStart)
    }
    return result
}

private func polylineToCubics(_ polyline: [Point], from: Point?, to: Point?) -> [CubicBezier] {
    var points = polyline
    if let from, points.first != from {
        points.insert(from, at: 0)
    }
    if let to, points.last != to {
        points.append(to)
    }
    guard points.count >= 2 else { return [] }
    var segments: [CubicBezier] = []
    for i in 0..<(points.count - 1) {
        segments.append(lineToCubic(from: points[i], to: points[i + 1]))
    }
    return segments
}

private func buildLoopFromSidesSimple(sideA: [Point], sideB: [Point]) -> [Point] {
    var points: [Point] = []
    points.append(contentsOf: sideA)
    points.append(contentsOf: sideB.reversed())
    if let first = points.first, points.last != first {
        points.append(first)
    }
    return points
}

private func lineSegmentsFromLoop(_ points: [Point]) -> [CubicBezier] {
    guard points.count >= 2 else { return [] }
    var segments: [CubicBezier] = []
    for i in 0..<(points.count - 1) {
        segments.append(lineToCubic(from: points[i], to: points[i + 1]))
    }
    return segments
}

private func offsetFromCenterline(point: Point, samples: [PathDomain.Sample]) -> Double {
    guard samples.count >= 2 else { return 0.0 }
    var bestDist = Double.greatestFiniteMagnitude
    var bestOffset = 0.0
    for i in 0..<(samples.count - 1) {
        let a = samples[i].point
        let b = samples[i + 1].point
        let ab = b - a
        let denom = ab.dot(ab)
        let t = denom > 1.0e-9 ? max(0.0, min(1.0, (point - a).dot(ab) / denom)) : 0.0
        let proj = a + ab * t
        let dist = (point - proj).length
        if dist < bestDist {
            bestDist = dist
            let tangent = samples[i].unitTangent
            let normal = tangent.leftNormal()
            bestOffset = (point - proj).dot(normal)
        }
    }
    return bestOffset
}
private func alignEndpoints(_ sideA: inout [Point], _ sideB: inout [Point]) {
    guard let startA = sideA.first, let startB = sideB.first,
          let endA = sideA.last, let endB = sideB.last else {
        return
    }
    let start = (startA + startB) * 0.5
    let end = (endA + endB) * 0.5
    sideA[0] = start
    sideB[0] = start
    sideA[sideA.count - 1] = end
    sideB[sideB.count - 1] = end
}

private func reverseSegments(_ segments: [CubicBezier]) -> [CubicBezier] {
    segments.reversed().map { segment in
        CubicBezier(p0: segment.p3, p1: segment.p2, p2: segment.p1, p3: segment.p0)
    }
}

private func lineToCubic(from: Point, to: Point) -> CubicBezier {
    let p1 = from + (to - from) * (1.0 / 3.0)
    let p2 = from + (to - from) * (2.0 / 3.0)
    return CubicBezier(p0: from, p1: p1, p2: p2, p3: to)
}

func fitCurve(_ points: [Point], error: Double) -> [CubicBezier] {
    guard points.count >= 2 else { return [] }
    let leftTangent = (points[1] - points[0]).normalized() ?? Point(x: 1, y: 0)
    let rightTangent = (points[points.count - 2] - points.last!).normalized() ?? Point(x: -1, y: 0)
    return fitCubic(points, leftTangent, rightTangent, error)
}

private func fitCubic(_ points: [Point], _ leftTangent: Point, _ rightTangent: Point, _ error: Double) -> [CubicBezier] {
    let n = points.count
    if n == 2 {
        let dist = (points[1] - points[0]).length / 3.0
        let p1 = points[0] + leftTangent * dist
        let p2 = points[1] + rightTangent * dist
        return [CubicBezier(p0: points[0], p1: p1, p2: p2, p3: points[1])]
    }

    var u = chordLengthParameterize(points)
    var bezier = generateBezier(points, u, leftTangent, rightTangent)
    var (maxError, splitPoint) = computeMaxError(points, bezier, u)

    if maxError < error {
        return [bezier]
    }

    for _ in 0..<4 {
        u = reparameterize(points, bezier, u)
        bezier = generateBezier(points, u, leftTangent, rightTangent)
        let result = computeMaxError(points, bezier, u)
        maxError = result.0
        splitPoint = result.1
        if maxError < error {
            return [bezier]
        }
    }

    let centerTangent = (points[splitPoint - 1] - points[splitPoint + 1]).normalized() ?? Point(x: 1, y: 0)
    let left = fitCubic(Array(points[0...splitPoint]), leftTangent, centerTangent, error)
    let right = fitCubic(Array(points[splitPoint...]), centerTangent * -1.0, rightTangent, error)
    return left + right
}

private func chordLengthParameterize(_ points: [Point]) -> [Double] {
    var u: [Double] = [0.0]
    for i in 1..<points.count {
        let dist = (points[i] - points[i - 1]).length
        u.append(u.last! + dist)
    }
    let total = u.last ?? 1.0
    if total <= 0.0 { return u.map { _ in 0.0 } }
    return u.map { $0 / total }
}

private func generateBezier(_ points: [Point], _ u: [Double], _ leftTangent: Point, _ rightTangent: Point) -> CubicBezier {
    let p0 = points.first!
    let p3 = points.last!

    var c00 = 0.0
    var c01 = 0.0
    var c11 = 0.0
    var x0 = 0.0
    var x1 = 0.0

    for i in 1..<(points.count - 1) {
        let t = u[i]
        let b0 = pow(1.0 - t, 3.0)
        let b1 = 3.0 * pow(1.0 - t, 2.0) * t
        let b2 = 3.0 * (1.0 - t) * t * t
        let b3 = t * t * t

        let a1 = leftTangent * b1
        let a2 = rightTangent * b2

        c00 += a1.dot(a1)
        c01 += a1.dot(a2)
        c11 += a2.dot(a2)

        let tmp = points[i] - (p0 * (b0 + b1) + p3 * (b2 + b3))
        x0 += a1.dot(tmp)
        x1 += a2.dot(tmp)
    }

    let det = c00 * c11 - c01 * c01
    let alpha1: Double
    let alpha2: Double
    if abs(det) > 1.0e-9 {
        alpha1 = (x0 * c11 - x1 * c01) / det
        alpha2 = (c00 * x1 - c01 * x0) / det
    } else {
        let dist = (p3 - p0).length / 3.0
        alpha1 = dist
        alpha2 = dist
    }

    let segLength = (p3 - p0).length
    let eps = 1.0e-6 * segLength
    let a1 = (alpha1 < eps || alpha2 < eps) ? segLength / 3.0 : alpha1
    let a2 = (alpha1 < eps || alpha2 < eps) ? segLength / 3.0 : alpha2

    let p1 = p0 + leftTangent * a1
    let p2 = p3 + rightTangent * a2
    return CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
}

private func computeMaxError(_ points: [Point], _ bezier: CubicBezier, _ u: [Double]) -> (Double, Int) {
    var maxDist = 0.0
    var splitPoint = points.count / 2
    for i in 1..<(points.count - 1) {
        let p = evaluateBezier(bezier, u[i])
        let dist = (p - points[i]).length
        if dist > maxDist {
            maxDist = dist
            splitPoint = i
        }
    }
    return (maxDist, splitPoint)
}

private func evaluateBezier(_ bezier: CubicBezier, _ t: Double) -> Point {
    let mt = 1.0 - t
    let b0 = mt * mt * mt
    let b1 = 3.0 * mt * mt * t
    let b2 = 3.0 * mt * t * t
    let b3 = t * t * t
    return bezier.p0 * b0 + bezier.p1 * b1 + bezier.p2 * b2 + bezier.p3 * b3
}

private func reparameterize(_ points: [Point], _ bezier: CubicBezier, _ u: [Double]) -> [Double] {
    var result: [Double] = []
    result.reserveCapacity(points.count)
    for i in 0..<points.count {
        let t = newtonRaphsonRootFind(bezier, points[i], u[i])
        result.append(t)
    }
    return result
}

private func newtonRaphsonRootFind(_ bezier: CubicBezier, _ point: Point, _ t: Double) -> Double {
    let q = evaluateBezier(bezier, t)
    let q1 = evaluateBezierDerivative(bezier, t)
    let q2 = evaluateBezierSecondDerivative(bezier, t)
    let numerator = (q - point).dot(q1)
    let denominator = q1.dot(q1) + (q - point).dot(q2)
    if abs(denominator) < 1.0e-9 { return t }
    return min(max(t - numerator / denominator, 0.0), 1.0)
}

private func evaluateBezierDerivative(_ bezier: CubicBezier, _ t: Double) -> Point {
    let mt = 1.0 - t
    return (bezier.p1 - bezier.p0) * (3.0 * mt * mt)
        + (bezier.p2 - bezier.p1) * (6.0 * mt * t)
        + (bezier.p3 - bezier.p2) * (3.0 * t * t)
}

private func evaluateBezierSecondDerivative(_ bezier: CubicBezier, _ t: Double) -> Point {
    let mt = 1.0 - t
    return (bezier.p2 - bezier.p1 * 2.0 + bezier.p0) * (6.0 * mt)
        + (bezier.p3 - bezier.p2 * 2.0 + bezier.p1) * (6.0 * t)
}

private func distancePointToSegment(_ p: Point, _ a: Point, _ b: Point) -> Double {
    let ab = b - a
    let ap = p - a
    let denom = ab.dot(ab)
    if denom <= 1.0e-12 { return ap.length }
    let t = max(0.0, min(1.0, ap.dot(ab) / denom))
    let proj = a + ab * t
    return (p - proj).length
}
