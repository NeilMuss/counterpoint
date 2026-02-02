import Foundation

public enum CapFilletCorner: String, Codable, Equatable {
    case left
    case right
    case both
}

public enum CapStyle: Codable, Equatable {
    case butt
    case round
    case ball
    case fillet(radius: Double, corner: CapFilletCorner)

    private enum CodingKeys: String, CodingKey {
        case type
        case radius
        case corner
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            switch text.lowercased() {
            case "round": self = .round
            case "ball": self = .ball
            case "fillet": self = .fillet(radius: 0.0, corner: .left)
            default: self = .butt
            }
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "butt"
        switch type.lowercased() {
        case "round":
            self = .round
        case "ball":
            self = .ball
        case "fillet":
            let radius = try container.decode(Double.self, forKey: .radius)
            let corner = (try? container.decode(CapFilletCorner.self, forKey: .corner)) ?? .left
            self = .fillet(radius: radius, corner: corner)
        default:
            self = .butt
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .butt:
            try container.encode("butt", forKey: .type)
        case .round:
            try container.encode("round", forKey: .type)
        case .ball:
            try container.encode("ball", forKey: .type)
        case .fillet(let radius, let corner):
            try container.encode("fillet", forKey: .type)
            try container.encode(radius, forKey: .radius)
            if corner != .left {
                try container.encode(corner, forKey: .corner)
            }
        }
    }
}
