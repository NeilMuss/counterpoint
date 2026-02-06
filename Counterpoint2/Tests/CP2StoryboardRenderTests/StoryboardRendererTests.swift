import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class StoryboardRendererTests: XCTestCase {
    private func makeContext(sampleCount: Int) -> StoryContext {
        let p0 = Vec2(0, 0)
        let p1 = Vec2(0, 0)
        let p2 = Vec2(100, 0)
        let p3 = Vec2(100, 0)
        let cubic = CubicBezier2(p0: p0, p1: p1, p2: p2, p3: p3)
        let path = SkeletonPath(cubic)
        let pathParam = SkeletonPathParameterization(path: path, samplesPerSegment: 8)
        let ts = (0..<sampleCount).map { Double($0) / Double(max(1, sampleCount - 1)) }
        let sampling = SamplingResult(ts: ts, trace: [], stats: SamplingStats())
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(100, 0),
            Vec2(100, 50),
            Vec2(0, 50),
            Vec2(0, 0)
        ]
        let capabilities = StoryCapabilities(
            hasRails: false,
            hasSoup: false,
            hasRings: false,
            hasResolve: false
        )
        return StoryContext(
            canvas: CanvasSize(width: 800, height: 600),
            frame: WorldRect(minX: -10, minY: -20, maxX: 110, maxY: 60),
            path: path,
            pathParam: pathParam,
            plan: nil,
            params: nil,
            sampling: sampling,
            ring: ring,
            railsLeft: nil,
            railsRight: nil,
            soupChains: nil,
            rings: nil,
            resolveBefore: nil,
            resolveAfter: nil,
            resolveIntersections: nil,
            capabilities: capabilities
        )
    }

    func test_AllStages_WritesNineFiles_WhenAllRequested() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = makeContext(sampleCount: 5)
        let stages = StoryStage.defaultOrder
        let cels = StoryboardRenderer.renderCels(context: context, stages: stages, contextMode: .none)
        try StoryboardRenderer.writeCels(cels: cels, outDir: tmp)
        for stage in StoryStage.defaultOrder {
            let path = tmp.appendingPathComponent(stage.filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        }
    }

    func test_CelSVG_ContainsExpectedGroupIDs() {
        let context = makeContext(sampleCount: 3)
        let stages: [StoryStage] = [.skeleton, .keyframes, .samples, .final]
        let cels = StoryboardRenderer.renderCels(context: context, stages: stages, contextMode: .none)
        let byStage = Dictionary(uniqueKeysWithValues: cels.map { ($0.stage, $0.svg) })

        XCTAssertTrue(byStage[.skeleton]?.contains("<g id=\"cel-skeleton\">") ?? false)
        XCTAssertTrue(byStage[.skeleton]?.contains("<g id=\"debug-skeleton\">") ?? false)

        XCTAssertTrue(byStage[.keyframes]?.contains("<g id=\"cel-keyframes\">") ?? false)
        XCTAssertTrue(byStage[.keyframes]?.contains("<g id=\"debug-keyframes\">") ?? false)

        XCTAssertTrue(byStage[.samples]?.contains("<g id=\"cel-samples\">") ?? false)
        XCTAssertTrue(byStage[.samples]?.contains("<g id=\"debug-samples\">") ?? false)

        XCTAssertTrue(byStage[.final]?.contains("<g id=\"cel-final\">") ?? false)
        XCTAssertTrue(byStage[.final]?.contains("<g id=\"final-silhouette\">") ?? false)
    }

    func test_SamplesCel_HasExpectedDotCount() {
        let context = makeContext(sampleCount: 7)
        let stages: [StoryStage] = [.samples]
        let cels = StoryboardRenderer.renderCels(context: context, stages: stages, contextMode: .none)
        guard let svg = cels.first?.svg else {
            XCTFail("missing samples cel")
            return
        }
        let dotCount = svg.components(separatedBy: "<circle ").count - 1
        XCTAssertEqual(dotCount, 7)
    }

    func test_Storyboard_MissingStages_StillWritesPlaceholderSVG() {
        let context = makeContext(sampleCount: 3)
        let stages: [StoryStage] = [.rails, .soup, .ring, .resolve]
        let cels = StoryboardRenderer.renderCels(context: context, stages: stages, contextMode: .none)
        let byStage = Dictionary(uniqueKeysWithValues: cels.map { ($0.stage, $0.svg) })
        XCTAssertTrue(byStage[.rails]?.contains("<g id=\"placeholder-rails\">") ?? false)
        XCTAssertTrue(byStage[.soup]?.contains("<g id=\"placeholder-soup\">") ?? false)
        XCTAssertTrue(byStage[.ring]?.contains("<g id=\"placeholder-ring\">") ?? false)
        XCTAssertTrue(byStage[.resolve]?.contains("<g id=\"placeholder-resolve\">") ?? false)
    }

    func test_ContextPrev_IncludesEarlierStagesInGrey() {
        let context = makeContext(sampleCount: 5)
        let stages: [StoryStage] = [.samples]
        let cels = StoryboardRenderer.renderCels(context: context, stages: stages, contextMode: .prev)
        guard let svg = cels.first?.svg else {
            XCTFail("missing samples cel")
            return
        }
        XCTAssertTrue(svg.contains("id=\"context-skeleton\""))
        XCTAssertTrue(svg.contains("id=\"context-keyframes\""))
        XCTAssertTrue(svg.contains("id=\"focus\""))
        XCTAssertTrue(svg.contains("id=\"debug-samples\""))
    }

    func test_Numbering_IsFixedAndNotRenumbered() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = makeContext(sampleCount: 3)
        let stages: [StoryStage] = [.final]
        let cels = StoryboardRenderer.renderCels(context: context, stages: stages, contextMode: .none)
        try StoryboardRenderer.writeCels(cels: cels, outDir: tmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("09_final.svg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("01_final.svg").path))
    }
}
