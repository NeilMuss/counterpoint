import Foundation
import CP2Geometry
import CP2Skeleton

enum StoryStage: String, CaseIterable {
    case skeleton
    case keyframes
    case counterpoint
    case samples
    case rails
    case soup
    case ring
    case resolve
    case final

    var stageNumber: Int {
        switch self {
        case .skeleton: return 1
        case .keyframes: return 2
        case .counterpoint: return 3
        case .samples: return 4
        case .rails: return 5
        case .soup: return 6
        case .ring: return 7
        case .resolve: return 8
        case .final: return 9
        }
    }

    var filename: String {
        String(format: "%02d_%@.svg", stageNumber, rawValue)
    }

    static var defaultOrder: [StoryStage] {
        [.skeleton, .keyframes, .counterpoint, .samples, .rails, .soup, .ring, .resolve, .final]
    }
}

enum StoryboardContextMode: String {
    case none
    case prev
    case all
}

struct StoryCapabilities {
    let hasRails: Bool
    let hasSoup: Bool
    let hasRings: Bool
    let hasResolve: Bool
}

struct StoryContext {
    let canvas: CanvasSize
    let frame: WorldRect
    let path: SkeletonPath
    let pathParam: SkeletonPathParameterization
    let plan: SweepPlan?
    let params: StrokeParams?
    let sampling: SamplingResult?
    let ring: [Vec2]
    let railsLeft: [Vec2]?
    let railsRight: [Vec2]?
    let soupChains: [[Vec2]]?
    let rings: [[Vec2]]?
    let resolveBefore: [Vec2]?
    let resolveAfter: [Vec2]?
    let resolveIntersections: [Vec2]?
    let capabilities: StoryCapabilities
}

struct StoryboardCel {
    let stage: StoryStage
    let svg: String
}
