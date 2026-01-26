import Foundation
import CP2Geometry
import CP2Skeleton

func makeCenterlineDebugOverlay(
    options: CLIOptions,
    path: SkeletonPath,
    pathParam: SkeletonPathParameterization,
    plan: SweepPlan
) -> DebugOverlay {
    let count = max(2, plan.sweepSampleCount)
    var left: [Vec2] = []
    var right: [Vec2] = []
    left.reserveCapacity(count)
    right.reserveCapacity(count)
    var tableP: [Vec2] = []
    tableP.reserveCapacity(count)
    
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        let point = pathParam.position(globalT: t)
        let tangent = pathParam.tangent(globalT: t).normalized()
        let normal = Vec2(-tangent.y, tangent.x)
        tableP.append(point)
        let halfW = plan.scaledWidthAtT(t) * 0.5
        let halfH = plan.sweepHeight * 0.5
        let angle = plan.thetaAtT(t)
        let corners: [Vec2] = [
            Vec2(-halfW, -halfH),
            Vec2(halfW, -halfH),
            Vec2(halfW, halfH),
            Vec2(-halfW, halfH)
        ]
        let cosA = cos(angle)
        let sinA = sin(angle)
        var minDot = Double.greatestFiniteMagnitude
        var maxDot = -Double.greatestFiniteMagnitude
        var leftPoint = point
        var rightPoint = point
        for corner in corners {
            let rotated = Vec2(
                corner.x * cosA - corner.y * sinA,
                corner.x * sinA + corner.y * cosA
            )
            let world = tangent * rotated.y + normal * rotated.x
            let cornerWorld = point + world
            let d = cornerWorld.dot(normal)
            if d < minDot {
                minDot = d
                leftPoint = cornerWorld
            }
            if d > maxDot {
                maxDot = d
                rightPoint = cornerWorld
            }
        }
        left.append(leftPoint)
        right.append(rightPoint)
    }

    let skeletonPath = tableP.enumerated().map { index, p in
        let cmd = index == 0 ? "M" : "L"
        return String(format: "\(cmd) %.4f %.4f", p.x, p.y)
    }.joined(separator: " ")
    let leftPath = left.enumerated().map { index, p in
        let cmd = index == 0 ? "M" : "L"
        return String(format: "\(cmd) %.4f %.4f", p.x, p.y)
    }.joined(separator: " ")
    let rightPath = right.enumerated().map { index, p in
        let cmd = index == 0 ? "M" : "L"
        return String(format: "\(cmd) %.4f %.4f", p.x, p.y)
    }.joined(separator: " ")
    
    var sampleDots: [String] = []
    sampleDots.reserveCapacity(count)
    for p in tableP {
        sampleDots.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"1.2\" fill=\"none\" stroke=\"blue\" stroke-width=\"0.5\"/>", p.x, p.y))
    }
    
    var normalLines: [String] = []
    normalLines.reserveCapacity(count)
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        let point = pathParam.position(globalT: t)
        let tangent = pathParam.tangent(globalT: t).normalized()
        let normal = Vec2(-tangent.y, tangent.x)
        let end = point + normal * (plan.sweepWidth * 0.5)
        normalLines.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"purple\" stroke-width=\"0.5\"/>", point.x, point.y, end.x, end.y))
    }
    
    var debugBounds = AABB.empty
    var debugLines: [String] = []
    if options.debugCenterline {
        var controlDots: [String] = []
        controlDots.reserveCapacity(path.segments.count * 2)
        for segment in path.segments {
            let controls = [segment.p1, segment.p2]
            for control in controls {
                let nearest = tableP[nearestIndex(points: tableP, to: control)]
                debugLines.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"#cccccc\" stroke-width=\"0.5\"/>", control.x, control.y, nearest.x, nearest.y))
                controlDots.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"2.0\" fill=\"red\" stroke=\"none\"/>", control.x, control.y))
                debugBounds.expand(by: control)
            }
        }
        for point in tableP {
            debugBounds.expand(by: point)
        }
        let svg = """
  <g id="debug">
    <path d="\(skeletonPath)" fill="none" stroke="orange" stroke-width="0.8" />
    \(debugLines.joined(separator: "\n    "))
    \(controlDots.joined(separator: "\n    "))
  </g>
"""
        return DebugOverlay(svg: svg, bounds: debugBounds)
    } else {
        for point in tableP + left + right {
            debugBounds.expand(by: point)
        }
        let svg = """
  <g id="debug">
    <path d="\(skeletonPath)" fill="none" stroke="orange" stroke-width="0.6" />
    <path d="\(leftPath)" fill="none" stroke="green" stroke-width="0.6" />
    <path d="\(rightPath)" fill="none" stroke="green" stroke-width="0.6" />
    \(normalLines.joined(separator: "\n    "))
    \(sampleDots.joined(separator: "\n    "))
  </g>
"""
        return DebugOverlay(svg: svg, bounds: debugBounds)
    }
}

func makeSamplingWhyOverlay(
    dots: [SamplingWhyDot],
    labelCount: Int = 5,
    minRadius: Double = 1.5,
    maxRadius: Double = 7.5,
    useLogRadius: Bool = false,
    fillOpacity: Double? = nil,
    renderAsRings: Bool = false,
    ringStrokeWidth: Double = 1.0,
    ringOpacity: Double? = nil,
    addLabelCenters: Bool = false
) -> DebugOverlay {
    guard !dots.isEmpty else {
        return DebugOverlay(svg: "<g id=\"debug-sampling-why\"></g>", bounds: AABB.empty)
    }

    var bounds = AABB.empty
    var dotParts: [String] = []
    dotParts.reserveCapacity(dots.count)

    func color(for reason: SamplingWhyReason) -> String {
        switch reason {
        case .flatness: return "#ff3333"
        case .railDeviation: return "#3377ff"
        case .both: return "#9932cc"
        case .forcedStop: return "#888888"
        }
    }

    for dot in dots {
        let radius: Double
        if useLogRadius {
            let mapped = minRadius + 3.0 * log10(1.0 + max(0.0, dot.severity))
            radius = max(minRadius, min(maxRadius, mapped))
        } else {
            radius = minRadius + min(6.0, dot.severity * 1.5)
        }
        let fill = color(for: dot.reason)
        if renderAsRings {
            let opacityAttr: String
            if let ringOpacity {
                opacityAttr = String(format: " stroke-opacity=\"%.3f\"", ringOpacity)
            } else {
                opacityAttr = ""
            }
            dotParts.append(String(
                format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.2f\" fill=\"none\" stroke=\"%@\" stroke-width=\"%.2f\"%@/>",
                dot.position.x, dot.position.y, radius, fill, ringStrokeWidth, opacityAttr
            ))
        } else {
            let opacityAttr: String
            if let fillOpacity {
                opacityAttr = String(format: " fill-opacity=\"%.3f\"", fillOpacity)
            } else {
                opacityAttr = ""
            }
            dotParts.append(String(
                format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.2f\" fill=\"%@\"%@ stroke=\"none\"/>",
                dot.position.x, dot.position.y, radius, fill, opacityAttr
            ))
        }
        bounds.expand(by: dot.position)
    }

    let worst = dots.sorted {
        if $0.severity == $1.severity {
            return $0.s < $1.s
        }
        return $0.severity > $1.severity
    }.prefix(labelCount)

    var labelParts: [String] = []
    labelParts.reserveCapacity(worst.count)
    var rank = 1
    for dot in worst {
        let reasonLabel: String = {
            switch dot.reason {
            case .flatness: return "F"
            case .railDeviation: return "R"
            case .both: return "B"
            case .forcedStop: return "S"
            }
        }()
        let text = String(format: "%d:%@ %.2f", rank, reasonLabel, dot.severity)
        labelParts.append(String(
            format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"8\" fill=\"#333333\">%@</text>",
            dot.position.x + 3.0, dot.position.y - 3.0, text
        ))
        rank += 1
    }

    if renderAsRings && addLabelCenters && !worst.isEmpty {
        for dot in worst {
            let fill = color(for: dot.reason)
            dotParts.append(String(
                format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.2f\" fill=\"%@\" stroke=\"none\"/>",
                dot.position.x, dot.position.y, 1.5, fill
            ))
        }
    }

    let svg = """
  <g id="debug-sampling-why">
    \(dotParts.joined(separator: "\n    "))
    \(labelParts.joined(separator: "\n    "))
  </g>
"""

    return DebugOverlay(svg: svg, bounds: bounds)
}
