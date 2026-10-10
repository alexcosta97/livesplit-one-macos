import XCTest

/// Logging as a user sees it: the files in the log folder (spec §12.2).
final class LoggingTests: XCTestCase {
    @MainActor
    func testTheLaunchIsLoggedInTheLogFolder() throws {
        let e2e = E2EApp()
        e2e.launch()
        XCTAssertTrue(e2e.timerWindow.waitForExistence(timeout: 10))
        let text = try XCTUnwrap(
            e2e.logText(containing: "  APP  LiveSplit One for macOS "),
            "No launch line in the log files in \(e2e.logFolder.path)")
        let names = try FileManager.default.contentsOfDirectory(atPath: e2e.logFolder.path)
        // Two if midnight passed during the test.
        XCTAssertTrue((1...2).contains(names.count), "\(names)")
        for name in names {
            XCTAssertNotNil(
                name.range(
                    of: #"^livesplit-one-macos-\d{4}-\d{2}-\d{2}\.log$"#,
                    options: .regularExpression),
                name)
        }
        XCTAssertNotNil(
            text.range(of: #"^\d\d:\d\d:\d\d\.\d{3}  APP  "#, options: .regularExpression))
    }
}
