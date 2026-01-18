import XCTest
@testable import Domain
@testable import UseCases

final class RailChain2BumpMetricTests: XCTestCase {
    func testBumpMetricMatchesDetectorInWindow() throws {
        let samples = try loadGlyphSamples()
        XCTAssertFalse(samples.isEmpty)

        let runs = adaptRailsToRailRuns2(side: .right, samples: samples)
        let chain = buildRailChain2(side: .right, runs: runs)
        let window = windowRailChain2(chain, gt0: 0.85, gt1: 0.90)

        let detected = detectRailChainBump(window, side: .right)
        let metric = measureRailChainBumpMetric(window, side: .right)

        XCTAssertNotNil(detected)
        XCTAssertNotNil(metric)

        guard let detected, let metric else { return }
        XCTAssertEqual(metric.chainGT, detected.chainGT, accuracy: 1.0e-9)
        XCTAssertEqual(metric.curvatureMagnitude, detected.curvatureMagnitude, accuracy: 1.0e-9)

        let repeatMetric = measureRailChainBumpMetric(window, side: .right)
        XCTAssertEqual(metric.chainGT, repeatMetric?.chainGT ?? -1.0, accuracy: 1.0e-9)
        XCTAssertEqual(metric.curvatureMagnitude, repeatMetric?.curvatureMagnitude ?? -1.0, accuracy: 1.0e-9)
    }

    private func loadGlyphSamples() throws -> [PathDomain.Sample] {
        let glyphURL = try fixtureURL(pathComponents: ["Fixtures", "glyphs", "J.v0.json"])
        let data = try Data(contentsOf: glyphURL)
        let document = try GlyphDocument.load(from: data)

        let pathById = Dictionary(uniqueKeysWithValues: document.inputs.geometry.paths.map { ($0.id, $0) })
        var segments: [CubicBezier] = []

        if let stroke = document.inputs.geometry.strokes.first {
            for skeletonId in stroke.skeletons {
                guard let path = pathById[skeletonId] else { continue }
                for segment in path.segments {
                    if case .cubic(let cubic) = segment { segments.append(cubic) }
                }
            }
        } else {
            for path in document.inputs.geometry.paths {
                for segment in path.segments {
                    if case .cubic(let cubic) = segment { segments.append(cubic) }
                }
            }
        }

        XCTAssertFalse(segments.isEmpty)
        let domain = PathDomain(path: BezierPath(segments: segments), samplesPerSegment: 12)
        return domain.samples
    }

    private func fixtureURL(pathComponents: [String]) throws -> URL {
        let fileURL = URL(fileURLWithPath: #file)
        var dir = fileURL.deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = pathComponents.reduce(dir) { $0.appendingPathComponent($1) }
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir.deleteLastPathComponent()
        }
        throw NSError(domain: "RailChain2BumpMetricTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found."])
    }
}
