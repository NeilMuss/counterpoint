import XCTest
@testable import Domain
@testable import UseCases

final class RailRun2AdapterTests: XCTestCase {
    func testExistingRailsCanBeAdaptedToSingleRailRun2() {
        let path = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 40, y: 80),
                p2: Point(x: 60, y: 80),
                p3: Point(x: 100, y: 0)
            )
        ])
        let domain = PathDomain(path: path, samplesPerSegment: 12)
        let samples = domain.samples
        XCTAssertFalse(samples.isEmpty)

        let leftRuns = adaptRailsToRailRuns2(side: .left, samples: samples)
        let rightRuns = adaptRailsToRailRuns2(side: .right, samples: samples)

        XCTAssertEqual(leftRuns.count, 1)
        XCTAssertEqual(rightRuns.count, 1)

        let left = leftRuns[0]
        let right = rightRuns[0]

        XCTAssertFalse(left.samples.isEmpty)
        XCTAssertFalse(right.samples.isEmpty)
        XCTAssertGreaterThan(left.inkLength, 0.0)
        XCTAssertGreaterThan(right.inkLength, 0.0)

        XCTAssertEqual(left.sortKey, samples[0].gt, accuracy: 1.0e-9)
        XCTAssertEqual(right.sortKey, samples[0].gt, accuracy: 1.0e-9)

        for (sample, railSample) in zip(samples, left.samples) {
            XCTAssertNotNil(railSample.sourceGT)
            XCTAssertEqual(railSample.sourceGT ?? -1.0, sample.gt, accuracy: 1.0e-9)
        }
        for (sample, railSample) in zip(samples, right.samples) {
            XCTAssertNotNil(railSample.sourceGT)
            XCTAssertEqual(railSample.sourceGT ?? -1.0, sample.gt, accuracy: 1.0e-9)
        }
    }

    func testRailsWithStitchBreakProduceMultipleRailRuns2() {
        let path = BezierPath(segments: [
            CubicBezier(
                p0: Point(x: 0, y: 0),
                p1: Point(x: 33, y: 0),
                p2: Point(x: 66, y: 0),
                p3: Point(x: 100, y: 0)
            ),
            CubicBezier(
                p0: Point(x: 1000, y: 0),
                p1: Point(x: 1033, y: 0),
                p2: Point(x: 1066, y: 0),
                p3: Point(x: 1100, y: 0)
            )
        ])
        let domain = PathDomain(path: path, samplesPerSegment: 8)
        let samples = domain.samples
        XCTAssertFalse(samples.isEmpty)

        let runs = adaptRailsToRailRuns2(side: .left, samples: samples)
        XCTAssertGreaterThanOrEqual(runs.count, 2)
        XCTAssertTrue(runs.allSatisfy { !$0.samples.isEmpty })

        let combinedSamples = runs.flatMap { $0.samples }
        XCTAssertEqual(combinedSamples.count, samples.count)

        for (sample, railSample) in zip(samples, combinedSamples) {
            XCTAssertEqual(railSample.p.x, sample.point.x, accuracy: 1.0e-9)
            XCTAssertEqual(railSample.p.y, sample.point.y, accuracy: 1.0e-9)
        }

        var lastKey = -Double.greatestFiniteMagnitude
        for run in runs {
            XCTAssertGreaterThan(run.sortKey, lastKey)
            lastKey = run.sortKey
        }
    }
}
