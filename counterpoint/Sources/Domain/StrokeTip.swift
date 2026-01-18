public typealias StrokeTipID = String

public struct StrokeTipSpec: Codable, Equatable {
    public let id: StrokeTipID
    public let offset: Double

    public init(id: StrokeTipID, offset: Double) {
        self.id = id
        self.offset = offset
    }
}

public struct StrokeTips<T: Codable & Equatable>: Codable, Equatable {
    public let tips: [StrokeTipID: T]

    public init(tips: [StrokeTipID: T]) {
        self.tips = tips
    }

    public static func single(_ value: T) -> StrokeTips<T> {
        StrokeTips(tips: ["default": value])
    }

    public var isSingle: Bool {
        tips.count == 1 && tips["default"] != nil
    }

    public var `default`: T? {
        tips["default"]
    }
}
