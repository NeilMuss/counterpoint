import CP2Domain
import CP2Geometry

struct StrokeInkEntry {
    let index: Int
    let strokeId: String?
    let inkName: String?
    let ring: [Vec2]
}

struct CounterRingEntry {
    let ring: [Vec2]
    let appliesTo: [String]?
}

struct RenderGlyphModel {
    let effectiveOptions: CLIOptions
    let renderSettings: RenderSettings
    let frame: WorldRect
    let referenceLayer: ReferenceLayer?
    let referenceSVGInner: String?
    let referenceViewBox: WorldRect?
    let strokeEntries: [StrokeInkEntry]
    let counterRingsNormalized: [CounterRingEntry]
    let debugOverlaySVG: String
    let combinedGlyphBounds: AABB?
    let exampleName: String?
}
