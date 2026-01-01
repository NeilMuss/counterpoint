import XCTest
@testable import Domain
@testable import UseCases
@testable import Adapters

final class StrokeOutlineBridgeTests: XCTestCase {
    func testStrokeOutlineWithBridgesHasComparableBounds() throws {
        let specData = try loadFixture(named: "s-curve")
        let spec = try JSONDecoder().decode(StrokeSpec.self, from: specData)
        try StrokeSpecValidator().validate(spec)

        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: IOverlayPolygonUnionAdapter()
        )

        let outlineWithBridges = try useCase.generateOutline(for: spec, includeBridges: true)
        let outlineWithoutBridges = try useCase.generateOutline(for: spec, includeBridges: false)

        XCTAssertLessThanOrEqual(outlineWithBridges.count, outlineWithoutBridges.count)

        let boundsA = bounds(of: outlineWithBridges)
        let boundsB = bounds(of: outlineWithoutBridges)
        let epsilon = 2.0

        XCTAssertEqual(boundsA.minX, boundsB.minX, accuracy: epsilon)
        XCTAssertEqual(boundsA.maxX, boundsB.maxX, accuracy: epsilon)
        XCTAssertEqual(boundsA.minY, boundsB.minY, accuracy: epsilon)
        XCTAssertEqual(boundsA.maxY, boundsB.maxY, accuracy: epsilon)
    }

    func testDeterminismForOutlineGeneration() throws {
        let specData = try loadFixture(named: "s-curve")
        let spec = try JSONDecoder().decode(StrokeSpec.self, from: specData)
        try StrokeSpecValidator().validate(spec)

        let useCase = GenerateStrokeOutlineUseCase(
            sampler: DefaultPathSampler(),
            evaluator: DefaultParamEvaluator(),
            unioner: PassthroughPolygonUnioner()
        )

        let outlineA = try useCase.generateOutline(for: spec, includeBridges: true)
        let outlineB = try useCase.generateOutline(for: spec, includeBridges: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let dataA = try encoder.encode(outlineA)
        let dataB = try encoder.encode(outlineB)

        XCTAssertEqual(String(data: dataA, encoding: .utf8), String(data: dataB, encoding: .utf8))
    }

    private func loadFixture(named name: String) throws -> Data {
        let fileURL = URL(fileURLWithPath: #file)
        var dir = fileURL.deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("Fixtures/specs/\(name).json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try Data(contentsOf: candidate)
            }
            dir.deleteLastPathComponent()
        }
        throw NSError(domain: "StrokeOutlineBridgeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found."])
    }

    private func bounds(of polygons: PolygonSet) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for polygon in polygons {
            for point in polygon.outer {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            for hole in polygon.holes {
                for point in hole {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
        }

        return (minX, maxX, minY, maxY)
    }
}
