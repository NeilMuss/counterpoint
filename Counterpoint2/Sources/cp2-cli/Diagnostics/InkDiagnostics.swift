import Foundation
import CP2Geometry
import CP2Skeleton

enum InkContinuityError: Error, CustomStringConvertible {
    case discontinuity(name: String, index: Int, dist: Double)
    case missingPart(name: String, part: String)
    case cyclicReference(name: String, part: String)
    case nestedHeartline(name: String, part: String)
    case emptyHeartline(name: String)
    case missingInk(name: String)

    var description: String {
        switch self {
        case .discontinuity(let name, let index, let dist):
            let distText = String(format: "%.6f", dist)
            return "ink continuity mismatch: \(name) segments \(index)->\(index + 1) dist=\(distText)"
        case .missingPart(let name, let part):
            return "heartline missing part: \(name) -> \(part)"
        case .cyclicReference(let name, let part):
            return "heartline cycle detected: \(name) -> \(part)"
        case .nestedHeartline(let name, let part):
            return "heartline nested heartline: \(name) -> \(part)"
        case .emptyHeartline(let name):
            return "heartline empty resolved path: \(name)"
        case .missingInk(let name):
            return "missing ink entry: \(name)"
        }
    }

    var localizedDescription: String {
        description
    }
}

func inkSegmentStart(_ segment: InkSegment) -> Vec2 {
    switch segment {
    case .line(let line):
        return vec(line.p0)
    case .cubic(let cubic):
        return vec(cubic.p0)
    }
}

func inkSegmentEnd(_ segment: InkSegment) -> Vec2 {
    switch segment {
    case .line(let line):
        return vec(line.p1)
    case .cubic(let cubic):
        return vec(cubic.p3)
    }
}

func formatVec2(_ point: Vec2) -> String {
    String(format: "(%.6f,%.6f)", point.x, point.y)
}

func cubicForSegment(_ segment: InkSegment) -> CubicBezier2 {
    switch segment {
    case .line(let line):
        return lineCubic(from: vec(line.p0), to: vec(line.p1))
    case .cubic(let cubic):
        return CubicBezier2(
            p0: vec(cubic.p0),
            p1: vec(cubic.p1),
            p2: vec(cubic.p2),
            p3: vec(cubic.p3)
        )
    }
}

func vec(_ point: InkPoint) -> Vec2 {
    Vec2(point.x, point.y)
}

func lineCubic(from start: Vec2, to end: Vec2) -> CubicBezier2 {
    let delta = end - start
    let p1 = start + delta * (1.0 / 3.0)
    let p2 = start + delta * (2.0 / 3.0)
    return CubicBezier2(p0: start, p1: p1, p2: p2, p3: end)
}

struct HeartlinePart {
    var name: String
    var segments: [InkSegment]
    var joinKnot: HeartlineJoinKnot?
}

struct ResolvedHeartline {
    var name: String
    var subpaths: [[InkSegment]]
    var parts: [HeartlinePart]
    var fillets: [HeartlineFilletDebug]
}

struct HeartlineFilletDebug {
    var radius: Double
    var start: Vec2
    var end: Vec2
    var startTangent: Vec2
    var endTangent: Vec2
    var bridge: InkSegment
}

func resolveHeartline(
    name: String,
    heartline: Heartline,
    ink: Ink,
    strict: Bool,
    warn: (String) -> Void
) throws -> ResolvedHeartline {
    guard !heartline.parts.isEmpty else {
        throw InkContinuityError.emptyHeartline(name: name)
    }
    var parts: [HeartlinePart] = []
    var visited = Set<String>()
    visited.insert(name)
    for partRef in heartline.parts {
        let partName = partRef.partName
        guard let primitive = ink.entries[partName] else {
            throw InkContinuityError.missingPart(name: name, part: partName)
        }
        switch primitive {
        case .line(let line):
            parts.append(HeartlinePart(name: partName, segments: [.line(line)], joinKnot: partRef.joinKnot))
        case .cubic(let cubic):
            parts.append(HeartlinePart(name: partName, segments: [.cubic(cubic)], joinKnot: partRef.joinKnot))
        case .path(let path):
            parts.append(HeartlinePart(name: partName, segments: path.segments, joinKnot: partRef.joinKnot))
        case .heartline:
            throw InkContinuityError.nestedHeartline(name: name, part: partName)
        }
    }
    var subpaths: [[InkSegment]] = []
    var current: [InkSegment] = []
    let allowGaps = heartline.allowGaps ?? false
    var fillets: [HeartlineFilletDebug] = []
    var lastPartSegments: [InkSegment] = []
    for (index, part) in parts.enumerated() {
        if index > 0, case .fillet(let radius) = (part.joinKnot ?? .smooth) {
            let fillet = makeHeartlineFillet(
                from: lastPartSegments,
                to: part.segments,
                radius: radius,
                samplesPerSegment: 64
            )
            if let fillet {
                if lastPartSegments.count <= current.count {
                    current.removeLast(lastPartSegments.count)
                } else {
                    current.removeAll()
                }
                current.append(contentsOf: fillet.trimmedA)
                current.append(fillet.bridge)
                current.append(contentsOf: fillet.trimmedB)
                fillets.append(fillet.debug)
                lastPartSegments = fillet.trimmedB
                continue
            }
        }
        for (segmentIndex, segment) in part.segments.enumerated() {
            if let last = current.last {
                let dist = (inkSegmentEnd(last) - inkSegmentStart(segment)).length
                let hasFillet = (part.joinKnot != nil && {
                    if case .fillet = part.joinKnot! { return true }
                    return false
                }())
                if dist > 1.0e-4, !hasFillet {
                    let distText = String(format: "%.6f", dist)
                    let message = "heartline continuity warning: \(name) part \(part.name) seg=\(segmentIndex) dist=\(distText)"
                    if strict {
                        throw InkContinuityError.discontinuity(name: name, index: index, dist: dist)
                    } else {
                        warn(message)
                    }
                    if !allowGaps {
                        subpaths.append(current)
                        current = []
                    }
                }
            }
            current.append(segment)
        }
        lastPartSegments = part.segments
    }
    if !current.isEmpty {
        subpaths.append(current)
    }
    if subpaths.isEmpty {
        throw InkContinuityError.emptyHeartline(name: name)
    }
    return ResolvedHeartline(name: name, subpaths: subpaths, parts: parts, fillets: fillets)
}

private struct HeartlineFilletResult {
    var trimmedA: [InkSegment]
    var trimmedB: [InkSegment]
    var bridge: InkSegment
    var debug: HeartlineFilletDebug
}

private func makeHeartlineFillet(
    from partA: [InkSegment],
    to partB: [InkSegment],
    radius: Double,
    samplesPerSegment: Int
) -> HeartlineFilletResult? {
    guard radius > Epsilon.defaultValue else { return nil }
    let cubicsA = partA.map { cubicForSegment($0) }
    let cubicsB = partB.map { cubicForSegment($0) }
    guard !cubicsA.isEmpty, !cubicsB.isEmpty else { return nil }
    let pathA = SkeletonPath(segments: cubicsA)
    let pathB = SkeletonPath(segments: cubicsB)
    let paramA = SkeletonPathParameterization(path: pathA, samplesPerSegment: samplesPerSegment)
    let paramB = SkeletonPathParameterization(path: pathB, samplesPerSegment: samplesPerSegment)
    let lenA = paramA.totalLength
    let lenB = paramB.totalLength
    let d = min(radius, 0.25 * lenA, 0.25 * lenB)
    if d <= Epsilon.defaultValue { return nil }
    let tA = max(0.0, min(1.0, (lenA - d) / lenA))
    let tB = max(0.0, min(1.0, d / lenB))
    let aPos = paramA.position(globalT: tA)
    let bPos = paramB.position(globalT: tB)
    let aTan = paramA.tangent(globalT: tA).normalized()
    let bTan = paramB.tangent(globalT: tB).normalized()
    let h = min(d, 0.5 * min(lenA, lenB))
    let p1 = aPos + aTan * h
    let p2 = bPos - bTan * h
    let bridge = InkSegment.cubic(
        InkCubic(
            p0: inkPoint(aPos),
            p1: inkPoint(p1),
            p2: inkPoint(p2),
            p3: inkPoint(bPos)
        )
    )
    let trimmedA = trimSegments(partA, upToGlobalT: tA, samplesPerSegment: samplesPerSegment)
    let trimmedB = trimSegments(partB, fromGlobalT: tB, samplesPerSegment: samplesPerSegment)
    let debug = HeartlineFilletDebug(
        radius: d,
        start: aPos,
        end: bPos,
        startTangent: aTan,
        endTangent: bTan,
        bridge: bridge
    )
    return HeartlineFilletResult(trimmedA: trimmedA, trimmedB: trimmedB, bridge: bridge, debug: debug)
}

private func trimSegments(
    _ segments: [InkSegment],
    upToGlobalT t: Double,
    samplesPerSegment: Int
) -> [InkSegment] {
    let cubics = segments.map { cubicForSegment($0) }
    guard !cubics.isEmpty else { return [] }
    let path = SkeletonPath(segments: cubics)
    let param = SkeletonPathParameterization(path: path, samplesPerSegment: samplesPerSegment)
    let mapped = param.map(globalT: t)
    var result: [InkSegment] = []
    for i in 0..<mapped.segmentIndex {
        result.append(cubicSegment(cubics[i]))
    }
    let segment = cubics[mapped.segmentIndex]
    let split = splitCubic(segment, t: mapped.localU)
    result.append(cubicSegment(split.left))
    return result
}

private func trimSegments(
    _ segments: [InkSegment],
    fromGlobalT t: Double,
    samplesPerSegment: Int
) -> [InkSegment] {
    let cubics = segments.map { cubicForSegment($0) }
    guard !cubics.isEmpty else { return [] }
    let path = SkeletonPath(segments: cubics)
    let param = SkeletonPathParameterization(path: path, samplesPerSegment: samplesPerSegment)
    let mapped = param.map(globalT: t)
    var result: [InkSegment] = []
    let segment = cubics[mapped.segmentIndex]
    let split = splitCubic(segment, t: mapped.localU)
    result.append(cubicSegment(split.right))
    if mapped.segmentIndex + 1 < cubics.count {
        for i in (mapped.segmentIndex + 1)..<cubics.count {
            result.append(cubicSegment(cubics[i]))
        }
    }
    return result
}

private func cubicSegment(_ cubic: CubicBezier2) -> InkSegment {
    InkSegment.cubic(
        InkCubic(
            p0: inkPoint(cubic.p0),
            p1: inkPoint(cubic.p1),
            p2: inkPoint(cubic.p2),
            p3: inkPoint(cubic.p3)
        )
    )
}

private func inkPoint(_ vec: Vec2) -> InkPoint {
    InkPoint(x: vec.x, y: vec.y)
}

private func splitCubic(_ cubic: CubicBezier2, t: Double) -> (left: CubicBezier2, right: CubicBezier2) {
    let p0 = cubic.p0
    let p1 = cubic.p1
    let p2 = cubic.p2
    let p3 = cubic.p3
    let a = p0.lerp(to: p1, t: t)
    let b = p1.lerp(to: p2, t: t)
    let c = p2.lerp(to: p3, t: t)
    let d = a.lerp(to: b, t: t)
    let e = b.lerp(to: c, t: t)
    let f = d.lerp(to: e, t: t)
    let left = CubicBezier2(p0: p0, p1: a, p2: d, p3: f)
    let right = CubicBezier2(p0: f, p1: e, p2: c, p3: p3)
    return (left, right)
}

func resolveInkSegments(
    name: String,
    ink: Ink,
    strict: Bool,
    warn: (String) -> Void
) throws -> [InkSegment] {
    guard let primitive = ink.entries[name] else {
        throw InkContinuityError.missingInk(name: name)
    }
    switch primitive {
    case .line(let line):
        return [.line(line)]
    case .cubic(let cubic):
        return [.cubic(cubic)]
    case .path(let path):
        return path.segments
    case .heartline(let heartline):
        let resolved = try resolveHeartline(
            name: name,
            heartline: heartline,
            ink: ink,
            strict: strict,
            warn: warn
        )
        let segments = resolved.subpaths.flatMap { $0 }
        if segments.isEmpty {
            throw InkContinuityError.emptyHeartline(name: name)
        }
        return segments
    }
}

func buildSkeletonPaths(
    name: String,
    primitive: InkPrimitive,
    strict: Bool,
    epsilon: Double,
    warn: (String) -> Void
) throws -> [SkeletonPath] {
    switch primitive {
    case .line(let line):
        let segment = lineCubic(from: vec(line.p0), to: vec(line.p1))
        return [SkeletonPath(segments: [segment])]
    case .cubic(let cubic):
        let segment = CubicBezier2(
            p0: vec(cubic.p0),
            p1: vec(cubic.p1),
            p2: vec(cubic.p2),
            p3: vec(cubic.p3)
        )
        return [SkeletonPath(segments: [segment])]
    case .path(let path):
        var paths: [SkeletonPath] = []
        var currentSegments: [CubicBezier2] = []
        for (index, segment) in path.segments.enumerated() {
            if index > 0 {
                let prev = path.segments[index - 1]
                let dist = (inkSegmentEnd(prev) - inkSegmentStart(segment)).length
                if dist > epsilon {
                    let distText = String(format: "%.6f", dist)
                    let message = "ink continuity warning: \(name) segments \(index - 1)->\(index) end=\(formatVec2(inkSegmentEnd(prev))) start=\(formatVec2(inkSegmentStart(segment))) dist=\(distText)"
                    if strict {
                        throw InkContinuityError.discontinuity(name: name, index: index - 1, dist: dist)
                    } else {
                        warn(message)
                        if !currentSegments.isEmpty {
                            paths.append(SkeletonPath(segments: currentSegments))
                            currentSegments = []
                        }
                    }
                }
            }
            currentSegments.append(cubicForSegment(segment))
        }
        if !currentSegments.isEmpty {
            paths.append(SkeletonPath(segments: currentSegments))
        }
        return paths
    case .heartline:
        return []
    }
}

func pickInkPrimitive(_ ink: Ink?, name: String?) -> (name: String, primitive: InkPrimitive)? {
    guard let ink else {
        return nil
    }
    if let name {
        if let primitive = ink.entries[name] {
            return (name, primitive)
        }
        return nil
    }
    if let heartline = ink.entries["J_heartline"] {
        return ("J_heartline", heartline)
    }
    if let stem = ink.stem {
        return ("stem", stem)
    }
    if let firstKey = ink.entries.keys.sorted().first, let primitive = ink.entries[firstKey] {
        return (firstKey, primitive)
    }
    return nil
}

func pathFromInk(_ ink: Ink?) -> SkeletonPath? {
    guard let stem = ink?.stem else {
        return nil
    }
    switch stem {
    case .line(let line):
        let cubic = lineCubic(from: vec(line.p0), to: vec(line.p1))
        return SkeletonPath(segments: [cubic])
    case .cubic(let cubic):
        let segment = CubicBezier2(
            p0: vec(cubic.p0),
            p1: vec(cubic.p1),
            p2: vec(cubic.p2),
            p3: vec(cubic.p3)
        )
        return SkeletonPath(segments: [segment])
    case .path:
        return nil
    case .heartline:
        return nil
    }
}
