import XCTest
@testable import cp2_cli
import CP2Geometry

final class CP2SpecTests: XCTestCase {
    func testDecodeJFixture() {
        let fixturePath = "Fixtures/glyphs/J.v0.json"
        guard let spec = loadSpec(path: fixturePath) else {
            XCTFail("Failed to load spec from \(fixturePath)")
            return
        }
        
        XCTAssertNotNil(spec.strokes)
        XCTAssertEqual(spec.strokes?.count, 1)
        
        guard let stroke = spec.strokes?.first else { return }
        XCTAssertEqual(stroke.id, "J-main")
        XCTAssertEqual(stroke.ink, "J_heartline")
        
        guard let params = stroke.params, let offset = params.offset else {
            XCTFail("Offset params missing")
            return
        }
        
        XCTAssertEqual(offset.keyframes.count, 3)
        XCTAssertEqual(offset.value(at: 0.0), 25.0, accuracy: 1e-6)
        XCTAssertEqual(offset.value(at: 0.9), 0.0, accuracy: 1e-6)
        XCTAssertEqual(offset.value(at: 1.0), 28.0, accuracy: 1e-6)
        
        // Also verify width and theta are present
        XCTAssertNotNil(params.width, "Width params should be present")
        XCTAssertNotNil(params.theta, "Theta params should be present")
    }
}
