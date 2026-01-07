import Foundation

public enum FinalOutlineConsolidationMode {
    case unionAuto
    case unionOff
    case trace
}

public enum OutlineTracer {
    public static func traceSilhouette(_ input: PolygonSet, epsilon: Double) -> PolygonSet {
        let result = Rasterizer.rasterize(polygons: input, epsilon: epsilon)
        let contours = ContourTracer.trace(grid: result.grid, origin: result.origin, pixelSize: result.pixelSize)
        var polygons = ContourTracer.assemblePolygons(from: contours)
        let preFilterCount = polygons.count
        let minArea = result.pixelSize * result.pixelSize * 64.0
        polygons = filterSmallPolygons(polygons, minArea: minArea, keepTop: 20)
        print("trace: eps=\(String(format: "%.6f", epsilon)) pixelSize=\(String(format: "%.6f", result.pixelSize)) grid=\(result.grid.width)x\(result.grid.height) inputPolys=\(input.count) rings=\(contours.count) polys pre=\(preFilterCount) post=\(polygons.count) minArea=\(String(format: "%.6f", minArea))")
        return polygons
    }
}

private func filterSmallPolygons(_ polygons: PolygonSet, minArea: Double, keepTop: Int) -> PolygonSet {
    let filtered = polygons.filter { abs(signedArea($0.outer)) >= minArea }
    let sorted = filtered.sorted { abs(signedArea($0.outer)) > abs(signedArea($1.outer)) }
    if sorted.count <= keepTop { return sorted }
    return Array(sorted.prefix(keepTop))
}
