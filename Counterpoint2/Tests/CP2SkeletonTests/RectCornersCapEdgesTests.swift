import XCTest
import CP2Geometry
@testable import CP2Skeleton

final class RectCornersCapEdgesTests: XCTestCase {
    func testPerimeterEdgesConnectWithinEachSample() {
        let sampleCount = 3
        var c0: [Vec2] = []
        var c1: [Vec2] = []
        var c2: [Vec2] = []
        var c3: [Vec2] = []
        for k in 0..<sampleCount {
            let x = Double(k) * 20.0
            c0.append(Vec2(x + 5.0, 2.0))
            c1.append(Vec2(x + 5.0, -2.0))
            c2.append(Vec2(x - 5.0, -2.0))
            c3.append(Vec2(x - 5.0, 2.0))
        }
        let output = buildPenSoupSegmentsRectCorners(
            corner0: c0,
            corner1: c1,
            corner2: c2,
            corner3: c3,
            eps: 1.0e-6
        )
        XCTAssertGreaterThan(output.perimeterSegments, 0)
        let expectedPerimeter = sampleCount * 4
        XCTAssertEqual(output.perimeterSegments, expectedPerimeter)

        let samples = zip(zip(c0, c1), zip(c2, c3)).map { [$0.0.0, $0.0.1, $0.1.0, $0.1.1] }
        func edgeKey(_ a: Vec2, _ b: Vec2) -> String {
            let ka = Epsilon.snapKey(a, eps: 1.0e-6)
            let kb = Epsilon.snapKey(b, eps: 1.0e-6)
            if ka.x < kb.x || (ka.x == kb.x && ka.y < kb.y) {
                return "\(ka.x),\(ka.y)->\(kb.x),\(kb.y)"
            }
            return "\(kb.x),\(kb.y)->\(ka.x),\(ka.y)"
        }
        let edgePairs = [(0, 1), (1, 2), (2, 3), (3, 0)]
        var sampleEdges: [Set<String>] = []
        for corners in samples {
            var keys = Set<String>()
            for pair in edgePairs {
                keys.insert(edgeKey(corners[pair.0], corners[pair.1]))
            }
            sampleEdges.append(keys)
        }
        var perSampleCounts: [Int] = Array(repeating: 0, count: sampleCount)
        for segment in output.segments where segment.source == .penCap {
            let key = edgeKey(segment.a, segment.b)
            for (index, keys) in sampleEdges.enumerated() where keys.contains(key) {
                perSampleCounts[index] += 1
            }
        }
        XCTAssertEqual(perSampleCounts[0], 4)
        XCTAssertEqual(perSampleCounts[1], 4)
        XCTAssertEqual(perSampleCounts[2], 4)
    }
}
