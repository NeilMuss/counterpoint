import Foundation
import Domain

public struct PassthroughPolygonUnioner: PolygonUnioning {
    public init() {}

    public func union(subjectRings: [Ring]) throws -> PolygonSet {
        subjectRings.map { Polygon(outer: $0, holes: []) }
    }
}
