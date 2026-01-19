import Foundation
import Domain

enum SilhouetteOutlineTracer {
    private struct IntPoint: Hashable {
        let x: Int
        let y: Int
    }

    private struct EdgeKey: Hashable {
        let a: IntPoint
        let b: IntPoint

        init(_ p0: IntPoint, _ p1: IntPoint) {
            if p0.x < p1.x || (p0.x == p1.x && p0.y <= p1.y) {
                a = p0
                b = p1
            } else {
                a = p1
                b = p0
            }
        }
    }

    static func trace(rings: [Ring], pixelSize: Double, padding: Double) -> [Ring] {
        guard !rings.isEmpty else { return [] }
        let bbox = bounds(of: rings)
        let originX = bbox.minX - padding
        let originY = bbox.minY - padding
        let width = max(1, Int(ceil((bbox.maxX + padding - originX) / pixelSize)))
        let height = max(1, Int(ceil((bbox.maxY + padding - originY) / pixelSize)))
        var grid = Array(repeating: Array(repeating: false, count: width), count: height)
        for j in 0..<height {
            let y = originY + (Double(j) + 0.5) * pixelSize
            for i in 0..<width {
                let x = originX + (Double(i) + 0.5) * pixelSize
                grid[j][i] = pointInRings(Point(x: x, y: y), rings: rings)
            }
        }
        let edges = perimeterEdges(grid: grid)
        let ringsInt = stitchEdges(edges)
        let ringsWorld = ringsInt.map { ring in
            ring.map { point in
                Point(
                    x: originX + Double(point.x) * pixelSize,
                    y: originY + Double(point.y) * pixelSize
                )
            }
        }
        return orderRings(ringsWorld)
    }

    private static func pointInRings(_ point: Point, rings: [Ring]) -> Bool {
        var inside = false
        for ring in rings {
            if pointInRing(point, ring: ring) {
                inside.toggle()
            }
        }
        return inside
    }

    private static func pointInRing(_ point: Point, ring: Ring) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let pi = ring[i]
            let pj = ring[j]
            let intersects = (pi.y > point.y) != (pj.y > point.y)
                && point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y + 1.0e-12) + pi.x
            if intersects {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private static func perimeterEdges(grid: [[Bool]]) -> [(IntPoint, IntPoint)] {
        let height = grid.count
        let width = grid.first?.count ?? 0
        var edges: [(IntPoint, IntPoint)] = []
        edges.reserveCapacity(width * height)
        for j in 0..<height {
            for i in 0..<width where grid[j][i] {
                let leftOutside = (i == 0) || !grid[j][i - 1]
                let rightOutside = (i == width - 1) || !grid[j][i + 1]
                let downOutside = (j == 0) || !grid[j - 1][i]
                let upOutside = (j == height - 1) || !grid[j + 1][i]
                if leftOutside {
                    edges.append((IntPoint(x: i, y: j), IntPoint(x: i, y: j + 1)))
                }
                if upOutside {
                    edges.append((IntPoint(x: i, y: j + 1), IntPoint(x: i + 1, y: j + 1)))
                }
                if rightOutside {
                    edges.append((IntPoint(x: i + 1, y: j + 1), IntPoint(x: i + 1, y: j)))
                }
                if downOutside {
                    edges.append((IntPoint(x: i + 1, y: j), IntPoint(x: i, y: j)))
                }
            }
        }
        return edges
    }

    private static func stitchEdges(_ edges: [(IntPoint, IntPoint)]) -> [[IntPoint]] {
        var adjacency: [IntPoint: [IntPoint]] = [:]
        var edgeSet: Set<EdgeKey> = []
        for (a, b) in edges {
            adjacency[a, default: []].append(b)
            adjacency[b, default: []].append(a)
            edgeSet.insert(EdgeKey(a, b))
        }
        for (key, value) in adjacency {
            adjacency[key] = value.sorted(by: lexOrder)
        }
        var rings: [[IntPoint]] = []
        while let startEdge = edgeSet.first {
            let start = startEdge.a
            let next = startEdge.b
            edgeSet.remove(startEdge)
            var ring: [IntPoint] = [start, next]
            var prev = start
            var curr = next
            while curr != start {
                guard let neighbors = adjacency[curr] else { break }
                var candidates = neighbors.filter { edgeSet.contains(EdgeKey(curr, $0)) }
                if candidates.count > 1 {
                    let nonPrev = candidates.filter { $0 != prev }
                    candidates = nonPrev.isEmpty ? candidates : nonPrev
                }
                guard let chosen = candidates.sorted(by: lexOrder).first else { break }
                edgeSet.remove(EdgeKey(curr, chosen))
                ring.append(chosen)
                prev = curr
                curr = chosen
            }
            if ring.first != ring.last {
                ring.append(ring.first!)
            }
            rings.append(ring)
        }
        return rings.map { removeConsecutiveDuplicates($0) }.filter { $0.count >= 4 }
    }

    private static func lexOrder(_ a: IntPoint, _ b: IntPoint) -> Bool {
        if a.x != b.x { return a.x < b.x }
        return a.y < b.y
    }

    private static func removeConsecutiveDuplicates(_ ring: [IntPoint]) -> [IntPoint] {
        guard !ring.isEmpty else { return [] }
        var result: [IntPoint] = [ring[0]]
        for point in ring.dropFirst() where point != result.last {
            result.append(point)
        }
        if result.count >= 2, result.first == result.last, result.count > 1 {
            return result
        }
        if result.first != result.last {
            result.append(result.first!)
        }
        return result
    }

    private static func orderRings(_ rings: [Ring]) -> [Ring] {
        return rings.sorted { lhs, rhs in
            let areaL = abs(signedArea(lhs))
            let areaR = abs(signedArea(rhs))
            if abs(areaL - areaR) > 1.0e-9 {
                return areaL > areaR
            }
            let minL = minPoint(lhs)
            let minR = minPoint(rhs)
            if minL.x != minR.x { return minL.x < minR.x }
            return minL.y < minR.y
        }
    }

    private static func signedArea(_ ring: Ring) -> Double {
        guard ring.count >= 3 else { return 0.0 }
        var area = 0.0
        for i in 0..<(ring.count - 1) {
            let a = ring[i]
            let b = ring[i + 1]
            area += (a.x * b.y - b.x * a.y)
        }
        return area * 0.5
    }

    private static func minPoint(_ ring: Ring) -> Point {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        for point in ring {
            if point.x < minX || (point.x == minX && point.y < minY) {
                minX = point.x
                minY = point.y
            }
        }
        return Point(x: minX, y: minY)
    }

    private static func bounds(of rings: [Ring]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for ring in rings {
            for point in ring {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
        }
        return (minX, minY, maxX, maxY)
    }
}
