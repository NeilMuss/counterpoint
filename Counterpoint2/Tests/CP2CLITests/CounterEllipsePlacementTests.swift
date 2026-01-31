import XCTest
import CP2Geometry
@testable import cp2_cli

final class CounterEllipsePlacementTests: XCTestCase {
    func testEllipseRingClosedAndOffsetMovesAlongNormal() throws {
        let specA = makeEllipseSpec(offsetN: 0.0)
        let specB = makeEllipseSpec(offsetN: 30.0)

        let svgA = try renderSVGString(options: CLIOptions(), spec: specA)
        let svgB = try renderSVGString(options: CLIOptions(), spec: specB)
        XCTAssertTrue(svgA.contains("fill-rule=\"nonzero\""))

        guard let pathA = extractInkCompoundPathData(from: svgA),
              let pathB = extractInkCompoundPathData(from: svgB) else {
            XCTFail("Missing ink compound path data")
            return
        }

        let subpathsA = parseSubpaths(from: pathA)
        let subpathsB = parseSubpaths(from: pathB)
        XCTAssertEqual(subpathsA.count, 2)
        XCTAssertEqual(subpathsB.count, 2)

        let counterA = ensureClosed(subpathsA[1])
        let counterB = ensureClosed(subpathsB[1])
        XCTAssertFalse(counterA.isEmpty)
        XCTAssertFalse(counterB.isEmpty)
        XCTAssertTrue(Epsilon.approxEqual(counterA.first!, counterA.last!))
        XCTAssertTrue(Epsilon.approxEqual(counterB.first!, counterB.last!))

        let centroidA = ringCentroid(counterA)
        let centroidB = ringCentroid(counterB)
        let delta = centroidB - centroidA
        XCTAssertLessThan(abs(delta.x), 5.0)
        XCTAssertGreaterThan(abs(delta.y), 10.0)

        let inkArea = signedArea(ensureClosed(subpathsA[0]))
        let counterArea = signedArea(counterA)
        XCTAssertLessThan(inkArea, 0.0)
        XCTAssertGreaterThan(counterArea, 0.0)
    }
}

private func makeEllipseSpec(offsetN: Double) -> CP2Spec {
    let line = InkPrimitive.line(InkLine(p0: InkPoint(x: 0, y: 0), p1: InkPoint(x: 200, y: 0)))
    let ink = Ink(stem: nil, entries: ["line": line])
    let params = StrokeParams(
        angleMode: .relative,
        theta: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: 0.0)]),
        widthLeft: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 20.0), Keyframe(t: 1.0, value: 20.0)]),
        widthRight: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 20.0), Keyframe(t: 1.0, value: 20.0)]),
        offset: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: 0.0)])
    )
    let stroke = StrokeSpec(id: "line-stroke", type: .stroke, ink: "line", params: params)
    let counters = CounterSet(entries: [
        "hole": .ellipse(
            CounterEllipse(
                at: CounterAnchor(stroke: "line-stroke", t: 0.5),
                rx: 30,
                ry: 20,
                rotateDeg: 0,
                offset: CounterOffset(t: 0.0, n: offsetN)
            )
        )
    ])
    return CP2Spec(example: nil, render: nil, reference: nil, ink: ink, counters: counters, strokes: [stroke])
}

private func extractInkCompoundPathData(from svg: String) -> String? {
    guard let idRange = svg.range(of: "id=\"ink-compound\"") else { return nil }
    guard let dRange = svg.range(of: "d=\"", range: idRange.upperBound..<svg.endIndex) else { return nil }
    let start = dRange.upperBound
    guard let end = svg[start...].firstIndex(of: "\"") else { return nil }
    return String(svg[start..<end])
}

private func parseSubpaths(from d: String) -> [[Vec2]] {
    var subpaths: [[Vec2]] = []
    var current: [Vec2] = []
    let tokens = d.split { $0 == " " || $0 == "\n" || $0 == "\t" }
    var index = 0
    while index < tokens.count {
        let token = tokens[index]
        if token == "M" {
            if !current.isEmpty {
                subpaths.append(current)
                current = []
            }
            if index + 2 < tokens.count,
               let x = Double(tokens[index + 1]),
               let y = Double(tokens[index + 2]) {
                current.append(Vec2(x, y))
                index += 3
                continue
            }
        } else if token == "L" {
            if index + 2 < tokens.count,
               let x = Double(tokens[index + 1]),
               let y = Double(tokens[index + 2]) {
                current.append(Vec2(x, y))
                index += 3
                continue
            }
        } else if token == "Z" {
            if !current.isEmpty {
                subpaths.append(current)
                current = []
            }
            index += 1
            continue
        }
        index += 1
    }
    if !current.isEmpty {
        subpaths.append(current)
    }
    return subpaths
}

private func ensureClosed(_ ring: [Vec2]) -> [Vec2] {
    guard !ring.isEmpty else { return [] }
    if let first = ring.first, let last = ring.last, !Epsilon.approxEqual(first, last) {
        return ring + [first]
    }
    return ring
}

private func ringCentroid(_ ring: [Vec2]) -> Vec2 {
    guard !ring.isEmpty else { return Vec2(0, 0) }
    var sum = Vec2(0, 0)
    for point in ring { sum = sum + point }
    let denom = Double(ring.count)
    return Vec2(sum.x / denom, sum.y / denom)
}

private func signedArea(_ ring: [Vec2]) -> Double {
    guard ring.count >= 3 else { return 0.0 }
    var area = 0.0
    for i in 0..<(ring.count - 1) {
        let a = ring[i]
        let b = ring[i + 1]
        area += (a.x * b.y - b.x * a.y)
    }
    return area * 0.5
}
