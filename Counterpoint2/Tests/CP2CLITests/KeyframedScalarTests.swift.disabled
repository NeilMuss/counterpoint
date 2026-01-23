import XCTest
@testable import CP2Geometry

final class KeyframedScalarTests: XCTestCase {
    func testLinearInterpolation() {
        let scalar = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 100.0),
            Keyframe(t: 1.0, value: 200.0)
        ])
        
        XCTAssertEqual(scalar.value(at: 0.0), 100.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 0.5), 150.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 1.0), 200.0, accuracy: 1e-6)
    }
    
    func testClamping() {
        let scalar = KeyframedScalar(keyframes: [
            Keyframe(t: 0.2, value: 10.0),
            Keyframe(t: 0.8, value: 50.0)
        ])
        
        XCTAssertEqual(scalar.value(at: 0.0), 10.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 1.0), 50.0, accuracy: 1e-6)
    }
    
    func testMultipleKeyframes() {
        let scalar = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 0.0),
            Keyframe(t: 0.5, value: 100.0),
            Keyframe(t: 1.0, value: 50.0)
        ])
        
        XCTAssertEqual(scalar.value(at: 0.25), 50.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 0.75), 75.0, accuracy: 1e-6)
    }
    
    func testEmptyKeyframes() {
        let scalar = KeyframedScalar(keyframes: [])
        XCTAssertEqual(scalar.value(at: 0.5), 0.0)
    }
    
    func testSingleKeyframe() {
        let scalar = KeyframedScalar(keyframes: [Keyframe(t: 0.5, value: 42.0)])
        XCTAssertEqual(scalar.value(at: 0.0), 42.0)
        XCTAssertEqual(scalar.value(at: 1.0), 42.0)
    }
    
    func testTwoKeyframeRamp() {
        // Specific test case requested: (t=0, value=10) to (t=1, value=30)
        let scalar = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 10.0),
            Keyframe(t: 1.0, value: 30.0)
        ])
        
        XCTAssertEqual(scalar.value(at: 0.0), 10.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 0.5), 20.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 1.0), 30.0, accuracy: 1e-6)
    }
    
    func testNegativeClamping() {
        // Test clamping outside the range
        let scalar = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 10.0),
            Keyframe(t: 1.0, value: 30.0)
        ])
        
        XCTAssertEqual(scalar.value(at: -0.1), 10.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 1.1), 30.0, accuracy: 1e-6)
    }
    
    func testUnsortedKeyframes() {
        // Test that unsorted keyframes are handled correctly (sorted internally)
        let scalar = KeyframedScalar(keyframes: [
            Keyframe(t: 1.0, value: 30.0),
            Keyframe(t: 0.0, value: 10.0),
            Keyframe(t: 0.5, value: 20.0)
        ])
        
        XCTAssertEqual(scalar.value(at: 0.0), 10.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 0.5), 20.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 1.0), 30.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 0.25), 15.0, accuracy: 1e-6)
        XCTAssertEqual(scalar.value(at: 0.75), 25.0, accuracy: 1e-6)
    }
}
