import Foundation
import CP2Geometry

public enum ErrorMetrics {
    /// Midpoint deviation from chord midpoint:
    /// err = distance(pm, (p0+p1)/2)
    public static func midpointDeviation(p0: Vec2, pm: Vec2, p1: Vec2) -> Double {
        let chordMid = (p0 + p1) * 0.5
        return (pm - chordMid).length
    }

    /// Rail error is max deviation of L and R from their chord midpoints.
    public static func railDeviation(l0: Vec2, lm: Vec2, l1: Vec2,
                                     r0: Vec2, rm: Vec2, r1: Vec2) -> Double {
        let le = midpointDeviation(p0: l0, pm: lm, p1: l1)
        let re = midpointDeviation(p0: r0, pm: rm, p1: r1)
        return max(le, re)
    }

    /// Param error: deviation from linear midpoint (dimensionless once normalized).
    public static func paramDeviation(v0: Double, vm: Double, v1: Double) -> Double {
        let mid = 0.5 * (v0 + v1)
        return abs(vm - mid)
    }
}
