import XCTest
import CP2Geometry
import CP2Skeleton

final class BoundarySoupProvenanceTests: XCTestCase {
    func testSoupDegreeStatsHistogramAndSources() {
        let a = Vec2(0, 0)
        let b = Vec2(0, 10)
        let c = Vec2(0, 20)

        let segments = [
            Segment2(a, b, source: .railLeft),
            Segment2(b, c, source: .railRight)
        ]

        let stats = computeSoupDegreeStats(segments: segments, eps: 1.0e-6)

        XCTAssertEqual(stats.nodeCount, 3)
        XCTAssertEqual(stats.edgeCount, 2)
        XCTAssertEqual(stats.degreeHistogram[1], 2)
        XCTAssertEqual(stats.degreeHistogram[2], 1)

        let aKey = Epsilon.snapKey(a, eps: 1.0e-6)
        let cKey = Epsilon.snapKey(c, eps: 1.0e-6)

        let aAnomaly = stats.anomalies.first { $0.key == aKey }
        let cAnomaly = stats.anomalies.first { $0.key == cKey }

        XCTAssertNotNil(aAnomaly)
        XCTAssertNotNil(cAnomaly)
        XCTAssertEqual(aAnomaly?.outNeighbors.count, 1)
        XCTAssertEqual(cAnomaly?.outNeighbors.count, 1)
        XCTAssertEqual(aAnomaly?.outNeighbors.first?.source, .railLeft)
        XCTAssertEqual(cAnomaly?.outNeighbors.first?.source, .railRight)
    }

    func testSoupEdgeDedupUpgradesUnknownToKnown() {
        let a = Vec2(0, 0)
        let b = Vec2(0, 10)

        let segments = [
            Segment2(a, b, source: .unknown("first")),
            Segment2(a, b, source: .railLeft)
        ]

        let stats = computeSoupDegreeStats(segments: segments, eps: 1.0e-6)
        let aKey = Epsilon.snapKey(a, eps: 1.0e-6)
        let aAnomaly = stats.anomalies.first { $0.key == aKey }

        XCTAssertNotNil(aAnomaly)
        XCTAssertEqual(aAnomaly?.outNeighbors.count, 1)
        XCTAssertEqual(aAnomaly?.outNeighbors.first?.source, .railLeft)
        XCTAssertEqual(stats.edgeCount, 1)
    }

    func testCapEdgeSourceDescriptionIsStable() {
        let source = EdgeSource.capStartEdge(role: .joinLR, detail: "capIndex=0")
        XCTAssertEqual(source.description, "capStart.joinLR(capIndex=0)")
    }

    func testSpotlightCapSegmentsMatchesKeys() {
        let a = Vec2(0, 0)
        let b = Vec2(0, 10)
        let c = Vec2(10, 10)

        let segments = [
            Segment2(a, b, source: .capStartEdge(role: .joinLR, detail: "capIndex=0")),
            Segment2(b, c, source: .capStartEdge(role: .walkL, detail: "capIndex=1")),
            Segment2(a, c, source: .railLeft)
        ]

        let aKey = Epsilon.snapKey(a, eps: 1.0e-6)
        let bKey = Epsilon.snapKey(b, eps: 1.0e-6)

        let hits = spotlightCapSegments(
            segments: segments,
            keyQuant: { Epsilon.snapKey($0, eps: 1.0e-6) },
            matchA: aKey,
            matchB: bKey,
            sources: { source in
                if case .capStartEdge = source { return true }
                return false
            },
            topN: 5
        )

        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.seg.source, .capStartEdge(role: .joinLR, detail: "capIndex=0"))
    }

    func testSpotlightCapSegmentsTopNOrdering() {
        let a = Vec2(0, 0)
        let b = Vec2(0, 10)   // len 10
        let c = Vec2(0, 5)    // len 5
        let d = Vec2(0, 17)   // len 17
        let e = Vec2(0, 7)    // len 7

        let segments = [
            Segment2(a, b, source: .capStartEdge(role: .walkL, detail: "capIndex=0")),
            Segment2(a, c, source: .capStartEdge(role: .walkR, detail: "capIndex=1")),
            Segment2(a, d, source: .capStartEdge(role: .joinLR, detail: "capIndex=2")),
            Segment2(a, e, source: .capStartEdge(role: .walkL, detail: "capIndex=3"))
        ]

        let hits = spotlightCapSegments(
            segments: segments,
            keyQuant: { Epsilon.snapKey($0, eps: 1.0e-6) },
            matchA: nil,
            matchB: nil,
            sources: { source in
                if case .capStartEdge = source { return true }
                return false
            },
            topN: 2
        )

        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].len, (d - a).length)
        XCTAssertEqual(hits[1].len, (b - a).length)
    }

    func testCapStartJoinConnectsCorrespondingEndpoints() {
        let left = [Vec2(0, 1), Vec2(10, 1)]
        let right = [Vec2(0, -1), Vec2(10, -1)]

        let result = buildCaps(
            leftRail: left,
            rightRail: right,
            capNamespace: "capIndex",
            capLocalIndex: 0,
            widthStart: 2.0,
            widthEnd: 2.0,
            startCap: .butt,
            endCap: .butt,
            capFilletArcSegments: 8,
            debugFillet: nil,
            debugCapBoundary: nil
        )
        let join = result.segments.first {
            if case .capStartEdge(let role, _) = $0.source { return role == .joinLR }
            return false
        }

        XCTAssertNotNil(join)
        let endpoints = [join!.a, join!.b]
        XCTAssertTrue(endpoints.contains(where: { Epsilon.approxEqual($0, left[0]) }))
        XCTAssertTrue(endpoints.contains(where: { Epsilon.approxEqual($0, right[0]) }))
        XCTAssertEqual((join!.b - join!.a).length, (left[0] - right[0]).length, accuracy: 1.0e-6)
    }

    func testCapEndJoinConnectsCorrespondingEndpoints() {
        let left = [Vec2(0, 1), Vec2(10, 1)]
        let right = [Vec2(0, -1), Vec2(10, -1)]

        let result = buildCaps(
            leftRail: left,
            rightRail: right,
            capNamespace: "capIndex",
            capLocalIndex: 0,
            widthStart: 2.0,
            widthEnd: 2.0,
            startCap: .butt,
            endCap: .butt,
            capFilletArcSegments: 8,
            debugFillet: nil,
            debugCapBoundary: nil
        )
        let join = result.segments.first {
            if case .capEndEdge(let role, _) = $0.source { return role == .joinLR }
            return false
        }

        XCTAssertNotNil(join)
        let endpoints = [join!.a, join!.b]
        XCTAssertTrue(endpoints.contains(where: { Epsilon.approxEqual($0, left[1]) }))
        XCTAssertTrue(endpoints.contains(where: { Epsilon.approxEqual($0, right[1]) }))
        XCTAssertEqual((join!.b - join!.a).length, (left[1] - right[1]).length, accuracy: 1.0e-6)
    }

    func testCapJoinUnaffectedByRightRailOrder() {
        let left = [Vec2(0, 1), Vec2(10, 1)]
        let right = [Vec2(0, -1), Vec2(10, -1)]
        let rightReversed = right.reversed()

        let result = buildCaps(
            leftRail: left,
            rightRail: Array(rightReversed),
            capNamespace: "capIndex",
            capLocalIndex: 0,
            widthStart: 2.0,
            widthEnd: 2.0,
            startCap: .butt,
            endCap: .butt,
            capFilletArcSegments: 8,
            debugFillet: nil,
            debugCapBoundary: nil
        )
        let startJoin = result.segments.first {
            if case .capStartEdge(let role, _) = $0.source { return role == .joinLR }
            return false
        }
        let endJoin = result.segments.first {
            if case .capEndEdge(let role, _) = $0.source { return role == .joinLR }
            return false
        }

        XCTAssertNotNil(startJoin)
        XCTAssertNotNil(endJoin)
        XCTAssertEqual((startJoin!.b - startJoin!.a).length, (left[0] - right[0]).length, accuracy: 1.0e-6)
        XCTAssertEqual((endJoin!.b - endJoin!.a).length, (left[1] - right[1]).length, accuracy: 1.0e-6)
    }
}
