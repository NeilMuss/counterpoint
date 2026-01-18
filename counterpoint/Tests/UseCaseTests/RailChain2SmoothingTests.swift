import XCTest
@testable import Domain
@testable import UseCases

final class RailChain2SmoothingTests: XCTestCase {
    func testSmoothingReducesBumpCurvatureInWindow() throws {
        let samples = try loadGlyphSamples()
        XCTAssertFalse(samples.isEmpty)

        let runs = adaptRailsToRailRuns2(side: .right, samples: samples)
        let chain = buildRailChain2(side: .right, runs: runs)
        let window = windowRailChain2(chain, gt0: 0.85, gt1: 0.90)

        let baseline = measureRailChainBumpMetric(window, side: .right)
        XCTAssertNotNil(baseline)

        let smoothed = smoothRailChainWindow(window, iterations: 2, lambda: 0.25)
        let after = measureRailChainBumpMetric(smoothed, side: .right)
        XCTAssertNotNil(after)

        guard let baseline, let after else { return }
        XCTAssertLessThan(after.curvatureMagnitude, baseline.curvatureMagnitude - 1.0e-12)

        let repeatSmoothed = smoothRailChainWindow(window, iterations: 2, lambda: 0.25)
        let repeatMetric = measureRailChainBumpMetric(repeatSmoothed, side: .right)
        XCTAssertEqual(after.curvatureMagnitude, repeatMetric?.curvatureMagnitude ?? -1.0, accuracy: 1.0e-12)

        let bound = max(5.0, windowBounds(window).diagonal * 0.02)
        XCTAssertLessThanOrEqual(maxDistanceMoved(original: window, smoothed: smoothed), bound + 1.0e-9)
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

    private func windowBounds(_ window: RailChain2Window) -> (minX: Double, minY: Double, maxX: Double, maxY: Double, diagonal: Double) {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for run in window.runs {
            for sample in run.samples {
                let p = sample.p
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
        }
        let dx = maxX - minX
        let dy = maxY - minY
        return (minX, minY, maxX, maxY, hypot(dx, dy))
    }

    private func maxDistanceMoved(original: RailChain2Window, smoothed: RailChain2Window) -> Double {
        let originalSamples = original.runs.flatMap { $0.samples }
        let smoothedSamples = smoothed.runs.flatMap { $0.samples }
        XCTAssertEqual(originalSamples.count, smoothedSamples.count)
        var maxDistance = 0.0
        for (a, b) in zip(originalSamples, smoothedSamples) {
            let delta = (b.p - a.p).length
            maxDistance = max(maxDistance, delta)
        }
        return maxDistance
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
        throw NSError(domain: "RailChain2SmoothingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found."])
    }
}
