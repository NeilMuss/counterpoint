import XCTest
import CP2Geometry
@testable import cp2_cli

final class CapStyleCornerParseTests: XCTestCase {
    func testCapStyleCornerBothRoundTrips() throws {
        let json = """
        {
          "startCap": { "type": "fillet", "radius": 12, "corner": "both" }
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(StrokeParams.self, from: data)
        guard let startCap = decoded.startCap else {
            XCTFail("Missing startCap")
            return
        }
        switch startCap {
        case .fillet(let radius, let corner):
            XCTAssertEqual(radius, 12, accuracy: 1.0e-6)
            XCTAssertEqual(corner, .both)
        default:
            XCTFail("Expected fillet cap")
        }

        let encoded = try JSONEncoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded, options: [])
        guard
            let dict = object as? [String: Any],
            let start = dict["startCap"] as? [String: Any],
            let corner = start["corner"] as? String
        else {
            XCTFail("Missing encoded corner")
            return
        }
        XCTAssertEqual(corner, "both")
    }
}
