import Foundation

public struct RailJoinResult {
    public var left: [Point]
    public var right: [Point]
}

public func applyRailJoins(
    left: [Point],
    right: [Point],
    centers: [Point],
    segmentIndices: [Int]?,
    joinStyle: JoinStyle,
    cornerThresholdDegrees: Double = 35.0,
    roundSegments: Int = 8
) -> RailJoinResult {
    guard left.count == right.count, left.count == centers.count, left.count >= 3 else {
        return RailJoinResult(left: left, right: right)
    }

    let thresholdRadians = cornerThresholdDegrees * .pi / 180.0
    let corners = railCornerIndices(
        centers: centers,
        segmentIndices: segmentIndices,
        thresholdRadians: thresholdRadians
    )

    var joinedLeft: [Point] = []
    var joinedRight: [Point] = []
    joinedLeft.reserveCapacity(left.count)
    joinedRight.reserveCapacity(right.count)

    for i in 0..<left.count {
        if i == 0 || i == left.count - 1 || !corners.contains(i) {
            joinedLeft.append(left[i])
            joinedRight.append(right[i])
            continue
        }

        guard let dirIn = (centers[i] - centers[i - 1]).normalized(),
              let dirOut = (centers[i + 1] - centers[i]).normalized() else {
            joinedLeft.append(left[i])
            joinedRight.append(right[i])
            continue
        }

        let radius = max(1.0e-6, (left[i] - right[i]).length * 0.5)
        let leftJoin = railJoinPoints(
            center: centers[i],
            dirIn: dirIn,
            dirOut: dirOut,
            radius: radius,
            style: joinStyle,
            sign: 1.0,
            roundSegments: roundSegments
        )
        let rightJoin = railJoinPoints(
            center: centers[i],
            dirIn: dirIn,
            dirOut: dirOut,
            radius: radius,
            style: joinStyle,
            sign: -1.0,
            roundSegments: roundSegments
        )

        if leftJoin.isEmpty || rightJoin.isEmpty {
            joinedLeft.append(left[i])
            joinedRight.append(right[i])
        } else {
            joinedLeft.append(contentsOf: leftJoin)
            joinedRight.append(contentsOf: rightJoin)
        }
    }

    return RailJoinResult(left: joinedLeft, right: joinedRight)
}

private func railCornerIndices(
    centers: [Point],
    segmentIndices: [Int]?,
    thresholdRadians: Double
) -> Set<Int> {
    let count = centers.count
    guard count >= 3 else { return [] }
    var result: Set<Int> = []
    for i in 1..<(count - 1) {
        let prev = centers[i - 1]
        let curr = centers[i]
        let next = centers[i + 1]
        let v0 = (curr - prev).normalized()
        let v1 = (next - curr).normalized()
        if let v0, let v1 {
            let dot = max(-1.0, min(1.0, v0.dot(v1)))
            let angle = acos(dot)
            if angle > thresholdRadians {
                result.insert(i)
            }
        }
        if let segmentIndices,
           segmentIndices[i] != segmentIndices[i - 1] || segmentIndices[i] != segmentIndices[i + 1] {
            result.insert(i)
        }
    }
    return result
}

private func railJoinPoints(
    center: Point,
    dirIn: Point,
    dirOut: Point,
    radius: Double,
    style: JoinStyle,
    sign: Double,
    roundSegments: Int
) -> [Point] {
    let n0 = dirIn.leftNormal() * sign
    let n1 = dirOut.leftNormal() * sign
    switch style {
    case .bevel:
        return [center + n0 * radius, center + n1 * radius]
    case .round:
        return arcPoints(center: center, from: n0, to: n1, radius: radius, segments: roundSegments)
    case .miter(let limit):
        let miter = (n0 + n1).normalized()
        guard let miter else {
            return [center + n0 * radius, center + n1 * radius]
        }
        let denom = max(1.0e-6, miter.dot(n1))
        let length = radius / denom
        if length > limit * radius {
            return [center + n0 * radius, center + n1 * radius]
        }
        return [center + miter * length]
    }
}

private func arcPoints(center: Point, from n0: Point, to n1: Point, radius: Double, segments: Int) -> [Point] {
    let start = atan2(n0.y, n0.x)
    let end = atan2(n1.y, n1.x)
    let delta = AngleMath.shortestDelta(from: start, to: end)
    let steps = max(2, segments)
    var points: [Point] = []
    points.reserveCapacity(steps + 1)
    for i in 0...steps {
        let t = Double(i) / Double(steps)
        let angle = start + delta * t
        points.append(Point(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        ))
    }
    return points
}
