import Foundation

public enum FinalOutlineConsolidationMode {
    case unionAuto
    case unionOff
    case trace
}

public enum OutlineTracer {
    public static func traceSilhouette(_ input: PolygonSet, epsilon: Double, closingPasses: Int = 1) -> PolygonSet {
        let result = Rasterizer.rasterize(polygons: input, epsilon: epsilon, closingPasses: closingPasses)
        let contours = ContourTracer.trace(grid: result.grid, origin: result.origin, pixelSize: result.pixelSize)
        var polygons = ContourTracer.assemblePolygons(from: contours)
        let preFilterCount = polygons.count
        let minArea = result.pixelSize * result.pixelSize * 64.0
        let relativeKeepRatio = 0.01
        let filterResult = filterSmallPolygons(polygons, minArea: minArea, keepTop: 20, relativeKeepRatio: relativeKeepRatio)
        polygons = filterResult.polygons
        let mergeDistanceMultiplier = (closingPasses >= 2) ? 10.0 : 3.0
        let mergeResult = mergeNearArtifacts(polygons, pixelSize: result.pixelSize, mergeDistanceMultiplier: mergeDistanceMultiplier)
        polygons = mergeResult.polygons
        if mergeResult.didRun {
            let detail = mergeResult.droppedDetails.isEmpty ? "" : " details=[" + mergeResult.droppedDetails.joined(separator: ", ") + "]"
            let candidateDetail = mergeResult.candidateArea == nil
                ? ""
                : " candidateArea=\(String(format: "%.3f", mergeResult.candidateArea ?? 0)) candidateDist=\(String(format: "%.3f", mergeResult.candidateDistance ?? 0)) candidateYOverlap=\(String(format: "%.3f", mergeResult.candidateYOverlap ?? 0)) minDist=\(String(format: "%.3f", mergeResult.minimumDistance ?? 0))"
            print("mergeNear: threshold=\(String(format: "%.6f", mergeResult.threshold)) mainArea=\(String(format: "%.6f", mergeResult.mainArea)) dropped=\(mergeResult.droppedIndices.count) remaining=\(polygons.count)\(detail)")
            if !candidateDetail.isEmpty {
                print("mergeNear candidate:\(candidateDetail)")
            }
            if let mainBBox = mergeResult.mainBBox {
                print("mergeNear mainBBox min=(\(String(format: "%.3f", mainBBox.min.x)), \(String(format: "%.3f", mainBBox.min.y))) max=(\(String(format: "%.3f", mainBBox.max.x)), \(String(format: "%.3f", mainBBox.max.y))) pixelSize=\(String(format: "%.6f", result.pixelSize)) threshold=\(String(format: "%.6f", mergeResult.threshold))")
            }
            if let candidateBBox = mergeResult.candidateBBox,
               let dx = mergeResult.candidateDx,
               let dy = mergeResult.candidateDy,
               let dist = mergeResult.candidateDistance {
                let centroid = mergeResult.candidateCentroid
                let centroidText = centroid == nil ? "" : " centroid=(\(String(format: "%.3f", centroid!.x)), \(String(format: "%.3f", centroid!.y)))"
                print("mergeNear candidateBBox min=(\(String(format: "%.3f", candidateBBox.min.x)), \(String(format: "%.3f", candidateBBox.min.y))) max=(\(String(format: "%.3f", candidateBBox.max.x)), \(String(format: "%.3f", candidateBBox.max.y))) dx=\(String(format: "%.3f", dx)) dy=\(String(format: "%.3f", dy)) dist=\(String(format: "%.3f", dist))\(centroidText)")
            }
        }
        print("trace: eps=\(String(format: "%.6f", epsilon)) closingPasses=\(closingPasses) pixelSize=\(String(format: "%.6f", result.pixelSize)) grid=\(result.grid.width)x\(result.grid.height) inputPolys=\(input.count) rings=\(contours.count) polys pre=\(preFilterCount) post=\(polygons.count) minArea=\(String(format: "%.6f", minArea)) largestArea=\(String(format: "%.6f", filterResult.largestArea)) secondArea=\(String(format: "%.6f", filterResult.secondArea)) secondRatio=\(String(format: "%.6f", filterResult.secondRatio)) relativeKeepRatio=\(String(format: "%.6f", relativeKeepRatio)) keptByRelative=\(filterResult.keptByRelative)")
        return polygons
    }
}

public struct OutlineFilterResult {
    public let polygons: PolygonSet
    public let largestArea: Double
    public let secondArea: Double
    public let secondRatio: Double
    public let keptByRelative: Int
}

public func filterSmallPolygons(_ polygons: PolygonSet, minArea: Double, keepTop: Int, relativeKeepRatio: Double) -> OutlineFilterResult {
    let items = polygons.map { polygon in
        (polygon: polygon, area: abs(signedArea(polygon.outer)))
    }.sorted { $0.area > $1.area }
    guard let first = items.first else {
        return OutlineFilterResult(polygons: [], largestArea: 0, secondArea: 0, secondRatio: 0, keptByRelative: 0)
    }
    let largestArea = first.area
    let secondArea = items.dropFirst().first?.area ?? 0.0
    let secondRatio = largestArea > 0 ? (secondArea / largestArea) : 0.0
    var kept: [(polygon: Polygon, area: Double)] = []
    kept.reserveCapacity(items.count)
    kept.append(first)
    let threshold = largestArea * relativeKeepRatio
    for item in items.dropFirst() {
        if item.area >= minArea && item.area >= threshold {
            kept.append(item)
        }
    }
    let keptByRelative = max(0, kept.count - 1)
    let trimmed = kept.prefix(max(1, keepTop)).map { $0.polygon }
    return OutlineFilterResult(
        polygons: trimmed,
        largestArea: largestArea,
        secondArea: secondArea,
        secondRatio: secondRatio,
        keptByRelative: keptByRelative
    )
}

struct MergeNearResult {
    let polygons: PolygonSet
    let droppedIndices: [Int]
    let droppedDetails: [String]
    let threshold: Double
    let mainArea: Double
    let mainBBox: (min: Point, max: Point)?
    let candidateBBox: (min: Point, max: Point)?
    let candidateArea: Double?
    let candidateDistance: Double?
    let candidateDx: Double?
    let candidateDy: Double?
    let candidateYOverlap: Double?
    let candidateCentroid: Point?
    let minimumDistance: Double?
    let didRun: Bool
}

func mergeNearArtifacts(_ polygons: PolygonSet, pixelSize: Double, mergeDistanceMultiplier: Double) -> MergeNearResult {
    guard polygons.count > 1 else {
        return MergeNearResult(
            polygons: polygons,
            droppedIndices: [],
            droppedDetails: [],
            threshold: 0,
            mainArea: 0,
            mainBBox: nil,
            candidateBBox: nil,
            candidateArea: nil,
            candidateDistance: nil,
            candidateDx: nil,
            candidateDy: nil,
            candidateYOverlap: nil,
            candidateCentroid: nil,
            minimumDistance: nil,
            didRun: false
        )
    }
    let mergeDistance = pixelSize * mergeDistanceMultiplier
    let mainAreaKeepRatio = 0.25
    var mainIndex = 0
    var mainArea = abs(signedArea(polygons[0].outer))
    for index in polygons.indices.dropFirst() {
        let area = abs(signedArea(polygons[index].outer))
        if area > mainArea {
            mainArea = area
            mainIndex = index
        }
    }
    guard let mainBox = boundingBox(polygons[mainIndex].outer) else {
        return MergeNearResult(
            polygons: polygons,
            droppedIndices: [],
            droppedDetails: [],
            threshold: mergeDistance,
            mainArea: mainArea,
            mainBBox: nil,
            candidateBBox: nil,
            candidateArea: nil,
            candidateDistance: nil,
            candidateDx: nil,
            candidateDy: nil,
            candidateYOverlap: nil,
            candidateCentroid: nil,
            minimumDistance: nil,
            didRun: true
        )
    }
    var kept: PolygonSet = []
    kept.reserveCapacity(polygons.count)
    var droppedIndices: [Int] = []
    var droppedDetails: [String] = []
    var candidateArea: Double?
    var candidateDistance: Double?
    var candidateYOverlap: Double?
    var candidateDx: Double?
    var candidateDy: Double?
    var candidateBBox: (min: Point, max: Point)?
    var candidateCentroid: Point?
    var minimumDistance: Double?
    var candidates: [(index: Int, area: Double, distance: Double, yOverlap: Double)] = []
    for (index, polygon) in polygons.enumerated() {
        if index == mainIndex {
            kept.append(polygon)
            continue
        }
        guard let box = boundingBox(polygon.outer) else {
            kept.append(polygon)
            continue
        }
        let area = abs(signedArea(polygon.outer))
        let components = bboxDistanceComponents(mainBox, box)
        let distance = components.dist
        let yOverlap = overlapAmount(minA: mainBox.min.y, maxA: mainBox.max.y, minB: box.min.y, maxB: box.max.y)
        candidates.append((index: index, area: area, distance: distance, yOverlap: yOverlap))
        if distance <= mergeDistance && yOverlap > 0 && area < (mainArea * mainAreaKeepRatio) {
            droppedIndices.append(index)
            droppedDetails.append("i=\(index) area=\(String(format: "%.3f", area)) dist=\(String(format: "%.3f", distance))")
            continue
        }
        kept.append(polygon)
    }
    if !candidates.isEmpty {
        if let best = candidates.max(by: { $0.area < $1.area }) {
            candidateArea = best.area
            candidateDistance = best.distance
            candidateYOverlap = best.yOverlap
            if let box = boundingBox(polygons[best.index].outer) {
                let components = bboxDistanceComponents(mainBox, box)
                candidateDx = components.dx
                candidateDy = components.dy
                candidateBBox = box
            }
            candidateCentroid = centroid(polygons[best.index].outer)
        }
        minimumDistance = candidates.map { $0.distance }.min()
    }
    return MergeNearResult(
        polygons: kept,
        droppedIndices: droppedIndices,
        droppedDetails: droppedDetails,
        threshold: mergeDistance,
        mainArea: mainArea,
        mainBBox: mainBox,
        candidateBBox: candidateBBox,
        candidateArea: candidateArea,
        candidateDistance: candidateDistance,
        candidateDx: candidateDx,
        candidateDy: candidateDy,
        candidateYOverlap: candidateYOverlap,
        candidateCentroid: candidateCentroid,
        minimumDistance: minimumDistance,
        didRun: true
    )
}

func bboxDistanceComponents(_ a: (min: Point, max: Point), _ b: (min: Point, max: Point)) -> (dx: Double, dy: Double, dist: Double) {
    let dx: Double
    if a.max.x < b.min.x {
        dx = b.min.x - a.max.x
    } else if b.max.x < a.min.x {
        dx = a.min.x - b.max.x
    } else {
        dx = 0
    }
    let dy: Double
    if a.max.y < b.min.y {
        dy = b.min.y - a.max.y
    } else if b.max.y < a.min.y {
        dy = a.min.y - b.max.y
    } else {
        dy = 0
    }
    let dist = (dx * dx + dy * dy).squareRoot()
    return (dx: dx, dy: dy, dist: dist)
}

private func bboxDistance(_ a: (min: Point, max: Point), _ b: (min: Point, max: Point)) -> Double {
    return bboxDistanceComponents(a, b).dist
}

private func centroid(_ ring: Ring) -> Point? {
    guard !ring.isEmpty else { return nil }
    var sumX = 0.0
    var sumY = 0.0
    for point in ring {
        sumX += point.x
        sumY += point.y
    }
    let count = Double(ring.count)
    return Point(x: sumX / count, y: sumY / count)
}

private func overlapAmount(minA: Double, maxA: Double, minB: Double, maxB: Double) -> Double {
    let lower = max(minA, minB)
    let upper = min(maxA, maxB)
    return max(0.0, upper - lower)
}
