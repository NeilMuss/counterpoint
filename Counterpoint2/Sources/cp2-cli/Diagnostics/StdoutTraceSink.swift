import Foundation
import CP2Domain
import CP2Geometry

struct StdoutTraceSink: TraceSink {
    func emit(_ event: TraceEvent) {
        switch event {
        case .soupNeighborhood(let payload):
            print(String(format: "soupNeighborhood label=%@ center=(%.6f,%.6f) r=%.6f nodes=%d collisions=%d", payload.label, payload.center.x, payload.center.y, payload.radius, payload.nodes.count, payload.collisions.count))
            for node in payload.nodes {
                print(String(format: "  node key=(%d,%d) pos=(%.6f,%.6f) degree=%d", node.keyX, node.keyY, node.pos.x, node.pos.y, node.degree))
                for edge in node.edges {
                    let segIndexText = edge.segmentIndex.map(String.init) ?? "none"
                    print(String(format: "    out -> key=(%d,%d) pos=(%.6f,%.6f) len=%.6f dir=(%.6f,%.6f) src=%@ segIndex=%@", edge.toKeyX, edge.toKeyY, edge.toPos.x, edge.toPos.y, edge.len, edge.dir.x, edge.dir.y, edge.sourceDescription, segIndexText))
                }
            }
            if !payload.collisions.isEmpty {
                print(String(format: "soupNeighborhood collisions=%d", payload.collisions.count))
                for collision in payload.collisions {
                    let positions = collision.positions.map { String(format: "(%.6f,%.6f)", $0.x, $0.y) }.joined(separator: ", ")
                    print(String(format: "  collision key=(%d,%d) positions=[%@]", collision.keyX, collision.keyY, positions))
                }
            }
        case .capFilletSuccess(let payload):
            print(String(format: "capFillet kind=%@ side=%@ r=%.6f theta=%.6f d=%.6f corner=(%.6f,%.6f) P=(%.6f,%.6f) Q=(%.6f,%.6f)", payload.kind, payload.side, payload.radius, payload.theta, payload.d, payload.corner.x, payload.corner.y, payload.p.x, payload.p.y, payload.q.x, payload.q.y))
        case .capFilletFailure(let payload):
            print(String(format: "capFillet kind=%@ side=%@ r=%.6f failed=%@", payload.kind, payload.side, payload.radius, payload.reason))
        case .capFilletMidSegmentFound(let payload):
            let midAText = String(format: "(%.3f,%.3f)", payload.midA.x, payload.midA.y)
            let midBText = String(format: "(%.3f,%.3f)", payload.midB.x, payload.midB.y)
            print("capFilletMidSegmentFound count=\(payload.count) midA=\(midAText) midB=\(midBText)")
        case .capFilletMidSegmentDetail(let payload):
            print(String(format: "  mid len=%.6f a=(%.3f,%.3f) b=(%.3f,%.3f) src=%@", payload.len, payload.a.x, payload.a.y, payload.b.x, payload.b.y, payload.sourceDescription))
        case .capFilletBypassEdgesFound(let payload):
            let cornerAText = String(format: "(%.3f,%.3f)", payload.cornerA.x, payload.cornerA.y)
            let cornerBText = String(format: "(%.3f,%.3f)", payload.cornerB.x, payload.cornerB.y)
            print("capFilletBypassEdgesFound count=\(payload.count) cornerA=\(cornerAText) cornerB=\(cornerBText)")
        case .capFilletBypassDetail(let payload):
            print(String(format: "  bypass len=%.6f a=(%.3f,%.3f) b=(%.3f,%.3f) src=%@", payload.len, payload.a.x, payload.a.y, payload.b.x, payload.b.y, payload.sourceDescription))
        case .capFilletConnectivity(let ok):
            print("capFilletConnectivity ok=\(ok)")
        case .capFilletXTouch(let payload):
            let epsText = String(format: "%.1e", payload.eps)
            print("capFilletXTouch count=\(payload.count) x=\(payload.x) eps=\(epsText)")
        case .capFilletXTouchDetail(let payload):
            print(String(format: "  xTouch len=%.6f a=(%.3f,%.3f) b=(%.3f,%.3f) src=%@", payload.len, payload.a.x, payload.a.y, payload.b.x, payload.b.y, payload.sourceDescription))
        case .resolveSelfOverlap(let payload):
            let enabled = payload.enabledExplicit ? "true" : "auto"
            print(String(format: "RESOLVE_SELF_OVERLAP enabled=%@ ringSelfXBefore=%d ringSelfXAfter=%d vertsBefore=%d vertsAfter=%d", enabled, payload.ringSelfXBefore, payload.ringSelfXAfter, payload.vertsBefore, payload.vertsAfter))
        case .resolveSelfOverlapFallback(let reason):
            print(String(format: "RESOLVE_SELF_OVERLAP_FALLBACK reason=%@", reason))
        case .ringTopoCount(let count):
            print("RING_TOPO ringCount=\(count)")
        case .ringTopoInfo(let payload):
            print(String(format: "RING_TOPO ring=%d absArea=%.6f winding=%@ verts=%d", payload.index, payload.absArea, payload.winding, payload.verts))
        case .ringSelfXCount(let ringIndex, let count):
            print(String(format: "RING_SELF_X ring=%d count=%d", ringIndex, count))
        case .ringSelfXHit(let payload):
            print(String(format: "RING_SELF_X hit ring=%d i=%d j=%d P=(%.6f,%.6f)", payload.ringIndex, payload.i, payload.j, payload.point.x, payload.point.y))
        case .ringMicro(let ringIndex, let absArea):
            print(String(format: "RING_MICRO ring=%d absArea=%.6f", ringIndex, absArea))
        case .ringSelfXHitDetail(let payload):
            print(String(format: "RING_SELF_X_HIT k=%d ring=%d i=%d j=%d P=(%.6f,%.6f) A0=(%.6f,%.6f) A1=(%.6f,%.6f) B0=(%.6f,%.6f) B1=(%.6f,%.6f)", payload.k, payload.ringIndex, payload.i, payload.j, payload.point.x, payload.point.y, payload.a0.x, payload.a0.y, payload.a1.x, payload.a1.y, payload.b0.x, payload.b0.y, payload.b1.x, payload.b1.y))
        case .ringSelfXHitOutOfRange(let k, let count):
            print(String(format: "RING_SELF_X_HIT k=%d out_of_range count=%d", k, count))
        }
    }
}
