import XCTest
import CP2Geometry
import CP2Skeleton

final class SCurveParameterizationTests: XCTestCase {
    func testSCurveEndpointsMonotoneAndTangent() {
        let curve = sCurveFixtureCubic()
        let path = SkeletonPath(segments: [curve])
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)

        XCTAssertTrue(Epsilon.approxEqual(param.position(globalT: 0.0), curve.p0, eps: 1.0e-6))
        XCTAssertTrue(Epsilon.approxEqual(param.position(globalT: 1.0), curve.p3, eps: 1.0e-6))

        let gtValues: [Double] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
        var previousU = -Double.greatestFiniteMagnitude
        for gt in gtValues {
            let mapping = param.map(globalT: gt)
            XCTAssertGreaterThanOrEqual(mapping.localU + 1.0e-12, previousU)
            previousU = mapping.localU
            let tan = param.tangent(globalT: gt)
            XCTAssertTrue(tan.length > 1.0e-9)
        }
    }
}
