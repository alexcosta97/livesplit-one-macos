import XCTest

/// Settings as a user sees them: the file on disk (spec §11).
final class SettingsTests: XCTestCase {
    @MainActor
    func testTheFirstLaunchWritesNoSettings() throws {
        let e2e = E2EApp()
        e2e.launch()
        XCTAssertTrue(e2e.timerWindow.waitForExistence(timeout: 10))
        // Reading the settings is logged: once that line is there, the app has looked.
        XCTAssertNotNil(e2e.logText(containing: "No settings file yet at "))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: e2e.configFolder.appending(path: "app.toml").path))
    }
}
