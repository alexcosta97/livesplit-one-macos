import XCTest

/// E2E tests drive the app only through what a user does and sees (spec §14.1).
final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsTheTimerWindow() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows["timer-window"].waitForExistence(timeout: 10))
    }
}
