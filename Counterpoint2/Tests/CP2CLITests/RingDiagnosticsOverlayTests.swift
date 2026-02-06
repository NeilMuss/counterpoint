import XCTest
import CP2Geometry
import CP2ResolveOverlap
import CP2Skeleton
import Foundation
import Darwin
@testable import cp2_cli

final class RingDiagnosticsOverlayTests: XCTestCase {
    func testRingOutputOutlineOverlayEmitsPath() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
        var options = parseArgs(["--view", "ringOutputOutline"])
        options.example = spec.example
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("<g id=\"debug-ring-output-outline\">"))
        XCTAssertEqual(svg.components(separatedBy: "class=\"ring-output\"").count - 1, 1)
    }

    func testRingOutputSelfXOverlayEmitsCirclesWhenSelfIntersectionsExist() throws {
        let render = RenderSettings(
            canvasPx: CanvasSize(width: 600, height: 600),
            fitMode: .none,
            paddingWorld: 0,
            clipToFrame: false,
            worldFrame: WorldRect(minX: -20, minY: -20, maxX: 140, maxY: 140)
        )
        let path = InkPath(segments: [
            .line(InkLine(p0: InkPoint(x: 0, y: 0), p1: InkPoint(x: 120, y: 120))),
            .line(InkLine(p0: InkPoint(x: 120, y: 120), p1: InkPoint(x: 0, y: 120))),
            .line(InkLine(p0: InkPoint(x: 0, y: 120), p1: InkPoint(x: 120, y: 0)))
        ])
        let ink = Ink(stem: .path(path), entries: ["stem": .path(path)])
        let spec = CP2Spec(example: nil, render: render, reference: nil, ink: ink)

        var options = parseArgs(["--view", "ringOutputSelfX"])
        options.penShape = .railsOnly
        options.resolveSelfOverlap = false

        let svg = try renderSVGString(options: options, spec: spec)

        let provider = ExampleParamProvider()
        let funcs = provider.makeParamFuncs(options: options, exampleName: nil, sweepWidth: 20.0)
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 6.0,
            sweepSampleCount: 64
        )
        let skeleton = SkeletonPath(segments: path.segments.map(cubicForSegment))
        let sweep = runSweep(
            path: skeleton,
            plan: plan,
            options: options,
            capNamespace: "test",
            startCap: .butt,
            endCap: .butt
        )
        let selfX = ringSelfIntersectionCount(sweep.finalContour.points)
        XCTAssertTrue(svg.contains("<g id=\"debug-ring-output-selfx\">"))
        if selfX > 0 {
            XCTAssertTrue(svg.contains("<circle"))
        }
    }

    func testEnvelopeCandidateAndResolvedFacesOverlaysEmitGroups() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
        var options = parseArgs(["--view", "envelopeCandidateOutline,resolvedFacesAll"])
        options.example = spec.example
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("<g id=\"debug-envelope-candidate-outline\">"))
        XCTAssertTrue(svg.contains("<g id=\"debug-resolved-faces-all\">"))
        let faceCount = svg.components(separatedBy: "class=\"resolved-face").count - 1
        XCTAssertGreaterThanOrEqual(faceCount, 2)
        XCTAssertTrue(svg.contains("resolved-face selected"))
    }

    func testDebugSummaryUsesFaceIdWhenResolved() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
        var options = parseArgs(["--view", "ringOutputOutline", "--debug-summary"])
        options.example = spec.example
        let output = try captureStdout {
            _ = try renderSVGString(options: options, spec: spec)
        }
        XCTAssertTrue(output.contains("OUTPUT faceId="))
    }

    func testDebugSummaryUsesRingIndexWhenNotResolved() throws {
        let path = InkPath(segments: [
            .line(InkLine(p0: InkPoint(x: 0, y: 0), p1: InkPoint(x: 120, y: 0)))
        ])
        let ink = Ink(stem: .path(path), entries: ["stem": .path(path)])
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
            counters: nil,
            strokes: [StrokeSpec(id: "stem", type: .stroke, ink: "stem", params: params)]
        )
        var options = parseArgs(["--debug-summary"])
        options.penShape = .railsOnly
        options.resolveSelfOverlap = false
        let output = try captureStdout {
            _ = try renderSVGString(options: options, spec: spec)
        }
        XCTAssertTrue(output.contains("OUTPUT ringIndex="))
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
