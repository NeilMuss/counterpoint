import XCTest
@testable import Domain

final class RasterizerComponentsTests: XCTestCase {
    func testCountComponentsBridgeConnects() {
        var grid = RasterGrid(width: 5, height: 4, fill: 0)
        setSquare(&grid, x: 0, y: 1)
        setSquare(&grid, x: 3, y: 1)
        grid[2, 1] = 1
        let count = countComponents(grid)
        XCTAssertEqual(count, 1)
    }
}

private func setSquare(_ grid: inout RasterGrid, x: Int, y: Int) {
    grid[x, y] = 1
    grid[x + 1, y] = 1
    grid[x, y + 1] = 1
    grid[x + 1, y + 1] = 1
}
