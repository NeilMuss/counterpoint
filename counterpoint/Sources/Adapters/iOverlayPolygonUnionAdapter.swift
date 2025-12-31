import Foundation
import CoreGraphics
import iOverlay
import Domain

public final class IOverlayPolygonUnionAdapter: PolygonUnioning {
    public init() {}

    public func union(subjectRings: [Ring]) throws -> PolygonSet {
        guard !subjectRings.isEmpty else { return [] }
        var overlay = CGOverlay()
        for ring in subjectRings {
            let path = ring.map { CGPoint(x: $0.x, y: $0.y) }
            overlay.add(path: path, type: .subject)
        }

        let graph = overlay.buildGraph()
        let shapes = graph.extractShapes(overlayRule: .union)

        return shapes.map { shape in
            let paths = shape.map { closeRing(points: $0.map { Point(x: Double($0.x), y: Double($0.y)) }) }
            let outer = paths.first ?? []
            let holes = Array(paths.dropFirst())
            return Polygon(outer: outer, holes: holes)
        }
    }

    private func closeRing(points: [Point]) -> Ring {
        guard let first = points.first else { return points }
        if points.last != first {
            return points + [first]
        }
        return points
    }
}
