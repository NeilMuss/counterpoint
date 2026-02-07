import Foundation
import CP2Geometry

public protocol TraceSink {
    func emit(_ event: TraceEvent)
}

public enum TraceEvent: Equatable, Sendable {
    case soupNeighborhood(TraceSoupNeighborhood)
    case capFilletSuccess(TraceCapFilletSuccess)
    case capFilletFailure(TraceCapFilletFailure)
    case capFilletMidSegmentFound(TraceCapFilletMidSegment)
    case capFilletMidSegmentDetail(TraceCapFilletSegmentDetail)
    case capFilletBypassEdgesFound(TraceCapFilletBypass)
    case capFilletBypassDetail(TraceCapFilletSegmentDetail)
    case capFilletConnectivity(ok: Bool)
    case capFilletXTouch(TraceCapFilletXTouch)
    case capFilletXTouchDetail(TraceCapFilletSegmentDetail)
    case resolveSelfOverlap(TraceResolveSelfOverlap)
    case resolveSelfOverlapFallback(reason: String)
    case ringTopoCount(count: Int)
    case ringTopoInfo(TraceRingTopoInfo)
    case ringSelfXCount(ringIndex: Int, count: Int)
    case ringSelfXHit(TraceRingSelfXHit)
    case ringMicro(ringIndex: Int, absArea: Double)
    case ringSelfXHitDetail(TraceRingSelfXHitDetail)
    case ringSelfXHitOutOfRange(k: Int, count: Int)
}

public struct TraceSoupNeighborhood: Equatable, Sendable {
    public let label: String
    public let center: Vec2
    public let radius: Double
    public let nodes: [TraceSoupNeighborhoodNode]
    public let collisions: [TraceSoupNeighborhoodCollision]

    public init(label: String, center: Vec2, radius: Double, nodes: [TraceSoupNeighborhoodNode], collisions: [TraceSoupNeighborhoodCollision]) {
        self.label = label
        self.center = center
        self.radius = radius
        self.nodes = nodes
        self.collisions = collisions
    }
}

public struct TraceSoupNeighborhoodNode: Equatable, Sendable {
    public let keyX: Int
    public let keyY: Int
    public let pos: Vec2
    public let degree: Int
    public let edges: [TraceSoupNeighborhoodEdge]

    public init(keyX: Int, keyY: Int, pos: Vec2, degree: Int, edges: [TraceSoupNeighborhoodEdge]) {
        self.keyX = keyX
        self.keyY = keyY
        self.pos = pos
        self.degree = degree
        self.edges = edges
    }
}

public struct TraceSoupNeighborhoodEdge: Equatable, Sendable {
    public let toKeyX: Int
    public let toKeyY: Int
    public let toPos: Vec2
    public let len: Double
    public let dir: Vec2
    public let sourceDescription: String
    public let segmentIndex: Int?

    public init(toKeyX: Int, toKeyY: Int, toPos: Vec2, len: Double, dir: Vec2, sourceDescription: String, segmentIndex: Int?) {
        self.toKeyX = toKeyX
        self.toKeyY = toKeyY
        self.toPos = toPos
        self.len = len
        self.dir = dir
        self.sourceDescription = sourceDescription
        self.segmentIndex = segmentIndex
    }
}

public struct TraceSoupNeighborhoodCollision: Equatable, Sendable {
    public let keyX: Int
    public let keyY: Int
    public let positions: [Vec2]

    public init(keyX: Int, keyY: Int, positions: [Vec2]) {
        self.keyX = keyX
        self.keyY = keyY
        self.positions = positions
    }
}

public struct TraceCapFilletSuccess: Equatable, Sendable {
    public let kind: String
    public let side: String
    public let radius: Double
    public let theta: Double
    public let d: Double
    public let corner: Vec2
    public let p: Vec2
    public let q: Vec2

    public init(kind: String, side: String, radius: Double, theta: Double, d: Double, corner: Vec2, p: Vec2, q: Vec2) {
        self.kind = kind
        self.side = side
        self.radius = radius
        self.theta = theta
        self.d = d
        self.corner = corner
        self.p = p
        self.q = q
    }
}

public struct TraceCapFilletFailure: Equatable, Sendable {
    public let kind: String
    public let side: String
    public let radius: Double
    public let reason: String

    public init(kind: String, side: String, radius: Double, reason: String) {
        self.kind = kind
        self.side = side
        self.radius = radius
        self.reason = reason
    }
}

public struct TraceCapFilletMidSegment: Equatable, Sendable {
    public let count: Int
    public let midA: Vec2
    public let midB: Vec2

    public init(count: Int, midA: Vec2, midB: Vec2) {
        self.count = count
        self.midA = midA
        self.midB = midB
    }
}

public struct TraceCapFilletBypass: Equatable, Sendable {
    public let count: Int
    public let cornerA: Vec2
    public let cornerB: Vec2

    public init(count: Int, cornerA: Vec2, cornerB: Vec2) {
        self.count = count
        self.cornerA = cornerA
        self.cornerB = cornerB
    }
}

public struct TraceCapFilletSegmentDetail: Equatable, Sendable {
    public let len: Double
    public let a: Vec2
    public let b: Vec2
    public let sourceDescription: String

    public init(len: Double, a: Vec2, b: Vec2, sourceDescription: String) {
        self.len = len
        self.a = a
        self.b = b
        self.sourceDescription = sourceDescription
    }
}

public struct TraceCapFilletXTouch: Equatable, Sendable {
    public let count: Int
    public let x: Double
    public let eps: Double

    public init(count: Int, x: Double, eps: Double) {
        self.count = count
        self.x = x
        self.eps = eps
    }
}

public struct TraceResolveSelfOverlap: Equatable, Sendable {
    public let enabledExplicit: Bool
    public let ringSelfXBefore: Int
    public let ringSelfXAfter: Int
    public let vertsBefore: Int
    public let vertsAfter: Int

    public init(enabledExplicit: Bool, ringSelfXBefore: Int, ringSelfXAfter: Int, vertsBefore: Int, vertsAfter: Int) {
        self.enabledExplicit = enabledExplicit
        self.ringSelfXBefore = ringSelfXBefore
        self.ringSelfXAfter = ringSelfXAfter
        self.vertsBefore = vertsBefore
        self.vertsAfter = vertsAfter
    }
}

public struct TraceRingTopoInfo: Equatable, Sendable {
    public let index: Int
    public let absArea: Double
    public let winding: String
    public let verts: Int

    public init(index: Int, absArea: Double, winding: String, verts: Int) {
        self.index = index
        self.absArea = absArea
        self.winding = winding
        self.verts = verts
    }
}

public struct TraceRingSelfXHit: Equatable, Sendable {
    public let ringIndex: Int
    public let i: Int
    public let j: Int
    public let point: Vec2

    public init(ringIndex: Int, i: Int, j: Int, point: Vec2) {
        self.ringIndex = ringIndex
        self.i = i
        self.j = j
        self.point = point
    }
}

public struct TraceRingSelfXHitDetail: Equatable, Sendable {
    public let k: Int
    public let ringIndex: Int
    public let i: Int
    public let j: Int
    public let point: Vec2
    public let a0: Vec2
    public let a1: Vec2
    public let b0: Vec2
    public let b1: Vec2

    public init(k: Int, ringIndex: Int, i: Int, j: Int, point: Vec2, a0: Vec2, a1: Vec2, b0: Vec2, b1: Vec2) {
        self.k = k
        self.ringIndex = ringIndex
        self.i = i
        self.j = j
        self.point = point
        self.a0 = a0
        self.a1 = a1
        self.b0 = b0
        self.b1 = b1
    }
}
