import Foundation

public struct RasterGrid {
    public let width: Int
    public let height: Int
    public var data: [UInt8]

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.width = width
        self.height = height
        self.data = Array(repeating: fill, count: width * height)
    }

    public func index(x: Int, y: Int) -> Int {
        y * width + x
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { data[index(x: x, y: y)] }
        set { data[index(x: x, y: y)] = newValue }
    }
}

public enum Rasterizer {
    public struct Result {
        public let grid: RasterGrid
        public let origin: Point
        public let pixelSize: Double
    }

    public static func rasterize(polygons: PolygonSet, epsilon: Double) -> Result {
        guard let bounds = polygonBounds(polygons), bounds.width.isFinite, bounds.height.isFinite else {
            return Result(grid: RasterGrid(width: 1, height: 1, fill: 0), origin: Point(x: 0, y: 0), pixelSize: max(epsilon, 1.0e-4))
        }
        let basePixelSize = max(epsilon, 1.0e-4)
        let pad = max(2.0 * epsilon, basePixelSize * 2.0)
        let padded = bounds.expanded(by: pad)
        let rawWidth = max(1, Int(ceil(padded.width / basePixelSize)))
        let rawHeight = max(1, Int(ceil(padded.height / basePixelSize)))
        let maxDim = 1024
        let width = clamp(rawWidth, min: 64, max: maxDim)
        let height = clamp(rawHeight, min: 64, max: maxDim)
        let pixelSizeX = padded.width / Double(width)
        let pixelSizeY = padded.height / Double(height)
        let pixelSize = max(basePixelSize, pixelSizeX, pixelSizeY)
        let origin = Point(x: padded.minX, y: padded.minY)

        var grid = RasterGrid(width: width, height: height, fill: 0)
        let rings = allRings(from: polygons)
        let segments = rings.reduce(0) { count, ring in
            max(0, closeRingIfNeeded(removeConsecutiveDuplicates(ring, tol: 0), tol: 0).count - 1) + count
        }
        print("rasterize bounds min=(\(format(bounds.minX)), \(format(bounds.minY))) max=(\(format(bounds.maxX)), \(format(bounds.maxY)))")
        print("rasterize pixelSize=\(format(pixelSize)) grid=\(width)x\(height) segments=\(segments)")

        var edgeBuckets: [[ActiveEdge]] = Array(repeating: [], count: height)
        for ring in rings {
            let points = closeRingIfNeeded(removeConsecutiveDuplicates(ring, tol: 0), tol: 0)
            guard points.count >= 2 else { continue }
            for i in 0..<(points.count - 1) {
                let p0 = points[i]
                let p1 = points[i + 1]
                if abs(p0.y - p1.y) <= 0 { continue }
                let yMin = min(p0.y, p1.y)
                let yMax = max(p0.y, p1.y)
                var rowMin = rowIndex(forY: yMin, originY: origin.y, pixelSize: pixelSize, roundUp: true)
                var rowMax = rowIndex(forY: yMax, originY: origin.y, pixelSize: pixelSize, roundUp: false) - 1
                if rowMax < rowMin { continue }
                if rowMax < 0 || rowMin >= height { continue }
                if rowMin < 0 { rowMin = 0 }
                if rowMax >= height { rowMax = height - 1 }
                if rowMax < rowMin { continue }
                let yStart = origin.y + (Double(rowMin) + 0.5) * pixelSize
                let invSlope = (p1.x - p0.x) / (p1.y - p0.y)
                let xStart = p0.x + (yStart - p0.y) * invSlope
                edgeBuckets[rowMin].append(ActiveEdge(x: xStart, invSlope: invSlope, maxRow: rowMax))
            }
        }

        var active: [ActiveEdge] = []
        active.reserveCapacity(64)
        for y in 0..<height {
            if !edgeBuckets[y].isEmpty {
                active.append(contentsOf: edgeBuckets[y])
            }
            active = active.filter { y <= $0.maxRow }
            if active.isEmpty {
                if y % 128 == 0 {
                    print("rasterize row \(y) active=0 intersections=0")
                }
                continue
            }
            active.sort { lhs, rhs in
                if lhs.x != rhs.x { return lhs.x < rhs.x }
                return lhs.invSlope < rhs.invSlope
            }
            let intersections = active.map { $0.x }
            if y % 128 == 0 {
                print("rasterize row \(y) active=\(active.count) intersections=\(intersections.count)")
            }
            var i = 0
            while i + 1 < intersections.count {
                let x0 = intersections[i]
                let x1 = intersections[i + 1]
                let minX = min(x0, x1)
                let maxX = max(x0, x1)
                let start = Int(ceil((minX - origin.x) / pixelSize - 0.5))
                let end = Int(floor((maxX - origin.x) / pixelSize - 0.5))
                if start <= end {
                    let clampedStart = max(0, start)
                    let clampedEnd = min(width - 1, end)
                    if clampedStart <= clampedEnd {
                        for x in clampedStart...clampedEnd {
                            grid[x, y] = 1
                        }
                    }
                }
                i += 2
            }
            for idx in 0..<active.count {
                active[idx].x += active[idx].invSlope * pixelSize
            }
        }

        let inkBefore = countInkPixels(grid)
        let closed = closeMask(grid)
        let inkAfter = countInkPixels(closed)
        print("rasterize closing inkPixels before=\(inkBefore) after=\(inkAfter)")

        return Result(grid: closed, origin: origin, pixelSize: pixelSize)
    }
}

private func allRings(from polygons: PolygonSet) -> [Ring] {
    var rings: [Ring] = []
    for polygon in polygons {
        rings.append(polygon.outer)
        rings.append(contentsOf: polygon.holes)
    }
    return rings
}

private struct Bounds {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }

    func expanded(by value: Double) -> Bounds {
        Bounds(
            minX: minX - value,
            minY: minY - value,
            maxX: maxX + value,
            maxY: maxY + value
        )
    }
}

private struct ActiveEdge {
    var x: Double
    let invSlope: Double
    let maxRow: Int
}

public func closeMask(_ grid: RasterGrid) -> RasterGrid {
    let dilated = dilate(grid)
    return erode(dilated)
}

private func polygonBounds(_ polygons: PolygonSet) -> Bounds? {
    var minX = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    var hasPoint = false
    for polygon in polygons {
        for point in polygon.outer {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            hasPoint = true
        }
        for hole in polygon.holes {
            for point in hole {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
                hasPoint = true
            }
        }
    }
    guard hasPoint else { return nil }
    return Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
}

private func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
    Swift.max(minValue, Swift.min(maxValue, value))
}

private func rowIndex(forY yWorld: Double, originY: Double, pixelSize: Double, roundUp: Bool) -> Int {
    let value = (yWorld - originY) / pixelSize - 0.5
    return roundUp ? Int(ceil(value)) : Int(floor(value))
}

private func format(_ value: Double) -> String {
    let factor = pow(10.0, 6.0)
    let rounded = (value * factor).rounded() / factor
    return String(format: "%.6f", rounded)
}

private func countInkPixels(_ grid: RasterGrid) -> Int {
    grid.data.reduce(0) { $0 + (Int($1) != 0 ? 1 : 0) }
}

private func dilate(_ grid: RasterGrid) -> RasterGrid {
    var result = RasterGrid(width: grid.width, height: grid.height, fill: 0)
    for y in 0..<grid.height {
        for x in 0..<grid.width {
            var filled = grid[x, y] != 0
            if !filled {
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let nx = x + dx
                        let ny = y + dy
                        if nx < 0 || ny < 0 || nx >= grid.width || ny >= grid.height { continue }
                        if grid[nx, ny] != 0 {
                            filled = true
                            break
                        }
                    }
                    if filled { break }
                }
            }
            result[x, y] = filled ? 1 : 0
        }
    }
    return result
}

private func erode(_ grid: RasterGrid) -> RasterGrid {
    var result = RasterGrid(width: grid.width, height: grid.height, fill: 0)
    for y in 0..<grid.height {
        for x in 0..<grid.width {
            if grid[x, y] == 0 {
                result[x, y] = 0
                continue
            }
            var keep = true
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = x + dx
                    let ny = y + dy
                    if nx < 0 || ny < 0 || nx >= grid.width || ny >= grid.height {
                        keep = false
                        break
                    }
                    if grid[nx, ny] == 0 {
                        keep = false
                        break
                    }
                }
                if !keep { break }
            }
            result[x, y] = keep ? 1 : 0
        }
    }
    return result
}
