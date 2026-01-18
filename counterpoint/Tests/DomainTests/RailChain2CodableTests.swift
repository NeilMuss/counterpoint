import XCTest
@testable import Domain

final class RailChain2CodableTests: XCTestCase {
    func testRailChain2RoundTripCodable() throws {
        let sample = RailSample2(
            p: Point(x: 1.0, y: 2.0),
            n: Point(x: 0.0, y: 1.0),
            lt: 0.25,
            sourceGT: 0.3,
            chainGT: 0.4
        )
        let run = RailRun2(
            id: 7,
            side: .left,
            samples: [sample],
            inkLength: 12.5,
            sortKey: 0.1
        )
        let inkEdge = ChainEdge2(
            kind: .ink,
            a: Point(x: 1.0, y: 2.0),
            b: Point(x: 3.0, y: 4.0),
            fromRun: 7,
            toRun: 7,
            length: 2.5,
            contributesToMetric: true
        )
        let connectorEdge = ChainEdge2(
            kind: .connector,
            a: Point(x: 3.0, y: 4.0),
            b: Point(x: 5.0, y: 6.0),
            fromRun: 7,
            toRun: 8,
            length: 3.0,
            contributesToMetric: false
        )
        let chain = RailChain2(
            side: .left,
            runs: [run],
            edges: [inkEdge, connectorEdge],
            metricLength: 12.5
        )

        let data = try JSONEncoder().encode(chain)
        let decoded = try JSONDecoder().decode(RailChain2.self, from: data)
        XCTAssertEqual(decoded, chain)
    }
}
