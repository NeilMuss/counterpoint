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

func makeKeyframesOverlay(
    params: StrokeParams,
    pathParam: SkeletonPathParameterization,
    plan: SweepPlan,
    labels: Bool
) -> DebugOverlay {
    let markerOffset = 12.0
    let triSize = 6.0
    let diamondSize = 5.0
    let circleRadius = 3.0
    let strokeWidth = 1.0
    let eps = 1.0e-9

    func normalized(_ v: Vec2, fallback: Vec2) -> Vec2 {
        let len = v.length
        if len <= eps { return fallback }
        return Vec2(v.x / len, v.y / len)
    }

    func uniqueSortedTs(_ ts: [Double]) -> [Double] {
        let sorted = ts.sorted()
        var result: [Double] = []
        for t in sorted {
            if let last = result.last, abs(t - last) <= 1.0e-9 {
                continue
            }
            result.append(t)
        }
        return result
    }

    func trianglePoints(center: Vec2, direction: Vec2, size: Double) -> [Vec2] {
        let dir = normalized(direction, fallback: Vec2(1.0, 0.0))
        let perp = Vec2(-dir.y, dir.x)
        let tip = center + dir * size
        let base = center - dir * (size * 0.6)
        let base1 = base + perp * (size * 0.6)
        let base2 = base - perp * (size * 0.6)
        return [tip, base1, base2]
    }

    func diamondPoints(center: Vec2, size: Double) -> [Vec2] {
        return [
            Vec2(center.x, center.y + size),
            Vec2(center.x + size, center.y),
            Vec2(center.x, center.y - size),
            Vec2(center.x - size, center.y)
        ]
    }

    func polygon(_ points: [Vec2], stroke: String) -> String {
        let pts = points.map { String(format: "%.4f,%.4f", $0.x, $0.y) }.joined(separator: " ")
        return "<polygon points=\"\(pts)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(String(format: "%.1f", strokeWidth))\" vector-effect=\"non-scaling-stroke\"/>"
    }

    func circle(center: Vec2, radius: Double, stroke: String) -> String {
        return String(
            format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.2f\" fill=\"none\" stroke=\"%@\" stroke-width=\"%.1f\" vector-effect=\"non-scaling-stroke\"/>",
            center.x, center.y, radius, stroke, strokeWidth
        )
    }

    func label(_ text: String, at point: Vec2) -> String {
        return String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"9\" fill=\"#111111\">%@</text>", point.x + 4.0, point.y - 4.0, text)
    }

    let styleAtGT: (Double) -> SweepStyle = { t in
        return SweepStyle(
            width: plan.scaledWidthAtT(t),
            widthLeft: plan.scaledWidthLeftAtT(t),
            widthRight: plan.scaledWidthRightAtT(t),
            height: plan.sweepHeight,
            angle: plan.thetaAtT(t),
            offset: plan.offsetAtT(t),
            angleIsRelative: plan.angleMode == .relative
        )
    }

    enum TrackKind {
        case widthLeft
        case widthRight
        case widthLegacy
        case offset
        case theta
        case alpha
    }

    struct TrackSpec {
        let kind: TrackKind
        let keyframes: [Keyframe]
        let color: String
    }

    let tracks: [TrackSpec] = [
        TrackSpec(kind: .widthLeft, keyframes: params.widthLeft?.keyframes ?? [], color: "#d32f2f"),
        TrackSpec(kind: .widthRight, keyframes: params.widthRight?.keyframes ?? [], color: "#1976d2"),
        TrackSpec(kind: .widthLegacy, keyframes: params.width?.keyframes ?? [], color: "#000000"),
        TrackSpec(kind: .offset, keyframes: params.offset?.keyframes ?? [], color: "#388e3c"),
        TrackSpec(kind: .theta, keyframes: params.theta?.keyframes ?? [], color: "#8e24aa"),
        TrackSpec(kind: .alpha, keyframes: params.alpha?.keyframes ?? [], color: "#f9a825")
    ]

    var svgParts: [String] = []
    var bounds = AABB.empty

    for track in tracks {
        guard !track.keyframes.isEmpty else { continue }
        let ts = uniqueSortedTs(track.keyframes.map { $0.t })
        for t in ts {
            let frame = railSampleFrameAtGlobalT(
                param: pathParam,
                warpGT: plan.warpT,
                styleAtGT: styleAtGT,
                gt: t,
                index: -1
            )
            let cross = normalized(frame.crossAxis, fallback: Vec2(0.0, 1.0))
            let normal = normalized(frame.normal, fallback: Vec2(-cross.y, cross.x))

            let markerPos: Vec2
            let markerSVG: String
            switch track.kind {
            case .widthLeft:
                markerPos = frame.left
                let pts = trianglePoints(center: markerPos, direction: Vec2(-cross.x, -cross.y), size: triSize)
                markerSVG = polygon(pts, stroke: track.color)
            case .widthRight:
                markerPos = frame.right
                let pts = trianglePoints(center: markerPos, direction: cross, size: triSize)
                markerSVG = polygon(pts, stroke: track.color)
            case .widthLegacy:
                markerPos = frame.center
                let pts = diamondPoints(center: markerPos, size: diamondSize)
                markerSVG = polygon(pts, stroke: track.color)
            case .offset:
                markerPos = frame.center + cross * markerOffset
                let pts = trianglePoints(center: markerPos, direction: cross, size: triSize)
                markerSVG = polygon(pts, stroke: track.color)
            case .theta:
                markerPos = frame.center + normal * markerOffset
                let pts = trianglePoints(center: markerPos, direction: normal, size: triSize)
                markerSVG = polygon(pts, stroke: track.color)
            case .alpha:
                markerPos = frame.center - normal * markerOffset
                markerSVG = circle(center: markerPos, radius: circleRadius, stroke: track.color)
            }

            svgParts.append(markerSVG)
            if labels {
                svgParts.append(label(String(format: "%.3f", t), at: markerPos))
            }
            bounds.expand(by: markerPos)
        }
    }

    let svg = """
  <g id="debug-keyframes">
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

struct RingJumpInfo {
    let ringIndex: Int
    let verts: Int
    let maxSegIndex: Int
    let aIndex: Int
    let bIndex: Int
    let a: Vec2
    let b: Vec2
    let length: Double
}

func computeRingJumps(
    rings: [[Vec2]],
    topK: Int = 1
) -> [RingJumpInfo] {
    var jumps: [RingJumpInfo] = []
    for (ringIndex, ring) in rings.enumerated() {
        guard ring.count > 1 else { continue }
        var maxLen = -Double.greatestFiniteMagnitude
        var maxIndex = 0
        var maxA = ring[0]
        var maxB = ring[0]
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            let len = (b - a).length
            if len > maxLen {
                maxLen = len
                maxIndex = i
                maxA = a
                maxB = b
            }
        }
        jumps.append(RingJumpInfo(
            ringIndex: ringIndex,
            verts: ring.count,
            maxSegIndex: maxIndex,
            aIndex: maxIndex,
            bIndex: (maxIndex + 1) % ring.count,
            a: maxA,
            b: maxB,
            length: maxLen
        ))
    }

    let sorted = jumps.sorted {
        if $0.length == $1.length {
            if $0.ringIndex == $1.ringIndex { return $0.maxSegIndex < $1.maxSegIndex }
            return $0.ringIndex < $1.ringIndex
        }
        return $0.length > $1.length
    }
    return Array(sorted.prefix(max(1, topK)))
}

func makeRingJumpOverlay(
    jumps: [RingJumpInfo]
) -> DebugOverlay {
    guard !jumps.isEmpty else {
        return DebugOverlay(svg: "<g id=\"debug-ring-jump\"></g>", bounds: AABB.empty)
    }

    var bounds = AABB.empty
    var svgParts: [String] = []
    for jump in jumps {
        let mid = (jump.a + jump.b) * 0.5
        svgParts.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"#ff1744\" stroke-width=\"6\" stroke-linecap=\"round\" opacity=\"0.9\"/>", jump.a.x, jump.a.y, jump.b.x, jump.b.y))
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"5\" fill=\"#ff1744\" stroke=\"none\"/>", jump.a.x, jump.a.y))
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"5\" fill=\"#ff1744\" stroke=\"none\"/>", jump.b.x, jump.b.y))
        svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"10\" fill=\"#111111\">a=%d</text>", jump.a.x + 4.0, jump.a.y - 4.0, jump.aIndex))
        svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"10\" fill=\"#111111\">b=%d</text>", jump.b.x + 4.0, jump.b.y - 4.0, jump.bIndex))
        svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"10\" fill=\"#111111\">k=%d len=%.4f</text>", mid.x + 4.0, mid.y - 4.0, jump.maxSegIndex, jump.length))
        svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"10\" fill=\"#111111\">ringJump verts=%d maxK=%d len=%.4f</text>", mid.x + 4.0, mid.y + 12.0, jump.verts, jump.maxSegIndex, jump.length))
        bounds.expand(by: jump.a)
        bounds.expand(by: jump.b)
        bounds.expand(by: mid)
    }

    let svg = """
  <g id="debug-ring-jump">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""

    return DebugOverlay(svg: svg, bounds: bounds)
}
