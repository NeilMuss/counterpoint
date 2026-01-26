import Foundation

public func warpT(t: Double, alpha: Double) -> Double {
    let clampedT = max(0.0, min(1.0, t))
    let exponent = exp(alpha)
    let warped = pow(clampedT, exponent)
    return max(0.0, min(1.0, warped))
}
