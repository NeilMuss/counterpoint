import Foundation

public struct SnapKey: Hashable, Codable, Sendable {
    public let x: Int
    public let y: Int
}

public enum Epsilon {
    public static let defaultValue: Double = 1.0e-6

    public static func approxEqual(_ a: Double, _ b: Double, eps: Double = defaultValue) -> Bool {
        abs(a - b) <= eps
    }

    public static func approxEqual(_ a: Vec2, _ b: Vec2, eps: Double = defaultValue) -> Bool {
        approxEqual(a.x, b.x, eps: eps) && approxEqual(a.y, b.y, eps: eps)
    }

    public static func snapKey(_ v: Vec2, eps: Double = defaultValue) -> SnapKey {
        let inv = 1.0 / eps
        let x = Int(floor(v.x * inv + 0.5))
        let y = Int(floor(v.y * inv + 0.5))
        return SnapKey(x: x, y: y)
    }
}
