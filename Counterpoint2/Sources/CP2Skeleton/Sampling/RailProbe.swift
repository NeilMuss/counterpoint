import Foundation
import CP2Geometry

// You can swap this to whatever vector type CP2Geometry uses.
public struct RailSample: Sendable, Equatable {
    public let left: Vec2
    public let right: Vec2
    public init(left: Vec2, right: Vec2) { self.left = left; self.right = right }
}

/// A tiny adapter the sampler can call.
/// - In geometry-only tests, use a probe that throws or returns dummy rails.
/// - In real rendering, this uses your skeleton frame + stroke params to compute L/R rails at global-t.
public protocol RailProbe: Sendable {
    func rails(atGlobalT t: Double) -> RailSample
}

/// A no-op probe for cases where you only want path-flatness refinement.
public struct NullRailProbe: RailProbe {
    public init() {}

    public func rails(atGlobalT t: Double) -> RailSample {
        return RailSample(left: Vec2(0, 0), right: Vec2(0, 0))
    }
}

