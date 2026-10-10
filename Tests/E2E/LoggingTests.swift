import XCTest

/// Logging as a user sees it: the files in the log folder (spec §12.2).
final class LoggingTests: XCTestCase {
    @MainActor
    func testTheLaunchIsLoggedInTheLogFolder() throws {
        let e2e = E2EApp()
        e2e.launch()
        XCTAssertTrue(e2e.timerWindow.waitForExistence(timeout: 10))
        let text = try XCTUnwrap(e2e.logText(containing: "  APP  LiveSplit One for macOS "))
        let names = try FileManager.default.contentsOfDirectory(atPath: e2e.logFolder.path)
        XCTAssertEqual(names.count, 1, "\(names)")
        XCTAssertTrue(names[0].hasPrefix("livesplit-one-macos-"), names[0])
        XCTAssertTrue(names[0].hasSuffix(".log"), names[0])
        XCTAssertNotNil(
            text.range(of: #"^\d\d:\d\d:\d\d\.\d{3}  APP  "#, options: .regularExpression))
    }
}
