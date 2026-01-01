import XCTest
import Foundation
import Domain
@testable import CounterpointCLI

final class GlobalAngleOverlayTests: XCTestCase {
    func testEnvelopeRailCountsMatchSamples() throws {
        let specData = try loadFixture(named: "global-angle-scurve")
        let spec = try JSONDecoder().decode(StrokeSpec.self, from: specData)

        let options = CLIOptions(
            inputPath: nil,
            exampleName: "global-angle-scurve",
            svgOutputPath: nil,
            svgSize: nil,
            padding: 10.0,
            quiet: true,
            useBridges: true,
            debugSamples: true,
            quality: "preview",
            showEnvelope: nil,
            showEnvelopeUnion: false,
            showRays: true,
            counterpointSize: nil,
            angleModeOverride: nil,
            envelopeTolerance: nil,
            flattenTolerance: nil,
            maxSamples: nil
        )

        let overlay = makeDebugOverlay(spec: spec, options: options)
        XCTAssertEqual(overlay.envelopeLeft.count, overlay.samplePoints.count)
        XCTAssertEqual(overlay.envelopeRight.count, overlay.samplePoints.count)
        XCTAssertEqual(overlay.envelopeOutline.count, overlay.samplePoints.count * 2 + 1)
        XCTAssertEqual(overlay.envelopeOutline.first, overlay.envelopeOutline.last)
        XCTAssertTrue(bounds(of: overlay.envelopeOutline).width > bounds(of: overlay.samplePoints).width)
    }

    func testEnvelopeDeterminism() throws {
        let specData = try loadFixture(named: "global-angle-scurve")
        let spec = try JSONDecoder().decode(StrokeSpec.self, from: specData)

        let options = CLIOptions(
            inputPath: nil,
            exampleName: "global-angle-scurve",
            svgOutputPath: nil,
            svgSize: nil,
            padding: 10.0,
            quiet: true,
            useBridges: true,
            debugSamples: true,
            quality: "preview",
            showEnvelope: true,
            showEnvelopeUnion: false,
            showRays: false,
            counterpointSize: nil,
            angleModeOverride: nil,
            envelopeTolerance: nil,
            flattenTolerance: nil,
            maxSamples: nil
        )

        let overlayA = makeDebugOverlay(spec: spec, options: options)
        let overlayB = makeDebugOverlay(spec: spec, options: options)
        XCTAssertEqual(overlayA.envelopeOutline.count, overlayB.envelopeOutline.count)
        for i in 0..<overlayA.envelopeOutline.count {
            XCTAssertEqual(overlayA.envelopeOutline[i].x, overlayB.envelopeOutline[i].x, accuracy: 1.0e-9)
            XCTAssertEqual(overlayA.envelopeOutline[i].y, overlayB.envelopeOutline[i].y, accuracy: 1.0e-9)
        }
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
        throw NSError(domain: "GlobalAngleOverlayTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found."])
    }

    private func bounds(of points: [Point]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
