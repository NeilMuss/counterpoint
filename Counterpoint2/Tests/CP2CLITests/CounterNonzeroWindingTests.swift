import XCTest
import CP2Geometry
@testable import cp2_cli

final class CounterNonzeroWindingTests: XCTestCase {
    func testCompoundPathUsesNonzeroAndOppositeWinding() throws {
        let outerPath = InkPath(segments: [
            .line(InkLine(p0: InkPoint(x: 0, y: 0), p1: InkPoint(x: 100, y: 0))),
            .line(InkLine(p0: InkPoint(x: 100, y: 0), p1: InkPoint(x: 100, y: 100))),
            .line(InkLine(p0: InkPoint(x: 100, y: 100), p1: InkPoint(x: 0, y: 100))),
            .line(InkLine(p0: InkPoint(x: 0, y: 100), p1: InkPoint(x: 0, y: 0)))
        ])
        let innerPath = InkPath(segments: [
            .line(InkLine(p0: InkPoint(x: 30, y: 30), p1: InkPoint(x: 70, y: 30))),
            .line(InkLine(p0: InkPoint(x: 70, y: 30), p1: InkPoint(x: 70, y: 70))),
            .line(InkLine(p0: InkPoint(x: 70, y: 70), p1: InkPoint(x: 30, y: 70))),
            .line(InkLine(p0: InkPoint(x: 30, y: 70), p1: InkPoint(x: 30, y: 30)))
        ])

        let ink = Ink(stem: nil, entries: ["outer": .path(outerPath)])
        let counters = CounterSet(entries: ["hole": .path(innerPath)])
        let params = StrokeParams(
            angleMode: .relative,
            theta: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: 0.0)]),
            widthLeft: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 12.0), Keyframe(t: 1.0, value: 12.0)]),
            widthRight: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 12.0), Keyframe(t: 1.0, value: 12.0)]),
            offset: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: 0.0)])
        )
        let spec = CP2Spec(
            example: nil,
            render: nil,
            reference: nil,
            ink: ink,
            counters: counters,
            strokes: [StrokeSpec(id: "outer", type: .stroke, ink: "outer", params: params)]
        )

        let svg = try renderSVGString(options: CLIOptions(), spec: spec)
        XCTAssertTrue(svg.contains("fill-rule=\"nonzero\""))

        guard let pathData = extractInkCompoundPathData(from: svg) else {
            XCTFail("Missing ink compound path")
            return
        }
        let subpaths = parseSubpaths(from: pathData)
        XCTAssertEqual(subpaths.count, 2)

        let outerArea = signedArea(ensureClosed(subpaths[0]))
        let innerArea = signedArea(ensureClosed(subpaths[1]))
        XCTAssertLessThan(outerArea, 0.0)
        XCTAssertGreaterThan(innerArea, 0.0)
        XCTAssertGreaterThan(abs(outerArea), abs(innerArea))
    }
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
