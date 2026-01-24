import CP2Geometry
import Foundation

public enum SamplingWhyReason: Sendable, Equatable {
    case flatness
    case railDeviation
    case both
    case forcedStop
}

public struct SamplingWhyDot: Sendable, Equatable {
    public let s: Double
    public let position: Vec2
    public let severity: Double
    public let reason: SamplingWhyReason
    public let action: SampleAction
    public let errors: SampleErrors
    public let depth: Int

    public init(
        s: Double,
        position: Vec2,
        severity: Double,
        reason: SamplingWhyReason,
        action: SampleAction,
        errors: SampleErrors,
        depth: Int
    ) {
        self.s = s
        self.position = position
        self.severity = severity
        self.reason = reason
        self.action = action
        self.errors = errors
        self.depth = depth
    }
}

public func samplingWhyDots(
    result: SamplingResult,
    flatnessEps: Double,
    railEps: Double,
    positionAtS: (Double) -> Vec2
) -> [SamplingWhyDot] {
    let epsFlat = max(flatnessEps, 1.0e-12)
    let epsRail = max(railEps, 1.0e-12)

    return result.debugPoints().compactMap { point -> SamplingWhyDot? in
        let isDecision =
            point.action == .subdivided ||
            point.action == .forcedStop ||
            point.isForcedStop
        guard isDecision else { return nil }

        let forced = point.action == .forcedStop || point.isForcedStop
        let flat = point.triggersFlatness
        let rail = point.triggersRailDeviation

        let reason: SamplingWhyReason
        if forced {
            reason = .forcedStop
        } else if flat && rail {
            reason = .both
        } else if flat {
            reason = .flatness
        } else if rail {
            reason = .railDeviation
        } else {
            reason = .forcedStop
        }

        let flatNorm = (point.errors.flatnessErr ?? 0.0) / epsFlat
        let railNorm = (point.errors.railErr ?? 0.0) / epsRail
        var severity = max(flatNorm, railNorm)
        if forced && severity <= 0.0 {
            severity = 1.0
        }

        return SamplingWhyDot(
            s: point.s,
            position: positionAtS(point.s),
            severity: max(0.0, severity),
            reason: reason,
            action: point.action,
            errors: point.errors,
            depth: point.depth
        )
    }
}
