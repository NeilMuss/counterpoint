import Foundation
import CP2Geometry

func loadReferenceAsset(
    layer: ReferenceLayer,
    warn: (String) -> Void
) -> (inner: String, viewBox: WorldRect)? {
    let url = URL(fileURLWithPath: layer.path)
    guard let data = try? Data(contentsOf: url),
          let svgText = String(data: data, encoding: .utf8) else {
        warn("reference file not found: \(layer.path)")
        return nil
    }
    
    guard let viewBox = parseSVGViewBox(svgText) else {
        return nil
    }
    
    let inner = extractSVGInnerContent(svgText)
    return (inner: inner, viewBox: viewBox)
}
