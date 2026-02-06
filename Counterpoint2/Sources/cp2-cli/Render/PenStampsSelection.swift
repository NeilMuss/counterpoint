import Foundation
import CP2Skeleton

func selectPenStampTargetIndices(start: Int, end: Int, step: Int) -> [Int] {
    let strideValue = max(1, step)
    let lo = min(start, end)
    let hi = max(start, end)
    guard lo <= hi else { return [] }
    var values: [Int] = []
    values.reserveCapacity(max(1, (hi - lo) / strideValue + 1))
    var current = lo
    while current <= hi {
        values.append(current)
        current += strideValue
    }
    return values
}

func selectPenStampTargetGTs(start: Double, end: Double, step: Double) -> [Double] {
    let strideValue = max(1.0e-12, step)
    let lo = min(start, end)
    let hi = max(start, end)
    guard lo <= hi else { return [] }
    var values: [Double] = []
    var current = lo
    let eps = 1.0e-9
    while current <= hi + eps {
        values.append(current)
        current += strideValue
    }
    return values
}

func selectPenStampsBySampleRange(
    stamps: [PenStampSample],
    start: Int,
    end: Int,
    step: Int
) -> [PenStampSample] {
    let targets = Set(selectPenStampTargetIndices(start: start, end: end, step: step))
    guard !targets.isEmpty else { return [] }
    return stamps.filter { targets.contains($0.index) }
}

func selectPenStampsByGTRange(
    stamps: [PenStampSample],
    start: Double,
    end: Double,
    step: Double
) -> [PenStampSample] {
    let targets = selectPenStampTargetGTs(start: start, end: end, step: step)
    guard !targets.isEmpty, !stamps.isEmpty else { return [] }
    var selected: [PenStampSample] = []
    selected.reserveCapacity(targets.count)
    var usedIndices: Set<Int> = []
    for target in targets {
        var bestIndex: Int? = nil
        var bestDist = Double.greatestFiniteMagnitude
        for stamp in stamps {
            let dist = abs(stamp.gt - target)
            if dist < bestDist {
                bestDist = dist
                bestIndex = stamp.index
            } else if abs(dist - bestDist) <= 1.0e-12 {
                if let currentBest = bestIndex, stamp.index < currentBest {
                    bestIndex = stamp.index
                }
            }
        }
        if let bestIndex, !usedIndices.contains(bestIndex) {
            if let match = stamps.first(where: { $0.index == bestIndex }) {
                selected.append(match)
                usedIndices.insert(bestIndex)
            }
        }
    }
    return selected
}

func selectPenStamps(stamps: [PenStampSample], options: CLIOptions) -> [PenStampSample] {
    if let start = options.debugPenStampsSampleStart, let end = options.debugPenStampsSampleEnd {
        return selectPenStampsBySampleRange(
            stamps: stamps,
            start: start,
            end: end,
            step: options.debugPenStampsSampleStep
        )
    }
    if let start = options.debugPenStampsGTStart, let end = options.debugPenStampsGTEnd {
        return selectPenStampsByGTRange(
            stamps: stamps,
            start: start,
            end: end,
            step: options.debugPenStampsGTStep
        )
    }
    guard !stamps.isEmpty else { return [] }
    let start = stamps.first?.index ?? 0
    let end = stamps.last?.index ?? max(0, stamps.count - 1)
    return selectPenStampsBySampleRange(
        stamps: stamps,
        start: start,
        end: end,
        step: options.debugPenStampsSampleStep
    )
}
