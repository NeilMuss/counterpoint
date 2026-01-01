import Foundation

public struct ParamField {
    public let evaluate: (Double) -> Double

    public init(evaluate: @escaping (Double) -> Double) {
        self.evaluate = evaluate
    }

    public static func linearDegrees(startDeg: Double, endDeg: Double) -> ParamField {
        ParamField { s in
            let clamped = ScalarMath.clamp01(s)
            return ScalarMath.lerp(startDeg, endDeg, clamped)
        }
    }
}
