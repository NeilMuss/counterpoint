import Foundation
import CP2Geometry
import CP2Skeleton

struct DebugOverlay {
    var svg: String
    var bounds: AABB
}

func mergeDebugOverlays(_ overlays: [DebugOverlay]) -> DebugOverlay? {
    guard let first = overlays.first else { return nil }
    var bounds = first.bounds
    for overlay in overlays.dropFirst() {
        bounds = bounds.union(overlay.bounds)
    }
    let svg = overlays.map { $0.svg }.joined(separator: "\n")
    return DebugOverlay(svg: svg, bounds: bounds)
}

func sampleInkCubicPoints(_ cubic: InkCubic, steps: Int) -> [Vec2] {
    let count = max(2, steps)
    var points: [Vec2] = []
    points.reserveCapacity(count)
    let p0 = vec(cubic.p0)
    let p1 = vec(cubic.p1)
    let p2 = vec(cubic.p2)
    let p3 = vec(cubic.p3)
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        let mt = 1.0 - t
        let mt2 = mt * mt
        let t2 = t * t
        let a = p0 * (mt2 * mt)
        let b = p1 * (3.0 * mt2 * t)
        let c = p2 * (3.0 * mt * t2)
        let d = p3 * (t2 * t)
        points.append(a + b + c + d)
    }
    return points
}

func debugOverlayForInk(_ ink: InkPrimitive, steps: Int) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
    func addPoint(_ p: Vec2, radius: Double, fill: String) {
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.1f\" fill=\"%@\" stroke=\"none\"/>", p.x, p.y, radius, fill))
        bounds.expand(by: p)
    }
    func addLine(_ a: Vec2, _ b: Vec2, stroke: String, width: Double) {
        svgParts.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"%@\" stroke-width=\"%.1f\"/>", a.x, a.y, b.x, b.y, stroke, width))
        bounds.expand(by: a)
        bounds.expand(by: b)
    }
    func addPolyline(_ points: [Vec2], stroke: String, width: Double) {
        guard let first = points.first else { return }
        var parts: [String] = []
        parts.append(String(format: "M %.4f %.4f", first.x, first.y))
        for point in points.dropFirst() {
            parts.append(String(format: "L %.4f %.4f", point.x, point.y))
        }
        let pathData = parts.joined(separator: " ")
        let strokeWidth = String(format: "%.1f", width)
        svgParts.append("<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(strokeWidth)\" />")
        for point in points {
            bounds.expand(by: point)
        }
    }

    switch ink {
    case .line(let line):
        let p0 = vec(line.p0)
        let p1 = vec(line.p1)
        addLine(p0, p1, stroke: "orange", width: 2.0)
        addPoint(p0, radius: 4.0, fill: "blue")
        addPoint(p1, radius: 4.0, fill: "blue")
    case .cubic(let cubic):
        let p0 = vec(cubic.p0)
        let p1 = vec(cubic.p1)
        let p2 = vec(cubic.p2)
        let p3 = vec(cubic.p3)
        let samples = sampleInkCubicPoints(cubic, steps: steps)
        addLine(p0, p1, stroke: "#cccccc", width: 1.0)
        addLine(p3, p2, stroke: "#cccccc", width: 1.0)
        addPolyline(samples, stroke: "orange", width: 2.0)
        addPoint(p0, radius: 4.0, fill: "blue")
        addPoint(p3, radius: 4.0, fill: "blue")
        addPoint(p1, radius: 4.0, fill: "red")
        addPoint(p2, radius: 4.0, fill: "red")
    case .path(let path):
        return debugOverlayForInkPath(path, steps: steps)
    case .heartline:
        return DebugOverlay(svg: "<g id=\"debug\"></g>", bounds: AABB.empty)
    }

    let svg = """
  <g id="debug">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func debugOverlayForInkPath(_ path: InkPath, steps: Int) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
    func addPoint(_ p: Vec2, radius: Double, fill: String) {
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.1f\" fill=\"%@\" stroke=\"none\"/>", p.x, p.y, radius, fill))
        bounds.expand(by: p)
    }
    func addLine(_ a: Vec2, _ b: Vec2, stroke: String, width: Double) {
        svgParts.append(String(format: "<line x1=\"%.4f\" y1=\"\(String(format: "%.4f", a.y))\" x2=\"\(String(format: "%.4f", b.x))\" y2=\"\(String(format: "%.4f", b.y))\" stroke=\"\(stroke)\" stroke-width=\"\(String(format: "%.1f", width))\"/>", a.x))
        bounds.expand(by: a)
        bounds.expand(by: b)
    }
    func addPolyline(_ points: [Vec2], stroke: String, width: Double) {
        guard let first = points.first else { return }
        var parts: [String] = []
        parts.append(String(format: "M %.4f %.4f", first.x, first.y))
        for point in points.dropFirst() {
            parts.append(String(format: "L %.4f %.4f", point.x, point.y))
        }
        let pathData = parts.joined(separator: " ")
        let strokeWidth = String(format: "%.1f", width)
        svgParts.append("<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(strokeWidth)\" />")
        for point in points {
            bounds.expand(by: point)
        }
    }

    for segment in path.segments {
        switch segment {
        case .line(let line):
            let p0 = vec(line.p0)
            let p1 = vec(line.p1)
            addLine(p0, p1, stroke: "orange", width: 2.0)
            addPoint(p0, radius: 4.0, fill: "blue")
            addPoint(p1, radius: 4.0, fill: "blue")
        case .cubic(let cubic):
            let p0 = vec(cubic.p0)
            let p1 = vec(cubic.p1)
            let p2 = vec(cubic.p2)
            let p3 = vec(cubic.p3)
            let samples = sampleInkCubicPoints(cubic, steps: steps)
            addLine(p0, p1, stroke: "#cccccc", width: 1.0)
            addLine(p3, p2, stroke: "#cccccc", width: 1.0)
            addPolyline(samples, stroke: "orange", width: 2.0)
            addPoint(p0, radius: 4.0, fill: "blue")
            addPoint(p3, radius: 4.0, fill: "blue")
            addPoint(p1, radius: 4.0, fill: "red")
            addPoint(p2, radius: 4.0, fill: "red")
        }
    }

    let svg = """
  <g id="debug">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func debugOverlayForHeartline(_ resolved: ResolvedHeartline, steps: Int) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
    func addPoint(_ p: Vec2, radius: Double, fill: String) {
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.1f\" fill=\"%@\" stroke=\"none\"/>", p.x, p.y, radius, fill))
        bounds.expand(by: p)
    }
    func addLine(_ a: Vec2, _ b: Vec2, stroke: String, width: Double) {
        svgParts.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"%@\" stroke-width=\"%.1f\"/>", a.x, a.y, b.x, b.y, stroke, width))
        bounds.expand(by: a)
        bounds.expand(by: b)
    }
    func addPolyline(_ points: [Vec2], stroke: String, width: Double) {
        guard let first = points.first else { return }
        var parts: [String] = []
        parts.append(String(format: "M %.4f %.4f", first.x, first.y))
        for point in points.dropFirst() {
            parts.append(String(format: "L %.4f %.4f", point.x, point.y))
        }
        let pathData = parts.joined(separator: " ")
        let strokeWidth = String(format: "%.1f", width)
        svgParts.append("<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(strokeWidth)\" />")
        for point in points {
            bounds.expand(by: point)
        }
    }
    func addLabel(_ text: String, at point: Vec2) {
        svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"10\" fill=\"#444444\">%@</text>", point.x, point.y, text))
        bounds.expand(by: point)
    }

    for part in resolved.parts {
        var samplePoints: [Vec2] = []
        for segment in part.segments {
            switch segment {
            case .line(let line):
                let p0 = vec(line.p0)
                let p1 = vec(line.p1)
                addLine(p0, p1, stroke: "orange", width: 2.0)
                addPoint(p0, radius: 4.0, fill: "blue")
                addPoint(p1, radius: 4.0, fill: "blue")
                samplePoints.append(p0)
                samplePoints.append(p1)
            case .cubic(let cubic):
                let p0 = vec(cubic.p0)
                let p1 = vec(cubic.p1)
                let p2 = vec(cubic.p2)
                let p3 = vec(cubic.p3)
                let samples = sampleInkCubicPoints(cubic, steps: steps)
                addLine(p0, p1, stroke: "#cccccc", width: 1.0)
                addLine(p3, p2, stroke: "#cccccc", width: 1.0)
                addPolyline(samples, stroke: "orange", width: 2.0)
                addPoint(p0, radius: 4.0, fill: "blue")
                addPoint(p3, radius: 4.0, fill: "blue")
                addPoint(p1, radius: 4.0, fill: "red")
                addPoint(p2, radius: 4.0, fill: "red")
                samplePoints.append(contentsOf: samples)
            }
        }
        if !samplePoints.isEmpty {
            let mid = samplePoints[samplePoints.count / 2]
            addLabel(part.name, at: mid + Vec2(4.0, -4.0))
        }
    }

    let svg = """
  <g id="debug">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func makeRingSpineOverlay(
    rings: [[Vec2]],
    breadcrumbStep: Int = 50,
    closureEps: Double = Epsilon.defaultValue
) -> DebugOverlay {
    guard !rings.isEmpty else {
        return DebugOverlay(svg: "<g id=\"debug-ring-spine\"></g>", bounds: AABB.empty)
    }

    var bounds = AABB.empty
    var svgParts: [String] = []

    for (ringIndex, ring) in rings.enumerated() {
        guard let first = ring.first else { continue }
        var pathParts: [String] = []
        pathParts.append(String(format: "M %.4f %.4f", first.x, first.y))
        for point in ring.dropFirst() {
            pathParts.append(String(format: "L %.4f %.4f", point.x, point.y))
        }
        let pathData = pathParts.joined(separator: " ")
        svgParts.append("<path d=\"\(pathData)\" fill=\"none\" stroke=\"#00c853\" stroke-width=\"1.5\" stroke-linejoin=\"round\" stroke-linecap=\"round\" />")

        for (i, point) in ring.enumerated() {
            bounds.expand(by: point)
            if i % max(1, breadcrumbStep) == 0 {
                svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"1.8\" fill=\"#00c853\" stroke=\"none\"/>", point.x, point.y))
                svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"10\" fill=\"#111111\">%d</text>", point.x + 4.0, point.y - 4.0, i))
            }
        }

        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"4.0\" fill=\"#2962ff\" stroke=\"none\"/>", first.x, first.y))
        svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"10\" fill=\"#111111\">start</text>", first.x + 4.0, first.y - 4.0))

        if let last = ring.last {
            let closure = (last - first).length
            if closure > closureEps {
                svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"4.0\" fill=\"#d50000\" stroke=\"none\"/>", last.x, last.y))
                svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"10\" fill=\"#111111\">end d=%.4f</text>", last.x + 4.0, last.y - 4.0, closure))
            }
        }

        if ringIndex < rings.count - 1 {
            svgParts.append("<!-- ring \(ringIndex) end -->")
        }
    }

    let svg = """
  <g id="debug-ring-spine">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""

    return DebugOverlay(svg: svg, bounds: bounds)
}
