import XCTest
@testable import cp2_cli
import CP2Geometry

final class EHeartlineResolutionTests: XCTestCase {
    func testEHeartlineResolvesLoopOnly() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/e.v0.json")
        guard let ink = spec.ink else {
            XCTFail("expected ink in spec")
            return
        }
        XCTAssertNotNil(ink.entries["upper_loop"])
        XCTAssertNotNil(ink.entries["lower_loop"])
        XCTAssertNotNil(ink.entries["e_bowl"])

        guard case .heartline(let heartline)? = ink.entries["e_bowl"] else {
            XCTFail("expected e_bowl to be a heartline")
            return
        }

        let resolved = try resolveHeartline(
            name: "e_bowl",
            heartline: heartline,
            ink: ink,
            strict: true,
            warn: { _ in }
        )
        let segments = resolved.subpaths.flatMap { $0 }
        XCTAssertTrue(segments.contains { if case .cubic = $0 { return true } else { return false } })

        let crossA = Vec2(75, 166)
        let crossB = Vec2(375, 166)
        let eps = 1.0e-6
        for segment in segments {
            if case .line(let line) = segment {
                let a = vec(line.p0)
                let b = vec(line.p1)
                let matchesForward = (a - crossA).length <= eps && (b - crossB).length <= eps
                let matchesReverse = (a - crossB).length <= eps && (b - crossA).length <= eps
                XCTAssertFalse(matchesForward || matchesReverse, "cross line should not be in loop-only heartline")
            }
        }
    }

    func testHeartlineMissingPartThrows() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/e.v0.json")
        guard var ink = spec.ink else {
            XCTFail("expected ink in spec")
            return
        }
        ink.entries["e_bowl"] = .heartline(Heartline(parts: ["missing_part"]))
        guard case .heartline(let heartline)? = ink.entries["e_bowl"] else {
            XCTFail("expected e_bowl to be a heartline")
            return
        }
        XCTAssertThrowsError(
            try resolveHeartline(
                name: "e_bowl",
                heartline: heartline,
                ink: ink,
                strict: true,
                warn: { _ in }
            )
        ) { error in
            guard case InkContinuityError.missingPart(name: "e_bowl", part: "missing_part") = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }
}
