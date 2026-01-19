import XCTest
import CP2Geometry

final class RenderSettingsTests: XCTestCase {
    func testWorldFrameStableWithExplicitFrame() {
        let settings = RenderSettings(
            canvasPx: CanvasSize(width: 1200, height: 1200),
            fitMode: .none,
            paddingWorld: 30.0,
            clipToFrame: false,
            worldFrame: WorldRect(minX: -10, minY: -20, maxX: 110, maxY: 220)
        )
        let glyphA = AABB(min: Vec2(0, 0), max: Vec2(50, 50))
        let glyphB = AABB(min: Vec2(-100, -100), max: Vec2(300, 300))

        let frameA = resolveWorldFrame(
            settings: settings,
            glyphBounds: glyphA,
            referenceBounds: nil,
            debugBounds: nil
        )
        let frameB = resolveWorldFrame(
            settings: settings,
            glyphBounds: glyphB,
            referenceBounds: nil,
            debugBounds: nil
        )
        XCTAssertEqual(frameA, frameB)
        XCTAssertEqual(frameA, settings.worldFrame?.padded(by: settings.paddingWorld))
    }

    func testFitModeEverythingIncludesDebugBounds() {
        let settingsGlyph = RenderSettings(
            canvasPx: CanvasSize(width: 1200, height: 1200),
            fitMode: .glyph,
            paddingWorld: 0.0,
            clipToFrame: false,
            worldFrame: nil
        )
        let settingsEverything = RenderSettings(
            canvasPx: CanvasSize(width: 1200, height: 1200),
            fitMode: .everything,
            paddingWorld: 0.0,
            clipToFrame: false,
            worldFrame: nil
        )
        let glyph = AABB(min: Vec2(0, 0), max: Vec2(10, 10))
        let debug = AABB(min: Vec2(-5, -5), max: Vec2(20, 20))

        let frameGlyph = resolveWorldFrame(
            settings: settingsGlyph,
            glyphBounds: glyph,
            referenceBounds: nil,
            debugBounds: debug
        )
        let frameEverything = resolveWorldFrame(
            settings: settingsEverything,
            glyphBounds: glyph,
            referenceBounds: nil,
            debugBounds: debug
        )

        XCTAssertEqual(frameGlyph, WorldRect.fromAABB(glyph))
        XCTAssertEqual(frameEverything, WorldRect.fromAABB(glyph.union(debug)))
    }

    func testReferenceTransformMatrixStable() {
        let ref = ReferenceLayer(
            path: "Fixtures/references/example.svg",
            translateWorld: Vec2(10, -5),
            scale: 2.0,
            rotateDeg: 90.0,
            opacity: 0.35,
            lockPlacement: true
        )
        let matrix = referenceTransformMatrix(ref)

        let radians = 90.0 * Double.pi / 180.0
        let cosA = cos(radians)
        let sinA = sin(radians)
        let expected = Transform2D(
            a: ref.scale * cosA,
            b: ref.scale * sinA,
            c: ref.scale * -sinA,
            d: ref.scale * cosA,
            tx: ref.translateWorld.x,
            ty: ref.translateWorld.y
        )
        XCTAssertEqual(matrix, expected)
    }
}
