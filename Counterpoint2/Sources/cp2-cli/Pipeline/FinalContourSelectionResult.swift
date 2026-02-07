import Foundation
import CP2Geometry

struct FinalContourSelectionResult {
    var finalContour: FinalContour
    var ring: [Vec2]
    var rings: [[Vec2]]
    var envelopeIndex: Int
    var envelopeAbsArea: Double
    var envelopeBBoxMin: Vec2
    var envelopeBBoxMax: Vec2
    var envelopeSelfX: Int
}
