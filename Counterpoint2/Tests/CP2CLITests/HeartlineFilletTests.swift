import XCTest
import CP2Geometry
@testable import cp2_cli

final class HeartlineFilletTests: XCTestCase {
    func testFilletJoinIsG1ContinuousAndOffsetsMatch() throws {
        let lineA = InkPrimitive.line(InkLine(p0: InkPoint(x: 0, y: 0), p1: InkPoint(x: 100, y: 0)))
        let lineB = InkPrimitive.line(InkLine(p0: InkPoint(x: 100, y: 0), p1: InkPoint(x: 100, y: 100)))
        let heartline = Heartline(parts: [
            .spec(HeartlinePartSpec(name: "a")),
            .spec(HeartlinePartSpec(name: "b", joinKnot: .fillet(radius: 20)))
        ])
        let ink = Ink(stem: nil, entries: ["a": lineA, "b": lineB, "hl": .heartline(heartline)])

        let resolved = try resolveHeartline(
            name: "hl",
            heartline: heartline,
            ink: ink,
            strict: true,
            warn: { _ in }
        )
        XCTAssertEqual(resolved.fillets.count, 1)
        guard let fillet = resolved.fillets.first else {
            XCTFail("Missing fillet debug")
            return
        }

        XCTAssertTrue(approxEqual(fillet.start, Vec2(80, 0), eps: 1.0e-2))
        XCTAssertTrue(approxEqual(fillet.end, Vec2(100, 20), eps: 1.0e-2))

        guard case .cubic(let cubic) = fillet.bridge else {
            XCTFail("Expected cubic bridge")
            return
        }
        let bridgeStart = (vec(cubic.p1) - vec(cubic.p0)).normalized()
        let bridgeEnd = (vec(cubic.p3) - vec(cubic.p2)).normalized()
        XCTAssertGreaterThan(bridgeStart.dot(fillet.startTangent), 0.99)
        XCTAssertGreaterThan(bridgeEnd.dot(fillet.endTangent), 0.99)
        XCTAssertFalse(resolved.subpaths.isEmpty)
    }
}

private func approxEqual(_ a: Vec2, _ b: Vec2, eps: Double) -> Bool {
    abs(a.x - b.x) <= eps && abs(a.y - b.y) <= eps
}
