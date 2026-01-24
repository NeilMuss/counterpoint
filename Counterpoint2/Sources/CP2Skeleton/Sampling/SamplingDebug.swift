// Sources/CP2Skeleton/Sampling/SamplingDebug.swift
//
// Step 3.5 — “Why dots”
// Small, dependency-light helpers that turn SamplingResult.trace into
// renderable debug points.
//
// No SVG/CLI code here — just data extraction.
//
// IMPORTANT:
// - We plot midpoints (tm) for decisions that subdivided (or forcedStop)
// - We keep all reasons, so one point can show multiple triggers.
//

import Foundation
import CP2Geometry

public struct SamplingDebugPoint: Sendable, Equatable {
    public let s: Double                 // midpoint global-t (normalized arc-length fraction)
    public let depth: Int
    public let action: SampleAction
    public let reasons: [SampleReason]
    public let errors: SampleErrors

    public init(s: Double, depth: Int, action: SampleAction, reasons: [SampleReason], errors: SampleErrors) {
        self.s = s
        self.depth = depth
        self.action = action
        self.reasons = reasons
        self.errors = errors
    }

    public var triggersRailDeviation: Bool {
        reasons.contains { if case .subdivideRailDeviation = $0 { return true } else { return false } }
    }

    public var triggersFlatness: Bool {
        reasons.contains { if case .subdividePathFlatness = $0 { return true } else { return false } }
    }

    public var isForcedStop: Bool {
        reasons.contains { $0 == .maxDepthHit || $0 == .maxSamplesHit }
    }
}

public extension SamplingResult {
    /// Midpoint debug points for “interesting” decisions.
    /// By default, includes:
    /// - subdivided segments (the ones that caused recursion)
    /// - forced stops (max depth/samples)
    func debugPoints(includeAccepted: Bool = false) -> [SamplingDebugPoint] {
        trace.compactMap { d in
            switch d.action {
            case .accepted:
                if !includeAccepted { return nil }
            case .subdivided, .forcedStop:
                break
            }

            return SamplingDebugPoint(
                s: d.tm,
                depth: d.depth,
                action: d.action,
                reasons: d.reasons,
                errors: d.errors
            )
        }
    }

    /// Convenience: return the single “worst” point by rail error, if any.
    func worstRailPoint() -> SamplingDebugPoint? {
        debugPoints().max { (a, b) in
            (a.errors.railErr ?? 0) < (b.errors.railErr ?? 0)
        }
    }

    /// Convenience: return the single “worst” point by flatness error, if any.
    func worstFlatnessPoint() -> SamplingDebugPoint? {
        debugPoints().max { (a, b) in
            (a.errors.flatnessErr ?? 0) < (b.errors.flatnessErr ?? 0)
        }
    }
}
