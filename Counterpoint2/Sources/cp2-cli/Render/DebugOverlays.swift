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

    for fillet in resolved.fillets {
        let bridgePoints: [Vec2]
        switch fillet.bridge {
        case .line(let line):
            bridgePoints = [vec(line.p0), vec(line.p1)]
        case .cubic(let cubic):
            bridgePoints = sampleInkCubicPoints(cubic, steps: steps)
        }
        addPolyline(bridgePoints, stroke: "#6a1b9a", width: 1.6)
        addPoint(fillet.start, radius: 3.0, fill: "#00c853")
        addPoint(fillet.end, radius: 3.0, fill: "#00c853")
        let labelPos = (fillet.start + fillet.end) * 0.5
        addLabel(String(format: "fillet %.1f", fillet.radius), at: labelPos + Vec2(4.0, -4.0))
    }

    let svg = """
  <g id="debug">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func debugOverlayForCapFillets(_ fillets: [CapFilletDebug], steps: Int) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
    func addPoint(_ p: Vec2, radius: Double, fill: String) {
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.1f\" fill=\"%@\" stroke=\"none\"/>", p.x, p.y, radius, fill))
        bounds.expand(by: p)
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
    for fillet in fillets {
        let groupId = "debug-cap-fillet-\(fillet.kind)-\(fillet.side)"
        var localParts: [String] = []
        func addLocalPoint(_ p: Vec2, radius: Double, fill: String) {
            localParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.1f\" fill=\"%@\" stroke=\"none\"/>", p.x, p.y, radius, fill))
            bounds.expand(by: p)
        }
        func addQuarterCircle(corner: Vec2, a: Vec2, c: Vec2, radius: Double, stroke: String, opacity: Double) {
            let u = (corner - a).normalized()
            let v = (c - corner).normalized()
            if u.length <= 1.0e-6 || v.length <= 1.0e-6 {
                return
            }
            let start = corner + u * radius
            let end = corner + v * radius
            let cross = u.x * v.y - u.y * v.x
            let sweep = cross >= 0 ? 1 : 0
            localParts.append(String(format: "<path d=\"M %.4f %.4f A %.2f %.2f 0 0 %d %.4f %.4f\" fill=\"none\" stroke=\"%@\" stroke-width=\"2.4\" opacity=\"%.2f\"/>", start.x, start.y, radius, radius, sweep, end.x, end.y, stroke, opacity))
            bounds.expand(by: start)
            bounds.expand(by: end)
        }
        func addLocalPolyline(_ points: [Vec2], stroke: String, width: Double) {
            guard let first = points.first else { return }
            var parts: [String] = []
            parts.append(String(format: "M %.4f %.4f", first.x, first.y))
            for point in points.dropFirst() {
                parts.append(String(format: "L %.4f %.4f", point.x, point.y))
            }
            let pathData = parts.joined(separator: " ")
            let strokeWidth = String(format: "%.1f", width)
            localParts.append("<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(strokeWidth)\" />")
            for point in points {
                bounds.expand(by: point)
            }
        }
        addLocalPoint(fillet.corner, radius: 3.0, fill: "#ff1744")
        let label = "FILLET MARKER \(fillet.kind) \(fillet.side.uppercased())"
        if fillet.success, let bridge = fillet.bridge {
            let samples = (0...steps).map { t -> Vec2 in
                let u = Double(t) / Double(steps)
                return bridge.evaluate(u)
            }
            addQuarterCircle(corner: fillet.corner, a: fillet.a, c: fillet.c, radius: 10.0, stroke: "#2e7d32", opacity: 1.0)
            addLocalPolyline(samples, stroke: "#ff6f00", width: 1.6)
            addLocalPoint(fillet.p, radius: 3.0, fill: "#00c853")
            addLocalPoint(fillet.q, radius: 3.0, fill: "#00c853")
            localParts.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"#1565c0\" stroke-width=\"1.6\"/>", fillet.p.x, fillet.p.y, fillet.q.x, fillet.q.y))
            let mid = Vec2((fillet.p.x + fillet.q.x) * 0.5, (fillet.p.y + fillet.q.y) * 0.5)
            localParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"8\" fill=\"#1565c0\">P→Q</text>", mid.x + 4.0, mid.y - 4.0))
            localParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"8\" fill=\"#2e7d32\">%@</text>", fillet.corner.x + 6.0, fillet.corner.y - 6.0, label))
        } else if let failure = fillet.failureReason {
            addQuarterCircle(corner: fillet.corner, a: fillet.a, c: fillet.c, radius: 10.0, stroke: "#b0bec5", opacity: 0.6)
            let size: Double = 6.0
            let x0 = fillet.corner.x - size
            let y0 = fillet.corner.y - size
            let x1 = fillet.corner.x + size
            let y1 = fillet.corner.y + size
            localParts.append(String(format: "<path d=\"M %.4f %.4f L %.4f %.4f M %.4f %.4f L %.4f %.4f\" fill=\"none\" stroke=\"#d32f2f\" stroke-width=\"1.8\"/>", x0, y0, x1, y1, x0, y1, x1, y0))
            localParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"8\" fill=\"#d32f2f\">%@ fail: %@</text>", fillet.corner.x + 6.0, fillet.corner.y - 6.0, label, failure))
        }
        svgParts.append("""
    <g id="\(groupId)">
      \(localParts.joined(separator: "\n      "))
    </g>
""")
    }
    let svg = """
  <g id="debug-cap-fillet">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func debugOverlayForCapBoundary(_ boundaries: [CapBoundaryDebug]) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
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
        for point in points { bounds.expand(by: point) }
    }
    func addPoint(_ p: Vec2, radius: Double, fill: String) {
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.1f\" fill=\"%@\" stroke=\"none\"/>", p.x, p.y, radius, fill))
        bounds.expand(by: p)
    }
    for boundary in boundaries {
        addPolyline(boundary.simplified, stroke: "#455a64", width: 1.0)
        for (index, corner) in boundary.corners.enumerated() {
            if boundary.chosenIndices.contains(corner.index) {
                addPoint(corner.point, radius: 3.0, fill: "#d32f2f")
                let label = String(format: "%@ i=%d θ=%.1f", boundary.endpoint, corner.index, corner.theta * 180.0 / Double.pi)
                svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"8\" fill=\"#d32f2f\">%@</text>", corner.point.x + 4.0, corner.point.y - 4.0, label))
            } else if index == corner.index {
                addPoint(corner.point, radius: 2.0, fill: "#78909c")
            }
        }
        for point in boundary.trimPoints {
            addPoint(point, radius: 2.4, fill: "#1e88e5")
        }
        for point in boundary.arcPoints {
            addPoint(point, radius: 1.5, fill: "#43a047")
        }
    }
    let svg = """
  <g id="debug-cap-boundary">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func overlayForRailsAndHeartline(pathParam: SkeletonPathParameterization, plan: SweepPlan, sampleCount: Int, label: String) -> DebugOverlay {
    let count = max(2, sampleCount)
    let styleAtGT: (Double) -> SweepStyle = { t in
        SweepStyle(
            width: plan.scaledWidthAtT(t),
            widthLeft: plan.scaledWidthLeftAtT(t),
            widthRight: plan.scaledWidthRightAtT(t),
            height: plan.sweepHeight,
            angle: plan.thetaAtT(t),
            offset: plan.offsetAtT(t),
            angleIsRelative: plan.angleMode == .relative
        )
    }
    var centerPts: [Vec2] = []
    var leftPts: [Vec2] = []
    var rightPts: [Vec2] = []
    centerPts.reserveCapacity(count)
    leftPts.reserveCapacity(count)
    rightPts.reserveCapacity(count)
    var bounds = AABB.empty
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        let frame = railSampleFrameAtGlobalT(
            param: pathParam,
            warpGT: plan.warpT,
            styleAtGT: styleAtGT,
            gt: t,
            index: i
        )
        centerPts.append(frame.center)
        leftPts.append(frame.left)
        rightPts.append(frame.right)
        bounds.expand(by: frame.center)
        bounds.expand(by: frame.left)
        bounds.expand(by: frame.right)
    }
    func pathData(_ points: [Vec2]) -> String {
        guard let first = points.first else { return "" }
        var parts: [String] = []
        parts.append(String(format: "M %.4f %.4f", first.x, first.y))
        for p in points.dropFirst() {
            parts.append(String(format: "L %.4f %.4f", p.x, p.y))
        }
        return parts.joined(separator: " ")
    }
    let centerPath = pathData(centerPts)
    let leftPath = pathData(leftPts)
    let rightPath = pathData(rightPts)
    let labelText = label == "butt" ? "BUTT" : (label == "fillet" ? "FILLET" : label.uppercased())
    let labelPos = centerPts.first ?? Vec2(0, 0)
    let svg = """
  <g id="cap-fillet-line-aids-\(label)">
    <path d="\(centerPath)" fill="none" stroke="#111111" stroke-width="0.8" />
    <path d="\(leftPath)" fill="none" stroke="#d32f2f" stroke-width="0.6" />
    <path d="\(rightPath)" fill="none" stroke="#1976d2" stroke-width="0.6" />
    <text x="\(String(format: "%.4f", labelPos.x - 40.0))" y="\(String(format: "%.4f", labelPos.y - 10.0))" font-size="10" fill="#000000">\(labelText)</text>
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func overlayForCapFilletArcPoints(fillets: [CapFilletDebug], label: String) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
    let groupId = "cap-fillet-line-arc-points-\(label)"

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

    func addPoints(_ points: [Vec2], fill: String) {
        for point in points {
            svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"1.6\" fill=\"%@\" stroke=\"none\"/>", point.x, point.y, fill))
            bounds.expand(by: point)
        }
    }

    for fillet in fillets where fillet.success {
        guard let bridge = fillet.bridge else { continue }
        let strokeColor = fillet.side == "left" ? "#1b5e20" : "#0d47a1"
        let dotColor = fillet.side == "left" ? "#43a047" : "#42a5f5"
        let steps = max(8, fillet.arcSegments)
        let count = max(2, steps + 1)
        var points: [Vec2] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            points.append(bridge.evaluate(t))
        }
        addPolyline(points, stroke: strokeColor, width: 1.6)
        addPoints(points, fill: dotColor)
    }

    let svg = """
  <g id="\(groupId)">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func debugOverlayForCounters(_ counters: CounterSet, steps: Int, warn: (String) -> Void) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
    let stroke = "#d81b60"
    let strokeWidth = "1.5"
    let dash = "4,4"

    func addPolyline(_ points: [Vec2]) {
        guard let first = points.first else { return }
        var parts: [String] = []
        parts.append(String(format: "M %.4f %.4f", first.x, first.y))
        for point in points.dropFirst() {
            parts.append(String(format: "L %.4f %.4f", point.x, point.y))
        }
        let pathData = parts.joined(separator: " ")
        svgParts.append("<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(strokeWidth)\" stroke-dasharray=\"\(dash)\" />")
        for point in points {
            bounds.expand(by: point)
        }
    }

    for key in counters.entries.keys.sorted() {
        guard let primitive = counters.entries[key] else { continue }
        switch primitive {
        case .ink(let inkPrimitive, _):
            let lines = polylines(for: inkPrimitive, steps: steps, warn: warn)
            for line in lines {
                addPolyline(line)
            }
        case .ellipse:
            warn("counter ellipse is not supported for overlay")
        }
    }

    let svg = """
  <g id="debug-counters">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

private func polylines(for primitive: InkPrimitive, steps: Int, warn: (String) -> Void) -> [[Vec2]] {
    switch primitive {
    case .line(let line):
        return [[vec(line.p0), vec(line.p1)]]
    case .cubic(let cubic):
        return [sampleInkCubicPoints(cubic, steps: steps)]
    case .path(let path):
        var result: [[Vec2]] = []
        for segment in path.segments {
            switch segment {
            case .line(let line):
                result.append([vec(line.p0), vec(line.p1)])
            case .cubic(let cubic):
                result.append(sampleInkCubicPoints(cubic, steps: steps))
            }
        }
        return result
    case .heartline:
        warn("counter heartline is not supported for overlay")
        return []
    }
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

func makeParamsPlotOverlay(
    params: StrokeParams,
    plan: SweepPlan,
    glyphBounds: AABB?
) -> DebugOverlay {
    guard let bounds = glyphBounds else {
        return DebugOverlay(svg: "<g id=\"debug-params-plot\"></g>", bounds: AABB.empty)
    }

    let plotWidth = 200.0
    let plotHeight = 120.0
    let origin = Vec2(bounds.min.x + 20.0, bounds.min.y + 20.0)
    let samples = 200

    func sampleTrack(_ track: ParamTrack?) -> [Double] {
        guard let track else { return [] }
        return (0..<samples).map { i in
            let t = Double(i) / Double(max(1, samples - 1))
            return track.value(at: t)
        }
    }

    let widthLeftTrack = params.widthLeft.map { ParamTrack.fromKeyframedScalar($0, mode: .hermiteMonotone) }
    let widthRightTrack = params.widthRight.map { ParamTrack.fromKeyframedScalar($0, mode: .hermiteMonotone) }
    let widthTrack = params.width.map { ParamTrack.fromKeyframedScalar($0, mode: .hermiteMonotone) }

    var values: [Double] = []
    values.append(contentsOf: sampleTrack(widthLeftTrack))
    values.append(contentsOf: sampleTrack(widthRightTrack))
    if values.isEmpty {
        values.append(contentsOf: sampleTrack(widthTrack))
    }
    guard let minV = values.min(), let maxV = values.max() else {
        return DebugOverlay(svg: "<g id=\"debug-params-plot\"></g>", bounds: AABB.empty)
    }
    let range = max(1.0e-9, maxV - minV)

    func mapPoint(t: Double, value: Double) -> Vec2 {
        let x = origin.x + t * plotWidth
        let y = origin.y + (1.0 - (value - minV) / range) * plotHeight
        return Vec2(x, y)
    }

    func pathForTrack(_ track: ParamTrack, stroke: String) -> String {
        var parts: [String] = []
        for i in 0..<samples {
            let t = Double(i) / Double(max(1, samples - 1))
            let v = track.value(at: t)
            let p = mapPoint(t: t, value: v)
            let cmd = i == 0 ? "M" : "L"
            parts.append(String(format: "\(cmd) %.4f %.4f", p.x, p.y))
        }
        let d = parts.joined(separator: " ")
        return "<path d=\"\(d)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"1\" vector-effect=\"non-scaling-stroke\"/>"
    }

    func knotLabel(_ knot: KnotType) -> String {
        switch knot {
        case .smooth: return "S"
        case .cusp: return "C"
        case .hold: return "H"
        case .snap: return "N"
        }
    }

    func markersForTrack(_ track: ParamTrack, stroke: String) -> [String] {
        var parts: [String] = []
        for kf in track.keyframes {
            let p = mapPoint(t: kf.t, value: track.value(at: kf.t))
            parts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"2.5\" fill=\"none\" stroke=\"%@\" stroke-width=\"1\" vector-effect=\"non-scaling-stroke\"/>", p.x, p.y, stroke))
            parts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"9\" fill=\"%@\">%@</text>", p.x + 3.0, p.y - 3.0, stroke, knotLabel(kf.knot)))
        }
        return parts
    }

    var parts: [String] = []
    if let widthLeftTrack {
        parts.append(pathForTrack(widthLeftTrack, stroke: "#d32f2f"))
        parts.append(contentsOf: markersForTrack(widthLeftTrack, stroke: "#d32f2f"))
    }
    if let widthRightTrack {
        parts.append(pathForTrack(widthRightTrack, stroke: "#1976d2"))
        parts.append(contentsOf: markersForTrack(widthRightTrack, stroke: "#1976d2"))
    }
    if parts.isEmpty, let widthTrack {
        parts.append(pathForTrack(widthTrack, stroke: "#555555"))
        parts.append(contentsOf: markersForTrack(widthTrack, stroke: "#555555"))
    }

    let plotBounds = AABB(
        min: origin,
        max: Vec2(origin.x + plotWidth, origin.y + plotHeight)
    )

    let svg = """
  <g id="debug-params-plot">
    \(parts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: plotBounds)
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
