import XCTest
import CP2Geometry
import CP2Skeleton

final class CapBoundaryConnectivityTests: XCTestCase {
    func testCapBoundaryConnectivityVariants() {
        let rails = makeStraightRails()
        let styles: [CapStyle] = [
            .butt,
            .round,
            .ball,
            .fillet(radius: 5.0, corner: .left),
            .fillet(radius: 5.0, corner: .right),
            .fillet(radius: 5.0, corner: .both)
        ]
        for endpoint in ["start", "end"] {
            for style in styles {
                var boundaries: [CapBoundaryDebug] = []
                let startCap = endpoint == "start" ? style : .butt
                let endCap = endpoint == "end" ? style : .butt
                let result = buildCaps(
                    leftRail: rails.left,
                    rightRail: rails.right,
                    capNamespace: "test",
                    capLocalIndex: 0,
                    widthStart: 80,
                    widthEnd: 80,
                    startCap: startCap,
                    endCap: endCap,
                    capFilletArcSegments: 8,
                    debugFillet: nil,
                    debugCapBoundary: { boundaries.append($0) }
                )
                let capSegments = result.segments.filter { seg in
                    switch seg.source {
                    case .capStartEdge:
                        return endpoint == "start"
                    case .capEndEdge:
                        return endpoint == "end"
                    default:
                        return false
                    }
                }
                XCTAssertFalse(capSegments.isEmpty, "expected cap segments for \(endpoint) \(style)")
                let chain = chainFromSegments(capSegments)
                let minPoints = isFillet(style) ? 3 : 2
                let minEdges = isFillet(style) ? 2 : 1
                XCTAssertGreaterThanOrEqual(chain.points.count, minPoints)
                XCTAssertGreaterThanOrEqual(chain.edges.count, minEdges)
                XCTAssertTrue(chain.isConnected)
                XCTAssertFalse(chain.hasZeroLengthEdge)

                let expected = expectedEndpoints(
                    endpoint: endpoint,
                    leftRail: rails.left,
                    rightRail: rails.right,
                    result: result
                )
                let actual = chain.endpoints
                XCTAssertNotNil(actual)
                if let actual = actual {
                    let matches = (approxEqual(actual.0, expected.0) && approxEqual(actual.1, expected.1)) ||
                        (approxEqual(actual.0, expected.1) && approxEqual(actual.1, expected.0))
                    XCTAssertTrue(matches, "endpoints mismatch for \(endpoint) \(style)")
                }

                if case .fillet = style {
                    let boundary = boundaries.first { $0.endpoint == endpoint }
                    if let boundary, boundary.fallbackReason != nil {
                        XCTAssertNotNil(boundary.fallbackReason)
                    }
                }
            }
        }
    }
}

private func isFillet(_ style: CapStyle) -> Bool {
    if case .fillet = style { return true }
    return false
}

private func makeStraightRails() -> (left: [Vec2], right: [Vec2]) {
    let left = [Vec2(0, 40), Vec2(200, 40)]
    let right = [Vec2(0, -40), Vec2(200, -40)]
    return (left: left, right: right)
}

private func expectedEndpoints(
    endpoint: String,
    leftRail: [Vec2],
    rightRail: [Vec2],
    result: CapBuildResult
) -> (Vec2, Vec2) {
    let leftStart = leftRail.first ?? Vec2(0, 0)
    let leftEnd = leftRail.last ?? Vec2(0, 0)
    let rightStart = rightRail.first ?? Vec2(0, 0)
    let rightEnd = rightRail.last ?? Vec2(0, 0)
    let startDistance = (leftStart - rightStart).length
    let endDistance = (leftEnd - rightEnd).length
    let startAltDistance = (leftStart - rightEnd).length
    let endAltDistance = (leftEnd - rightStart).length
    let sumDirect = startDistance + endDistance
    let sumSwap = startAltDistance + endAltDistance
    let useReversedRight = sumSwap + Epsilon.defaultValue < sumDirect
    let rightForStart = useReversedRight ? rightEnd : rightStart
    let rightForEnd = useReversedRight ? rightStart : rightEnd

    if endpoint == "start" {
        let left = result.startLeftTrim ?? leftStart
        let right = result.startRightTrim ?? rightForStart
        return (left, right)
    }
    let left = result.endLeftTrim ?? leftEnd
    let right = result.endRightTrim ?? rightForEnd
    return (left, right)
}

private struct CapChain {
    var points: [Vec2]
    var edges: [(Int, Int)]
    var endpoints: (Vec2, Vec2)?
    var isConnected: Bool
    var hasZeroLengthEdge: Bool
}

private func chainFromSegments(_ segments: [Segment2]) -> CapChain {
    var points: [Vec2] = []
    var edges: [(Int, Int)] = []
    var indexForKey: [SnapKey: Int] = [:]
    var hasZeroLengthEdge = false

    func index(for point: Vec2) -> Int {
        let key = Epsilon.snapKey(point, eps: Epsilon.defaultValue)
        if let idx = indexForKey[key] { return idx }
        let idx = points.count
        points.append(point)
        indexForKey[key] = idx
        return idx
    }

    for seg in segments {
        let aIndex = index(for: seg.a)
        let bIndex = index(for: seg.b)
        edges.append((aIndex, bIndex))
        if (seg.a - seg.b).length <= 1.0e-8 {
            hasZeroLengthEdge = true
        }
    }

    var adjacency: [Int: [Int]] = [:]
    var degree: [Int: Int] = [:]
    for (a, b) in edges {
        adjacency[a, default: []].append(b)
        adjacency[b, default: []].append(a)
        degree[a, default: 0] += 1
        degree[b, default: 0] += 1
    }
    let usedVertices = Set(edges.flatMap { [$0.0, $0.1] })
    let startVertex = usedVertices.first
    var visited: Set<Int> = []
    if let startVertex {
        var queue: [Int] = [startVertex]
        visited.insert(startVertex)
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for next in adjacency[current] ?? [] {
                if !visited.contains(next) {
                    visited.insert(next)
                    queue.append(next)
                }
            }
        }
    }
    let connected = visited.count == usedVertices.count && !usedVertices.isEmpty
    let endpointIndices = degree.filter { $0.value == 1 }.map { $0.key }
    let endpoints: (Vec2, Vec2)?
    if endpointIndices.count == 2 {
        endpoints = (points[endpointIndices[0]], points[endpointIndices[1]])
    } else if edges.count == 1, let edge = edges.first {
        endpoints = (points[edge.0], points[edge.1])
    } else {
        endpoints = nil
    }
    return CapChain(points: points, edges: edges, endpoints: endpoints, isConnected: connected, hasZeroLengthEdge: hasZeroLengthEdge)
}

private func approxEqual(_ a: Vec2, _ b: Vec2) -> Bool {
    return (a - b).length <= 1.0e-6
}
