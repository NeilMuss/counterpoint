import Foundation
import CP2Geometry
import CP2Skeleton

func debugOverlayForPenStamps(
    stamps: [PenStampSample],
    showVertices: Bool,
    showConnectors: Bool
) -> DebugOverlay {
    guard !stamps.isEmpty else {
        return DebugOverlay(svg: "<g id=\"debug-pen-stamps\"></g>", bounds: AABB.empty)
    }
    let stroke = "#ff6f00"
    let connectorStroke = "#00897b"
    let vertexFill = "#ff6f00"
    let labelFill = "#37474f"

    var parts: [String] = []
    var bounds = AABB.empty

    for (index, stamp) in stamps.enumerated() {
        let corners = stamp.corners
        guard corners.count == 4 else { continue }
        var pointsText: [String] = []
        pointsText.reserveCapacity(5)
        for corner in corners {
            bounds.expand(by: corner)
            pointsText.append(String(format: "%.4f %.4f", corner.x, corner.y))
        }
        let first = corners[0]
        pointsText.append(String(format: "%.4f %.4f", first.x, first.y))
        let polyline = "<polyline class=\"pen-stamp\" data-stamp=\"\(index)\" points=\"\(pointsText.joined(separator: " "))\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"0.8\" />"
        parts.append(polyline)

        if showVertices {
            for (cornerIndex, corner) in corners.enumerated() {
                parts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"1.2\" fill=\"%@\" stroke=\"none\" />", corner.x, corner.y, vertexFill))
                parts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"6\" fill=\"%@\">%d</text>", corner.x + 2.2, corner.y - 2.2, labelFill, cornerIndex))
            }
        }
    }

    if showConnectors, stamps.count >= 2 {
        for i in 0..<(stamps.count - 1) {
            let a = stamps[i]
            let b = stamps[i + 1]
            guard a.corners.count == 4, b.corners.count == 4 else { continue }
            for k in 0..<4 {
                let p0 = a.corners[k]
                let p1 = b.corners[k]
                parts.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"%@\" stroke-width=\"0.5\" />", p0.x, p0.y, p1.x, p1.y, connectorStroke))
            }
        }
    }

    let svg = """
  <g id="debug-pen-stamps">
    \(parts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}
