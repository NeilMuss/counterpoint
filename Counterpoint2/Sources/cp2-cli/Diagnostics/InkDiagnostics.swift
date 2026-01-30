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
}

struct ResolvedHeartline {
    var name: String
    var subpaths: [[InkSegment]]
    var parts: [HeartlinePart]
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
    for partName in heartline.parts {
        guard let primitive = ink.entries[partName] else {
            throw InkContinuityError.missingPart(name: name, part: partName)
        }
        switch primitive {
        case .line(let line):
            parts.append(HeartlinePart(name: partName, segments: [.line(line)]))
        case .cubic(let cubic):
            parts.append(HeartlinePart(name: partName, segments: [.cubic(cubic)]))
        case .path(let path):
            parts.append(HeartlinePart(name: partName, segments: path.segments))
        case .heartline:
            throw InkContinuityError.nestedHeartline(name: name, part: partName)
        }
    }
    var subpaths: [[InkSegment]] = []
    var current: [InkSegment] = []
    let allowGaps = heartline.allowGaps ?? false
    for (index, part) in parts.enumerated() {
        for (segmentIndex, segment) in part.segments.enumerated() {
            if let last = current.last {
                let dist = (inkSegmentEnd(last) - inkSegmentStart(segment)).length
                if dist > 1.0e-4 {
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
    }
    if !current.isEmpty {
        subpaths.append(current)
    }
    if subpaths.isEmpty {
        throw InkContinuityError.emptyHeartline(name: name)
    }
    return ResolvedHeartline(name: name, subpaths: subpaths, parts: parts)
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
