import Foundation
import CP2Geometry

public struct Segment2: Equatable, Codable {
    public let a: Vec2
    public let b: Vec2

    public init(_ a: Vec2, _ b: Vec2) {
        self.a = a
        self.b = b
    }
}

public struct SweepStyle: Equatable, Codable {
    public let width: Double
    public let height: Double
    public let angle: Double
    public let offset: Double   // reserved; can be 0 for now

    public init(width: Double, height: Double, angle: Double, offset: Double) {
        self.width = width
        self.height = height
        self.angle = angle
        self.offset = offset
    }
}

public func boundarySoupGeneral(
    path: SkeletonPath,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    warpGT: (Double) -> Double = { $0 },
    styleAtGT: (Double) -> SweepStyle
) -> [Segment2] {
    let param = SkeletonPathParameterization(path: path, samplesPerSegment: arcSamplesPerSegment)

    let samples = adaptiveSampling
        ? mergeWithUniformSamples(
            AdaptiveSampler.sampleParameter(
                maxDepth: maxDepth,
                flatnessEps: flatnessEps,
                maxSamples: maxSamples,
                evaluate: { param.position(globalT: $0) }
            ),
            minCount: max(2, sampleCount)
        )
        : uniformSamples(count: max(2, sampleCount))

    let count = max(2, samples.count)

    var left: [Vec2] = []
    var right: [Vec2] = []
    left.reserveCapacity(count)
    right.reserveCapacity(count)

    for gt in samples {
        let point = param.position(globalT: gt)
        let tangent = param.tangent(globalT: gt).normalized()
        let normal = Vec2(-tangent.y, tangent.x)

        let warped = warpGT(gt)
        let style = styleAtGT(warped)

        // Offset reserved (0 by default). When you wire offset later,
        // this will become visible immediately.
        let center = point + normal * style.offset

        let corners = rectangleCorners(
            center: center,
            tangent: tangent,
            normal: normal,
            width: style.width,
            height: style.height,
            effectiveAngle: style.angle
        )

        var minDot = Double.greatestFiniteMagnitude
        var maxDot = -Double.greatestFiniteMagnitude
        var leftPoint = center
        var rightPoint = center

        for corner in corners {
            let d = corner.dot(normal)
            if d < minDot {
                minDot = d
                leftPoint = corner
            }
            if d > maxDot {
                maxDot = d
                rightPoint = corner
            }
        }

        left.append(leftPoint)
        right.append(rightPoint)
    }

    var segments: [Segment2] = []
    segments.reserveCapacity(count * 2 + 2)

    for i in 0..<(count - 1) {
        segments.append(Segment2(left[i], left[i + 1]))
    }
    for i in stride(from: count - 1, to: 0, by: -1) {
        segments.append(Segment2(right[i], right[i - 1]))
    }
    segments.append(Segment2(left[0], right[0]))
    segments.append(Segment2(right[count - 1], left[count - 1]))

    return segments
}


public func boundarySoup(
    path: SkeletonPath,
    width: Double,
    height: Double,
    effectiveAngle: Double,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        styleAtGT: { _ in SweepStyle(width: width, height: height, angle: effectiveAngle, offset: 0.0) }
    )
}


public func boundarySoupVariableWidth(
    path: SkeletonPath,
    height: Double,
    effectiveAngle: Double,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    widthAtT: (Double) -> Double
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        styleAtGT: { t in SweepStyle(width: widthAtT(t), height: height, angle: effectiveAngle, offset: 0.0) }
    )
}


public func boundarySoupVariableWidthAngle(
    path: SkeletonPath,
    height: Double,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    widthAtT: (Double) -> Double,
    angleAtT: (Double) -> Double
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        styleAtGT: { t in SweepStyle(width: widthAtT(t), height: height, angle: angleAtT(t), offset: 0.0) }
    )
}


public func boundarySoupVariableWidthAngleAlpha(
    path: SkeletonPath,
    height: Double,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    widthAtT: (Double) -> Double,
    angleAtT: (Double) -> Double,
    alphaAtT: (Double) -> Double,
    alphaStart: Double
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        warpGT: { gt in applyAlphaWarp(t: gt, alphaValue: alphaAtT(gt), alphaStart: alphaStart) },
        styleAtGT: { t in SweepStyle(width: widthAtT(t), height: height, angle: angleAtT(t), offset: 0.0) }
    )
}


private func rectangleCorners(
    center: Vec2,
    tangent: Vec2,
    normal: Vec2,
    width: Double,
    height: Double,
    effectiveAngle: Double
) -> [Vec2] {
    let halfW = width * 0.5
    let halfH = height * 0.5
    let localCorners: [Vec2] = [
        Vec2(-halfW, -halfH),
        Vec2(halfW, -halfH),
        Vec2(halfW, halfH),
        Vec2(-halfW, halfH)
    ]
    let cosA = cos(effectiveAngle)
    let sinA = sin(effectiveAngle)
    return localCorners.map { corner in
        let rotated = Vec2(
            corner.x * cosA - corner.y * sinA,
            corner.x * sinA + corner.y * cosA
        )
        let world = tangent * rotated.y + normal * rotated.x
        return center + world
    }
}

private func applyAlphaWarp(t: Double, alphaValue: Double, alphaStart: Double) -> Double {
    if t <= alphaStart || abs(alphaValue) <= Epsilon.defaultValue {
        return t
    }
    let span = max(Epsilon.defaultValue, 1.0 - alphaStart)
    let phase = max(0.0, min(1.0, (t - alphaStart) / span))
    let exponent = max(0.05, 1.0 + alphaValue)
    let biased = pow(phase, exponent)
    return alphaStart + biased * span
}

private func uniformSamples(count: Int) -> [Double] {
    let clamped = max(2, count)
    return (0..<clamped).map { Double($0) / Double(clamped - 1) }
}

private func mergeWithUniformSamples(_ samples: [Double], minCount: Int) -> [Double] {
    let minSamples = max(2, minCount)
    if samples.count >= minSamples {
        return samples
    }
    let combined = (samples + uniformSamples(count: minSamples)).sorted()
    var result: [Double] = []
    result.reserveCapacity(combined.count)
    var last: Double? = nil
    for t in combined {
        if let previous = last, abs(t - previous) <= 1.0e-9 {
            continue
        }
        result.append(t)
        last = t
    }
    return result
}

public func traceLoops(segments: [Segment2], eps: Double) -> [[Vec2]] {
    guard !segments.isEmpty else { return [] }

    var pointForKey: [SnapKey: Vec2] = [:]
    var adjacency: [SnapKey: [SnapKey]] = [:]
    var edges: Set<EdgeKey> = []

    for seg in segments {
        let aKey = Epsilon.snapKey(seg.a, eps: eps)
        let bKey = Epsilon.snapKey(seg.b, eps: eps)
        pointForKey[aKey] = pointForKey[aKey] ?? seg.a
        pointForKey[bKey] = pointForKey[bKey] ?? seg.b
        adjacency[aKey, default: []].append(bKey)
        adjacency[bKey, default: []].append(aKey)
        edges.insert(EdgeKey(aKey, bKey))
    }

    for (key, list) in adjacency {
        adjacency[key] = list.sorted(by: snapKeyLess)
    }

    var rings: [[SnapKey]] = []
    while let startEdge = edges.sorted(by: edgeLess).first {
        edges.remove(startEdge)
        let start = startEdge.a
        let next = startEdge.b
        var ring: [SnapKey] = [start, next]
        var prev = start
        var curr = next
        while curr != start {
            guard let neighbors = adjacency[curr] else { break }
            var candidates = neighbors.filter { edges.contains(EdgeKey(curr, $0)) }
            if candidates.count > 1 {
                let nonPrev = candidates.filter { $0 != prev }
                candidates = nonPrev.isEmpty ? candidates : nonPrev
            }
            guard let chosen = candidates.sorted(by: snapKeyLess).first else { break }
            edges.remove(EdgeKey(curr, chosen))
            ring.append(chosen)
            prev = curr
            curr = chosen
        }
        if ring.first != ring.last {
            ring.append(ring.first!)
        }
        rings.append(ring)
    }

    let worldRings = rings.map { ringKeys in
        ringKeys.compactMap { pointForKey[$0] }
    }.map(dedupRing)
    return worldRings.filter { $0.count >= 4 }
}

public func signedArea(_ ring: [Vec2]) -> Double {
    guard ring.count >= 3 else { return 0.0 }
    var area = 0.0
    for i in 0..<(ring.count - 1) {
        let a = ring[i]
        let b = ring[i + 1]
        area += (a.x * b.y - b.x * a.y)
    }
    return area * 0.5
}

private struct EdgeKey: Hashable {
    let a: SnapKey
    let b: SnapKey

    init(_ p0: SnapKey, _ p1: SnapKey) {
        if snapKeyLess(p0, p1) {
            a = p0
            b = p1
        } else {
            a = p1
            b = p0
        }
    }
}

private func snapKeyLess(_ a: SnapKey, _ b: SnapKey) -> Bool {
    if a.x != b.x { return a.x < b.x }
    return a.y < b.y
}

private func edgeLess(_ a: EdgeKey, _ b: EdgeKey) -> Bool {
    if snapKeyLess(a.a, b.a) { return true }
    if snapKeyLess(b.a, a.a) { return false }
    return snapKeyLess(a.b, b.b)
}

private func dedupRing(_ ring: [Vec2]) -> [Vec2] {
    guard !ring.isEmpty else { return [] }
    var result: [Vec2] = [ring[0]]
    for point in ring.dropFirst() where !Epsilon.approxEqual(point, result.last!) {
        result.append(point)
    }
    if let first = result.first, let last = result.last, !Epsilon.approxEqual(first, last) {
        result.append(first)
    }
    return result
}
