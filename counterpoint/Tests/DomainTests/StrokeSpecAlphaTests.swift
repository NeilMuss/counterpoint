import XCTest
@testable import Domain

final class StrokeSpecAlphaTests: XCTestCase {
    func testDecodesAlphaKeyframes() throws {
        let json = """
        {
          "path": {
            "segments": [
              {
                "p0": {"x": 0, "y": 0},
                "p1": {"x": 10, "y": 0},
                "p2": {"x": 20, "y": 0},
                "p3": {"x": 30, "y": 0}
              }
            ]
          },
          "width": { "keyframes": [ { "t": 0.0, "value": 10 }, { "t": 1.0, "value": 10 } ] },
          "height": { "keyframes": [ { "t": 0.0, "value": 20 }, { "t": 1.0, "value": 20 } ] },
          "theta": { "keyframes": [ { "t": 0.0, "value": 0 }, { "t": 1.0, "value": 0 } ] },
          "alpha": { "keyframes": [ { "t": 0.0, "value": 0.0 }, { "t": 1.0, "value": 1.0 } ] },
          "angleMode": "absolute",
          "sampling": { "baseSpacing": 2.0, "flatnessTolerance": 0.5, "rotationThresholdDegrees": 5.0, "minimumSpacing": 0.0001, "maxSamples": 64 }
        }
        """
        let spec = try JSONDecoder().decode(StrokeSpec.self, from: Data(json.utf8))
        XCTAssertNotNil(spec.alpha)
        XCTAssertEqual(spec.alpha?.keyframes.count, 2)
    }
}
