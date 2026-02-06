import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class RectCornersCapEdgesFixtureTests: XCTestCase {
    func testLine14WavyEmitsCapEdgesAndBridgesShortEdge() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
        guard let ink = spec.ink, let stroke = spec.strokes?.first, let params = stroke.params else {
            XCTFail("expected ink and stroke params")
            return
        }
        let segments = try resolveInkSegments(
            name: stroke.ink,
            ink: ink,
            strict: true,
            warn: { _ in }
        )
        let path = SkeletonPath(segments: segments.map(cubicForSegment))

        var options = CLIOptions()
        options.example = spec.example
        options.penShape = .rectCorners
        options.debugPenStamps = true

        let provider = SpecParamProvider(params: params)
        let funcs = provider.makeParamFuncs(options: options, exampleName: spec.example, sweepWidth: 20.0)
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 6.0,
            sweepSampleCount: 64
        )

        let sweep = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: "test",
            startCap: .butt,
            endCap: .butt
        )

        XCTAssertGreaterThan(sweep.soupCapSegments, 0)

        guard let stamps = sweep.penStamps?.samples, !stamps.isEmpty else {
            XCTFail("expected pen stamps")
            return
        }
        let peak = stamps.max { lhs, rhs in
            let ly = (lhs.corners[0].y + lhs.corners[1].y + lhs.corners[2].y + lhs.corners[3].y) * 0.25
            let ry = (rhs.corners[0].y + rhs.corners[1].y + rhs.corners[2].y + rhs.corners[3].y) * 0.25
            return ly < ry
        } ?? stamps[0]

        let corners = peak.corners
        let center = (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
        let edgePairs = [(0, 1), (1, 2), (2, 3), (3, 0)]
        var edges: [(len: Double, pair: (Int, Int), index: Int)] = []
        for (idx, pair) in edgePairs.enumerated() {
            let a = corners[pair.0]
            let b = corners[pair.1]
            edges.append(((a - b).length, pair, idx))
        }
        edges.sort { lhs, rhs in
            if lhs.len != rhs.len { return lhs.len < rhs.len }
            return lhs.index < rhs.index
        }
        let shortEdge = edges[0]
        let shortVec = corners[shortEdge.pair.1] - corners[shortEdge.pair.0]
        let shortLen = shortVec.length
        let shortDir = shortVec.normalized()

        var alignedCount = 0
        let ring = sweep.finalContour.points
        for i in 0..<(max(0, ring.count - 1)) {
            let a = ring[i]
            let b = ring[i + 1]
            let seg = b - a
            let len = seg.length
            if len <= 1.0e-6 { continue }
            let mid = (a + b) * 0.5
            if (mid - center).length > 60.0 { continue }
            let dir = seg * (1.0 / len)
            if abs(dir.dot(shortDir)) > 0.8 && len >= shortLen * 0.5 && len <= shortLen * 1.5 {
                alignedCount += 1
            }
        }
        XCTAssertGreaterThanOrEqual(alignedCount, 1)
    }

    func testDebugSummaryIncludesSoupEdges() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
        var options = parseArgs(["--debug-summary"])
        options.example = spec.example
        options.penShape = .rectCorners
        let output = try captureStdout {
            _ = try renderSVGString(options: options, spec: spec)
        }
        XCTAssertTrue(output.contains("SOUP_EDGES"))
        XCTAssertTrue(output.contains("capSegments="))
    }
}

private func captureStdout(_ block: () throws -> Void) rethrows -> String {
    let pipe = Pipe()
    let stdoutFd = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    try block()
    fflush(stdout)
    dup2(stdoutFd, STDOUT_FILENO)
    close(stdoutFd)
    pipe.fileHandleForWriting.closeFile()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
