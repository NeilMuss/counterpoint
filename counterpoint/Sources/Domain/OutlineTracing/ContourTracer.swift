import Foundation

public enum ContourTracer {
    public static func trace(grid: RasterGrid, origin: Point, pixelSize: Double) -> [Ring] {
        let edges = boundaryEdges(grid: grid)
        let loops = buildLoops(from: edges)
        var rings: [Ring] = []
        rings.reserveCapacity(loops.count)
        for loop in loops {
            var ring: Ring = []
            ring.reserveCapacity(loop.count)
            for point in loop {
                ring.append(Point(x: origin.x + Double(point.x) * pixelSize,
                                  y: origin.y + Double(point.y) * pixelSize))
            }
            if let normalized = normalizeRing(ring, tol: pixelSize * 0.1) {
                rings.append(normalized)
            }
        }
        return rings
    }

    public static func assemblePolygons(from rings: [Ring]) -> PolygonSet {
        guard !rings.isEmpty else { return [] }
        var entries: [(ring: Ring, area: Double)] = rings.map { ($0, signedArea($0)) }
        entries = entries.filter { abs($0.area) > 0.0 }

        var depth: [Int] = Array(repeating: 0, count: entries.count)
        for i in 0..<entries.count {
            let point = entries[i].ring[0]
            for j in 0..<entries.count where i != j {
                if pointInRing(point, entries[j].ring) {
                    depth[i] += 1
                }
            }
        }

        var outers: [(ring: Ring, area: Double, index: Int)] = []
        var holes: [(ring: Ring, area: Double, index: Int)] = []
        for i in 0..<entries.count {
            if depth[i] % 2 == 0 {
                outers.append((ring: enforceWinding(entries[i].ring, area: entries[i].area, wantCCW: true), area: abs(entries[i].area), index: i))
            } else {
                holes.append((ring: enforceWinding(entries[i].ring, area: entries[i].area, wantCCW: false), area: abs(entries[i].area), index: i))
            }
        }

        var polygons: [Polygon] = outers.map { Polygon(outer: $0.ring, holes: []) }
        for hole in holes {
            let point = hole.ring[0]
            var candidates: [(idx: Int, area: Double)] = []
            for (outerIndex, outer) in outers.enumerated() {
                if pointInRing(point, outer.ring) {
                    candidates.append((outerIndex, outer.area))
                }
            }
            if let target = candidates.min(by: { $0.area < $1.area }) {
                polygons[target.idx].holes.append(hole.ring)
            } else {
                polygons.append(Polygon(outer: hole.ring, holes: []))
            }
        }
        return polygons
    }
}

private struct GridPoint: Hashable, Comparable {
    let x: Int
    let y: Int

    static func < (lhs: GridPoint, rhs: GridPoint) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        return lhs.y < rhs.y
    }
}

private struct Edge: Hashable {
    let start: GridPoint
    let end: GridPoint
}

private func boundaryEdges(grid: RasterGrid) -> [Edge] {
    var edges: [Edge] = []
    edges.reserveCapacity(grid.width * grid.height)
    for y in 0..<grid.height {
        for x in 0..<grid.width {
            guard grid[x, y] != 0 else { continue }
            let upEmpty = (y + 1 >= grid.height) || grid[x, y + 1] == 0
            let rightEmpty = (x + 1 >= grid.width) || grid[x + 1, y] == 0
            let downEmpty = (y - 1 < 0) || grid[x, y - 1] == 0
            let leftEmpty = (x - 1 < 0) || grid[x - 1, y] == 0

            if upEmpty {
                edges.append(Edge(start: GridPoint(x: x, y: y + 1), end: GridPoint(x: x + 1, y: y + 1)))
            }
            if rightEmpty {
                edges.append(Edge(start: GridPoint(x: x + 1, y: y + 1), end: GridPoint(x: x + 1, y: y)))
            }
            if downEmpty {
                edges.append(Edge(start: GridPoint(x: x + 1, y: y), end: GridPoint(x: x, y: y)))
            }
            if leftEmpty {
                edges.append(Edge(start: GridPoint(x: x, y: y), end: GridPoint(x: x, y: y + 1)))
            }
        }
    }
    return edges
}

private func buildLoops(from edges: [Edge]) -> [[GridPoint]] {
    guard !edges.isEmpty else { return [] }
    var adjacency: [GridPoint: [GridPoint]] = [:]
    adjacency.reserveCapacity(edges.count)
    for edge in edges {
        adjacency[edge.start, default: []].append(edge.end)
    }
    for key in adjacency.keys {
        adjacency[key]?.sort()
    }
    let sortedKeys = adjacency.keys.sorted()
    var loops: [[GridPoint]] = []

    func popEdge() -> Edge? {
        for key in sortedKeys {
            guard var list = adjacency[key], !list.isEmpty else { continue }
            let end = list.removeFirst()
            adjacency[key] = list
            return Edge(start: key, end: end)
        }
        return nil
    }

    while let edge = popEdge() {
        var loop: [GridPoint] = [edge.start, edge.end]
        var current = edge.end
        while current != edge.start {
            guard var list = adjacency[current], !list.isEmpty else { break }
            let next = list.removeFirst()
            adjacency[current] = list
            loop.append(next)
            current = next
        }
        if loop.count >= 3 {
            loops.append(loop)
        }
    }

    return loops
}

private func pointInRing(_ point: Point, _ ring: Ring) -> Bool {
    guard ring.count >= 3 else { return false }
    var inside = false
    let count = ring.count
    var j = count - 1
    for i in 0..<count {
        let pi = ring[i]
        let pj = ring[j]
        let intersect = ((pi.y > point.y) != (pj.y > point.y))
            && (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y + 0.0) + pi.x)
        if intersect {
            inside.toggle()
        }
        j = i
    }
    return inside
}

private func enforceWinding(_ ring: Ring, area: Double, wantCCW: Bool) -> Ring {
    if wantCCW {
        return area >= 0 ? ring : Array(ring.reversed())
    } else {
        return area <= 0 ? ring : Array(ring.reversed())
    }
}
