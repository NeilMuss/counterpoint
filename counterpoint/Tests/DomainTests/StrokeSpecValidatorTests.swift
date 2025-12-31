import XCTest
@testable import Domain

final class StrokeSpecValidatorTests: XCTestCase {
    func testRejectsEmptyPathAndNonPositiveWidth() {
        let spec = StrokeSpec(
            path: BezierPath(segments: []),
            width: ParamTrack.constant(0),
            height: ParamTrack.constant(10),
            theta: ParamTrack.constant(0),
            angleMode: .absolute,
            sampling: SamplingSpec()
        )

        XCTAssertThrowsError(try StrokeSpecValidator().validate(spec)) { error in
            let description = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(description.contains("Path must contain"))
            XCTAssertTrue(description.contains("width"))
        }
    }
}
