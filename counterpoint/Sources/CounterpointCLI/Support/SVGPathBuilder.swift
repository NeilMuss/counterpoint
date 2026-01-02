import Foundation
import CoreGraphics
import Domain

struct SVGPathBuilder {
    let precision: Int

    init(precision: Int = 4) {
        self.precision = precision
    }

    func svgDocument(for polygons: PolygonSet, fittedPaths: [FittedPath]? = nil, size: CGSize?, padding: Double, debugOverlay: SVGDebugOverlay? = nil) -> String {
        let bounds = boundsFor(polygons: polygons, fittedPaths: fittedPaths, debugOverlay: debugOverlay)
        let padded = bounds.insetBy(dx: -padding, dy: -padding)
        let viewBox = padded
        let width = size?.width ?? viewBox.width
        let height = size?.height ?? viewBox.height
        let pathElements: String
        if let fittedPaths {
            pathElements = fittedPaths.map { pathData(for: $0) }.joined(separator: "\n")
        } else {
            pathElements = polygons.map { pathData(for: $0) }.joined(separator: "\n")
        }
        let debug = debugOverlay.map { debugGroup($0, polygons: polygons) } ?? ""

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

    func pathData(for fittedPath: FittedPath) -> String {
        let combined = fittedPath.subpaths.map { pathData(for: $0) }.joined(separator: " ")
        return "<path fill=\"black\" stroke=\"none\" fill-rule=\"nonzero\" d=\"\(combined)\"/>"
    }

    private func pathData(for subpath: FittedSubpath) -> String {
        guard let first = subpath.segments.first else { return "" }
        var parts: [String] = []
        parts.reserveCapacity(subpath.segments.count + 2)
        parts.append("M \(format(first.p0.x)) \(format(first.p0.y))")
        for segment in subpath.segments {
            parts.append("C \(format(segment.p1.x)) \(format(segment.p1.y)) \(format(segment.p2.x)) \(format(segment.p2.y)) \(format(segment.p3.x)) \(format(segment.p3.y))")
        }
        parts.append("Z")
        return parts.joined(separator: " ")
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

    private func boundsFor(polygons: PolygonSet, fittedPaths: [FittedPath]?, debugOverlay: SVGDebugOverlay?) -> CGRect {
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

        if let fittedPaths {
            for path in fittedPaths {
                for subpath in path.subpaths {
                    for segment in subpath.segments {
                        let points = [segment.p0, segment.p1, segment.p2, segment.p3]
                        for point in points {
                            minX = min(minX, point.x)
                            maxX = max(maxX, point.x)
                            minY = min(minY, point.y)
                            maxY = max(maxY, point.y)
                        }
                    }
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
            for point in overlay.samplePoints {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            for ray in overlay.tangentRays + overlay.angleRays {
                minX = min(minX, ray.0.x, ray.1.x)
                maxX = max(maxX, ray.0.x, ray.1.x)
                minY = min(minY, ray.0.y, ray.1.y)
                maxY = max(maxY, ray.0.y, ray.1.y)
            }
            for point in overlay.envelopeLeft + overlay.envelopeRight + overlay.envelopeOutline {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
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

    private func debugGroup(_ overlay: SVGDebugOverlay, polygons: PolygonSet) -> String {
        let skeletonPath = polylinePath(overlay.skeleton)
        let stampPaths = overlay.stamps.map { ringPath($0) }.filter { !$0.isEmpty }
        let bridgePaths = overlay.bridges.map { ringPath($0) }.filter { !$0.isEmpty }
        let tangentPath = rayPath(overlay.tangentRays)
        let anglePath = rayPath(overlay.angleRays)
        let leftRail = polylinePath(overlay.envelopeLeft)
        let rightRail = polylinePath(overlay.envelopeRight)
        let outlineRail = overlay.envelopeOutline.isEmpty ? "" : ringPath(overlay.envelopeOutline)
        let points = overlay.samplePoints.map { "<circle cx=\"\(format($0.x))\" cy=\"\(format($0.y))\" r=\"\(format(0.6))\" fill=\"#222222\" fill-opacity=\"0.5\"/>" }.joined(separator: "\n    ")

        let stampElements = stampPaths.map { "<path fill=\"none\" stroke=\"#0066ff\" stroke-opacity=\"0.3\" stroke-width=\"0.5\" d=\"\($0)\"/>" }.joined(separator: "\n    ")
        let bridgeElements = bridgePaths.map { "<path fill=\"none\" stroke=\"#00aa66\" stroke-opacity=\"0.25\" stroke-width=\"0.5\" d=\"\($0)\"/>" }.joined(separator: "\n    ")
        let unionSource = overlay.unionPolygons ?? polygons
        let unionOutline = overlay.showUnionOutline ? unionSource.map { outlinePath(for: $0) }.joined(separator: "\n    ") : ""
        let envelopeElements = [
            leftRail.isEmpty ? nil : "<path fill=\"none\" stroke=\"#8844ff\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(leftRail)\"/>",
            rightRail.isEmpty ? nil : "<path fill=\"none\" stroke=\"#8844ff\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(rightRail)\"/>",
            outlineRail.isEmpty ? nil : "<path fill=\"none\" stroke=\"#8844ff\" stroke-opacity=\"0.35\" stroke-width=\"0.6\" d=\"\(outlineRail)\"/>"
        ].compactMap { $0 }.joined(separator: "\n    ")

        return """
        <g id=\"debug\">
          <path fill=\"none\" stroke=\"#ff3366\" stroke-opacity=\"0.6\" stroke-width=\"0.5\" d=\"\(skeletonPath)\"/>
          <path fill=\"none\" stroke=\"#ff9900\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(tangentPath)\"/>
          <path fill=\"none\" stroke=\"#222222\" stroke-opacity=\"0.7\" stroke-width=\"0.6\" d=\"\(anglePath)\"/>
          \(points)
          \(envelopeElements)
          \(stampElements)
          \(bridgeElements)
          \(unionOutline)
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

    private func rayPath(_ rays: [(Point, Point)]) -> String {
        guard !rays.isEmpty else { return "" }
        var parts: [String] = []
        for ray in rays {
            parts.append("M \(format(ray.0.x)) \(format(ray.0.y)) L \(format(ray.1.x)) \(format(ray.1.y))")
        }
        return parts.joined(separator: " ")
    }

    private func outlinePath(for polygon: Polygon) -> String {
        let outer = ringPath(polygon.outer)
        let holes = polygon.holes.map { ringPath($0) }.joined(separator: " ")
        let combined = holes.isEmpty ? outer : "\(outer) \(holes)"
        return "<path fill=\"none\" stroke=\"#111111\" stroke-opacity=\"0.6\" stroke-width=\"0.7\" d=\"\(combined)\"/>"
    }
}

struct SVGDebugOverlay {
    var skeleton: [Point]
    var stamps: [Ring]
    var bridges: [Ring]
    var samplePoints: [Point]
    var tangentRays: [(Point, Point)]
    var angleRays: [(Point, Point)]
    var envelopeLeft: [Point]
    var envelopeRight: [Point]
    var envelopeOutline: Ring
    var showUnionOutline: Bool
    var unionPolygons: PolygonSet?
}
