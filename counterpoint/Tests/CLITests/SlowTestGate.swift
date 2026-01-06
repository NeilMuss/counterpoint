import Foundation
import XCTest

enum SlowTestGate {
    private static var didWarn = false

    static func requireSlowTests(file: StaticString = #filePath, line: UInt = #line) throws {
        let enabled = ProcessInfo.processInfo.environment["RUN_SLOW_TESTS"] == "1"
        guard enabled else {
            if !didWarn {
                didWarn = true
                fputs("note: skipping slow tests (set RUN_SLOW_TESTS=1 to enable)\n", stderr)
            }
            throw XCTSkip("Set RUN_SLOW_TESTS=1 to run slow tests.")
        }
    }
}
