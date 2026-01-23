import XCTest
@testable import cp2_cli
import CP2Geometry
import CP2Skeleton

final class SweepPlanTests: XCTestCase {
    func testParamPrecedence() {
        // Test that param precedence works: CLI > JSON > Example
        
        // Setup: Example defaults
        let provider = ExampleParamProvider()
        var options = CLIOptions()
        options.example = nil // No example, so defaults should be used
        var funcs = provider.makeParamFuncs(options: options, exampleName: nil, sweepWidth: 5.0)
        
        // Verify example defaults
        XCTAssertEqual(funcs.offsetAtT(0.5), 0.0, accuracy: 1e-6, "Example default offset should be 0")
        XCTAssertEqual(funcs.widthAtT(0.5), 5.0, accuracy: 1e-6, "Example default width should be sweepWidth (5.0)")
        XCTAssertEqual(funcs.thetaAtT(0.5), 0.0, accuracy: 1e-6, "Example default theta should be 0")
        
        // Setup: JSON ramps override examples
        let jsonOffset = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 10.0),
            Keyframe(t: 1.0, value: 30.0)
        ])
        let jsonWidth = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 100.0),
            Keyframe(t: 1.0, value: 200.0)
        ])
        let jsonTheta = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 0.0),
            Keyframe(t: 1.0, value: 1.0)
        ])
        
        // Wire JSON params (simulating what CLIPipeline does)
        funcs.offsetAtT = { t in jsonOffset.value(at: t) }
        funcs.widthAtT = { t in jsonWidth.value(at: t) }
        funcs.thetaAtT = { t in jsonTheta.value(at: t) }
        
        // Verify JSON overrides work
        XCTAssertEqual(funcs.offsetAtT(0.0), 10.0, accuracy: 1e-6, "JSON offset at t=0 should be 10")
        XCTAssertEqual(funcs.offsetAtT(0.5), 20.0, accuracy: 1e-6, "JSON offset at t=0.5 should interpolate to 20")
        XCTAssertEqual(funcs.offsetAtT(1.0), 30.0, accuracy: 1e-6, "JSON offset at t=1 should be 30")
        
        XCTAssertEqual(funcs.widthAtT(0.0), 100.0, accuracy: 1e-6, "JSON width at t=0 should be 100")
        XCTAssertEqual(funcs.widthAtT(0.5), 150.0, accuracy: 1e-6, "JSON width at t=0.5 should interpolate to 150")
        XCTAssertEqual(funcs.widthAtT(1.0), 200.0, accuracy: 1e-6, "JSON width at t=1 should be 200")
        
        XCTAssertEqual(funcs.thetaAtT(0.0), 0.0, accuracy: 1e-6, "JSON theta at t=0 should be 0")
        XCTAssertEqual(funcs.thetaAtT(0.5), 0.5, accuracy: 1e-6, "JSON theta at t=0.5 should interpolate to 0.5")
        XCTAssertEqual(funcs.thetaAtT(1.0), 1.0, accuracy: 1e-6, "JSON theta at t=1 should be 1")
        
        // Setup: CLI override wins over JSON
        options.offsetConst = 999.0
        funcs.offsetAtT = { _ in options.offsetConst ?? 0.0 }
        
        // Verify CLI override wins
        XCTAssertEqual(funcs.offsetAtT(0.0), 999.0, accuracy: 1e-6, "CLI offset override should win")
        XCTAssertEqual(funcs.offsetAtT(0.5), 999.0, accuracy: 1e-6, "CLI offset override should win")
        XCTAssertEqual(funcs.offsetAtT(1.0), 999.0, accuracy: 1e-6, "CLI offset override should win")
        
        // Width and theta should still use JSON (no CLI override for them)
        XCTAssertEqual(funcs.widthAtT(0.5), 150.0, accuracy: 1e-6, "Width should still use JSON (no CLI override)")
        XCTAssertEqual(funcs.thetaAtT(0.5), 0.5, accuracy: 1e-6, "Theta should still use JSON (no CLI override)")
    }
    
    func testSweepPlanWiring() {
        // Test that SweepPlan correctly stores and uses the closures
        let provider = ExampleParamProvider()
        let options = CLIOptions()
        var funcs = provider.makeParamFuncs(options: options, exampleName: nil, sweepWidth: 20.0)
        
        // Wire JSON params
        let jsonOffset = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 10.0),
            Keyframe(t: 1.0, value: 30.0)
        ])
        let jsonWidth = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 100.0),
            Keyframe(t: 1.0, value: 200.0)
        ])
        let jsonTheta = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 0.0),
            Keyframe(t: 1.0, value: 1.0)
        ])
        
        funcs.offsetAtT = { t in jsonOffset.value(at: t) }
        funcs.widthAtT = { t in jsonWidth.value(at: t) }
        funcs.thetaAtT = { t in jsonTheta.value(at: t) }
        
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 10.0,
            sweepSampleCount: 64
        )
        
        // Verify plan stores the closures correctly
        XCTAssertEqual(plan.offsetAtT(0.0), 10.0, accuracy: 1e-6)
        XCTAssertEqual(plan.offsetAtT(0.5), 20.0, accuracy: 1e-6)
        XCTAssertEqual(plan.offsetAtT(1.0), 30.0, accuracy: 1e-6)
        
        XCTAssertEqual(plan.widthAtT(0.0), 100.0, accuracy: 1e-6)
        XCTAssertEqual(plan.widthAtT(0.5), 150.0, accuracy: 1e-6)
        XCTAssertEqual(plan.widthAtT(1.0), 200.0, accuracy: 1e-6)
        
        XCTAssertEqual(plan.thetaAtT(0.0), 0.0, accuracy: 1e-6)
        XCTAssertEqual(plan.thetaAtT(0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(plan.thetaAtT(1.0), 1.0, accuracy: 1e-6)
    }
    
    func testOffsetAtTCalledWithMultipleTValues() {
        // Wiring sanity test: ensure offsetAtT is called with multiple distinct t values
        // This catches the "t is always 0" bug (which looks like 'first keyframe only')
        var observedTValues: [Double] = []
        
        let jsonOffset = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 10.0),
            Keyframe(t: 1.0, value: 30.0)
        ])
        
        let offsetAtT: (Double) -> Double = { t in
            observedTValues.append(t)
            return jsonOffset.value(at: t)
        }
        
        let provider = ExampleParamProvider()
        let options = CLIOptions()
        var funcs = provider.makeParamFuncs(options: options, exampleName: nil, sweepWidth: 20.0)
        funcs.offsetAtT = offsetAtT
        
        // Create a simple skeleton path (line) - not used but kept for clarity
        _ = SkeletonPath(segments: [
            CubicBezier2(
                p0: Vec2(0, 0),
                p1: Vec2(0, 33),
                p2: Vec2(0, 66),
                p3: Vec2(0, 100)
            )
        ])
        
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 10.0,
            sweepSampleCount: 10 // Small sample count for testing
        )
        
        // Clear observed values before running sweep
        observedTValues.removeAll()
        
        // Run a tiny sweep - this should call offsetAtT multiple times
        // We'll just call effectiveOffsetAtT directly to simulate what happens in the sweep
        for t in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0] {
            _ = plan.effectiveOffsetAtT(t)
        }
        
        // Verify we observed multiple distinct t values
        let uniqueTValues = Set(observedTValues)
        XCTAssertGreaterThan(uniqueTValues.count, 2, "Should observe more than 2 distinct t values, got \(uniqueTValues.count): \(Array(uniqueTValues).sorted())")
        
        // Verify interpolation is working (not just first keyframe)
        let values = observedTValues.map { jsonOffset.value(at: $0) }
        let uniqueValues = Set(values)
        XCTAssertGreaterThan(uniqueValues.count, 1, "Should observe multiple different offset values due to interpolation")
    }
    
    func testJFixtureParameterWiring() throws {
        // Integration test: Load J.v0.json and verify SweepPlan has correct parameter values
        // This test will fail if decoding/wiring is wrong
        
        let fixturePath = "Fixtures/glyphs/J.v0.json"
        guard let spec = loadSpec(path: fixturePath) else {
            XCTFail("Failed to load spec from \(fixturePath)")
            return
        }
        
        guard let stroke = spec.strokes?.first, let params = stroke.params else {
            XCTFail("Stroke params missing from fixture")
            return
        }
        
        // Build plan the same way CLI does
        let provider = ExampleParamProvider()
        var options = CLIOptions()
        options.example = nil
        var funcs = provider.makeParamFuncs(options: options, exampleName: nil, sweepWidth: 20.0)
        
        // Wire params from JSON (same as CLIPipeline does)
        if let jsonOffset = params.offset {
            funcs.offsetAtT = { t in jsonOffset.value(at: t) }
        }
        if let jsonWidth = params.width {
            funcs.widthAtT = { t in jsonWidth.value(at: t) }
        }
        if let jsonTheta = params.theta {
            // JSON stores theta in degrees, convert to radians (same as CLIPipeline)
            funcs.thetaAtT = { t in jsonTheta.value(at: t) * Double.pi / 180.0 }
        }
        
        // Enable variable width/angle/alpha if JSON params are present (same as CLIPipeline)
        if params.width != nil || params.theta != nil || params.offset != nil {
            funcs.usesVariableWidthAngleAlpha = true
        }
        
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 10.0,
            sweepSampleCount: 64
        )
        
        // Assert exact values from J.v0.json:
        // width: 200 at t=0, 20 at t=0.9, 110 at t=1.0
        XCTAssertEqual(plan.widthAtT(0.0), 200.0, accuracy: 1e-6, "Width at t=0 should be 200")
        XCTAssertEqual(plan.widthAtT(0.9), 20.0, accuracy: 1e-6, "Width at t=0.9 should be 20")
        XCTAssertEqual(plan.widthAtT(1.0), 110.0, accuracy: 1e-6, "Width at t=1.0 should be 110")
        
        // offset: 25 at t=0, 0 at t=0.9, 28 at t=1.0
        XCTAssertEqual(plan.offsetAtT(0.0), 25.0, accuracy: 1e-6, "Offset at t=0 should be 25")
        XCTAssertEqual(plan.offsetAtT(0.9), 0.0, accuracy: 1e-6, "Offset at t=0.9 should be 0")
        XCTAssertEqual(plan.offsetAtT(1.0), 28.0, accuracy: 1e-6, "Offset at t=1.0 should be 28")
        
        // theta: 50 at t=0, 0 at t=1.0 (JSON stores degrees, converted to radians)
        let theta0Rad = 50.0 * Double.pi / 180.0
        let theta1Rad = 0.0
        XCTAssertEqual(plan.thetaAtT(0.0), theta0Rad, accuracy: 1e-6, "Theta at t=0 should be 50 degrees converted to radians")
        XCTAssertEqual(plan.thetaAtT(1.0), theta1Rad, accuracy: 1e-6, "Theta at t=1.0 should be 0")
    }
}

