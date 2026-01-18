import XCTest
@testable import Domain
@testable import UseCases

final class RailChain2BuilderTests: XCTestCase {
    func testSingleRailRunProducesRailChain2WithInkMetric() {
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

        let runs = adaptRailsToRailRuns2(side: .left, samples: samples)
        XCTAssertEqual(runs.count, 1)

        let chain = buildRailChain2(side: .left, runs: runs)
        XCTAssertEqual(chain.runs.count, 1)
        XCTAssertFalse(chain.edges.isEmpty)
        XCTAssertGreaterThan(chain.metricLength, 0.0)

        for edge in chain.edges {
            XCTAssertEqual(edge.kind, .ink)
            XCTAssertTrue(edge.contributesToMetric)
        }

        let chainSamples = chain.runs[0].samples
        XCTAssertFalse(chainSamples.isEmpty)

        for i in 0..<chainSamples.count {
            let sample = chainSamples[i]
            XCTAssertNotNil(sample.chainGT)
            XCTAssertGreaterThanOrEqual(sample.chainGT ?? -1.0, 0.0)
            XCTAssertLessThanOrEqual(sample.chainGT ?? 2.0, 1.0)
            if i > 0 {
                XCTAssertGreaterThanOrEqual(sample.chainGT ?? -1.0, chainSamples[i - 1].chainGT ?? -2.0)
            }
        }
        XCTAssertEqual(chainSamples.first?.chainGT ?? -1.0, 0.0, accuracy: 1.0e-6)
        XCTAssertEqual(chainSamples.last?.chainGT ?? -1.0, 1.0, accuracy: 1.0e-6)
    }

    func testRailChain2AddsNonMetricConnectorsBetweenRuns() {
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

        let chain = buildRailChain2(side: .left, runs: runs)

        let connectorCount = chain.edges.filter { $0.kind == .connector }.count
        let inkCount = chain.edges.filter { $0.kind == .ink }.count
        XCTAssertGreaterThan(inkCount, 0)
        XCTAssertEqual(connectorCount, runs.count - 1)

        for edge in chain.edges where edge.kind == .connector {
            XCTAssertFalse(edge.contributesToMetric)
        }

        let inkSum = chain.edges.filter { $0.kind == .ink }.reduce(0.0) { $0 + $1.length }
        XCTAssertEqual(chain.metricLength, inkSum, accuracy: 1.0e-9)

        let expected = computeChainGT(runs: runs)
        let expectedSamples = expected.flatMap { $0.samples }
        let actualSamples = chain.runs.flatMap { $0.samples }
        XCTAssertEqual(actualSamples.count, expectedSamples.count)
        for (actual, baseline) in zip(actualSamples, expectedSamples) {
            XCTAssertEqual(actual.chainGT ?? -1.0, baseline.chainGT ?? -2.0, accuracy: 1.0e-9)
        }
    }

    private func computeChainGT(runs: [RailRun2]) -> [RailRun2] {
        var edgesLength = 0.0
        for run in runs where run.samples.count > 1 {
            for i in 1..<run.samples.count {
                edgesLength += (run.samples[i].p - run.samples[i - 1].p).length
            }
        }

        let denom = edgesLength > 0.0 ? edgesLength : 1.0
        var running = 0.0
        var updatedRuns: [RailRun2] = []
        updatedRuns.reserveCapacity(runs.count)

        for run in runs {
            guard !run.samples.isEmpty else {
                updatedRuns.append(run)
                continue
            }
            var updatedSamples: [RailSample2] = []
            updatedSamples.reserveCapacity(run.samples.count)

            for i in 0..<run.samples.count {
                let sample = run.samples[i]
                let gt = min(1.0, max(0.0, running / denom))
                updatedSamples.append(
                    RailSample2(
                        p: sample.p,
                        n: sample.n,
                        lt: sample.lt,
                        sourceGT: sample.sourceGT,
                        chainGT: gt
                    )
                )
                if i + 1 < run.samples.count {
                    running += (run.samples[i + 1].p - sample.p).length
                }
            }

            updatedRuns.append(RailRun2(id: run.id, side: run.side, samples: updatedSamples, inkLength: run.inkLength, sortKey: run.sortKey))
        }

        if edgesLength > 0.0, let lastIndex = updatedRuns.indices.last {
            var run = updatedRuns[lastIndex]
            if !run.samples.isEmpty {
                var samples = run.samples
                let lastSample = samples[samples.count - 1]
                samples[samples.count - 1] = RailSample2(
                    p: lastSample.p,
                    n: lastSample.n,
                    lt: lastSample.lt,
                    sourceGT: lastSample.sourceGT,
                    chainGT: 1.0
                )
                run = RailRun2(id: run.id, side: run.side, samples: samples, inkLength: run.inkLength, sortKey: run.sortKey)
                updatedRuns[lastIndex] = run
            }
        }

        return updatedRuns
    }
}
