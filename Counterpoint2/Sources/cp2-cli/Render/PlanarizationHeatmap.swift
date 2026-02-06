import Foundation
import CP2Geometry
import CP2ResolveOverlap

struct PlanarizationHeatmapDebug: Equatable, Sendable {
    let vertices: [Vec2]
    let degrees: [Int]
    let maxDegree: Int
    let avgDegree: Double
}

func buildPlanarizationHeatmap(artifact: PlanarizedSegmentsArtifact) -> PlanarizationHeatmapDebug? {
    let vertices = artifact.vertices
    guard !vertices.isEmpty else { return nil }
    var degrees = Array(repeating: 0, count: vertices.count)
    for seg in artifact.segments {
        if seg.a >= 0 && seg.a < degrees.count { degrees[seg.a] += 1 }
        if seg.b >= 0 && seg.b < degrees.count { degrees[seg.b] += 1 }
    }
    let maxDegree = degrees.max() ?? 0
    let sum = degrees.reduce(0, +)
    let avg = degrees.isEmpty ? 0.0 : Double(sum) / Double(degrees.count)
    return PlanarizationHeatmapDebug(
        vertices: vertices,
        degrees: degrees,
        maxDegree: maxDegree,
        avgDegree: avg
    )
}

func debugOverlayForPlanarizationHeatmap(debug: PlanarizationHeatmapDebug) -> DebugOverlay {
    guard !debug.vertices.isEmpty, debug.vertices.count == debug.degrees.count else {
        return DebugOverlay(svg: "<g id=\"debug-planarization-heatmap\"></g>", bounds: AABB.empty)
    }
    let minDegree = debug.degrees.min() ?? 0
    let maxDegree = debug.degrees.max() ?? minDegree
    let bounds = boundsForPoints(debug.vertices)
    var lines: [String] = []
    lines.append("  <g id=\"debug-planarization-heatmap\" opacity=\"0.6\">")
    for (index, point) in debug.vertices.enumerated() {
        let degree = debug.degrees[index]
        let t: Double
        if maxDegree == minDegree {
            t = 0.0
        } else {
            t = Double(degree - minDegree) / Double(maxDegree - minDegree)
        }
        let color = heatmapColor(t: t)
        lines.append(String(format: "    <circle cx=\"%.3f\" cy=\"%.3f\" r=\"2.0\" fill=\"%@\" />", point.x, point.y, color))
    }
    lines.append("  </g>")
    return DebugOverlay(svg: lines.joined(separator: "\n"), bounds: bounds)
}

private func boundsForPoints(_ points: [Vec2]) -> AABB {
    guard let first = points.first else { return AABB.empty }
    var minP = first
    var maxP = first
    for p in points.dropFirst() {
        minP = Vec2(min(minP.x, p.x), min(minP.y, p.y))
        maxP = Vec2(max(maxP.x, p.x), max(maxP.y, p.y))
    }
    return AABB(min: minP, max: maxP)
}

private func heatmapColor(t: Double) -> String {
    let clamped = max(0.0, min(1.0, t))
    let cool = (r: 0, g: 209, b: 209)
    let mid = (r: 255, g: 208, b: 0)
    let hot = (r: 239, g: 68, b: 68)
    let r: Int
    let g: Int
    let b: Int
    if clamped <= 0.5 {
        let tt = clamped / 0.5
        r = lerp(cool.r, mid.r, tt)
        g = lerp(cool.g, mid.g, tt)
        b = lerp(cool.b, mid.b, tt)
    } else {
        let tt = (clamped - 0.5) / 0.5
        r = lerp(mid.r, hot.r, tt)
        g = lerp(mid.g, hot.g, tt)
        b = lerp(mid.b, hot.b, tt)
    }
    return String(format: "#%02X%02X%02X", r, g, b)
}

private func lerp(_ a: Int, _ b: Int, _ t: Double) -> Int {
    let value = Double(a) + (Double(b) - Double(a)) * t
    return Int(value.rounded())
}
