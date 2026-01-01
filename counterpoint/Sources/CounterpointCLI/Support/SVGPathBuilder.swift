import Foundation
import CoreGraphics
import Domain

struct SVGPathBuilder {
    let precision: Int

    init(precision: Int = 4) {
        self.precision = precision
    }

    func svgDocument(for polygons: PolygonSet, size: CGSize?, padding: Double, debugOverlay: SVGDebugOverlay? = nil) -> String {
        let bounds = boundsFor(polygons: polygons, debugOverlay: debugOverlay)
        let padded = bounds.insetBy(dx: -padding, dy: -padding)
        let viewBox = padded
        let width = size?.width ?? viewBox.width
        let height = size?.height ?? viewBox.height
        let pathElements = polygons.map { pathData(for: $0) }.joined(separator: "\n")
        let debug = debugOverlay.map { debugGroup($0) } ?? ""

        return """
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(format(width))\" height=\"\(format(height))\" viewBox=\"\(format(viewBox.minX)) \(format(viewBox.minY)) \(format(viewBox.width)) \(format(viewBox.height))\">
          \(pathElements)
          \(debug)
        </svg>
        """
    }

    func pathData(for polygon: Polygon) -> String {
        let outer = ringPath(polygon.outer)
        let holes = polygon.holes.map { ringPath($0) }.joined(separator: " ")
        let combined = holes.isEmpty ? outer : "\(outer) \(holes)"
        return "<path fill=\"black\" stroke=\"none\" fill-rule=\"evenodd\" d=\"\(combined)\"/>"
    }

    private func ringPath(_ ring: Ring) -> String {
        let closed = closeRing(ring)
        guard let first = closed.first else { return "" }
        var parts: [String] = []
        parts.reserveCapacity(closed.count + 2)
        parts.append("M \(format(first.x)) \(format(first.y))")
        for point in closed.dropFirst() {
            parts.append("L \(format(point.x)) \(format(point.y))")
        }
        parts.append("Z")
        return parts.joined(separator: " ")
    }

    private func closeRing(_ ring: Ring) -> Ring {
        guard let first = ring.first else { return ring }
        if ring.last != first {
            return ring + [first]
        }
        return ring
    }

    private func boundsFor(polygons: PolygonSet, debugOverlay: SVGDebugOverlay?) -> CGRect {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for polygon in polygons {
            for point in polygon.outer {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            for hole in polygon.holes {
                for point in hole {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
        }

        if !minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        if let overlay = debugOverlay {
            for point in overlay.skeleton {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            for ring in overlay.stamps + overlay.bridges {
                for point in ring {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
        }

        let width = max(0.0, maxX - minX)
        let height = max(0.0, maxY - minY)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func format(_ value: Double) -> String {
        let factor = pow(10.0, Double(precision))
        let rounded = (value * factor).rounded() / factor
        if rounded == -0.0 { return "0" }
        return String(format: "%0.*f", precision, rounded)
    }

    private func debugGroup(_ overlay: SVGDebugOverlay) -> String {
        let skeletonPath = polylinePath(overlay.skeleton)
        let stampPaths = overlay.stamps.map { ringPath($0) }.filter { !$0.isEmpty }
        let bridgePaths = overlay.bridges.map { ringPath($0) }.filter { !$0.isEmpty }

        let stampElements = stampPaths.map { "<path fill=\"none\" stroke=\"#0066ff\" stroke-opacity=\"0.3\" stroke-width=\"0.5\" d=\"\($0)\"/>" }.joined(separator: "\n    ")
        let bridgeElements = bridgePaths.map { "<path fill=\"none\" stroke=\"#00aa66\" stroke-opacity=\"0.25\" stroke-width=\"0.5\" d=\"\($0)\"/>" }.joined(separator: "\n    ")

        return """
        <g id=\"debug\">
          <path fill=\"none\" stroke=\"#ff3366\" stroke-opacity=\"0.6\" stroke-width=\"0.5\" d=\"\(skeletonPath)\"/>
          \(stampElements)
          \(bridgeElements)
        </g>
        """
    }

    private func polylinePath(_ points: [Point]) -> String {
        guard let first = points.first else { return "" }
        var parts: [String] = ["M \(format(first.x)) \(format(first.y))"]
        for point in points.dropFirst() {
            parts.append("L \(format(point.x)) \(format(point.y))")
        }
        return parts.joined(separator: " ")
    }
}

struct SVGDebugOverlay {
    var skeleton: [Point]
    var stamps: [Ring]
    var bridges: [Ring]
}
