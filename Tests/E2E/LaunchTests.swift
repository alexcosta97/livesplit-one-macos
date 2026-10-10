import XCTest

/// E2E tests drive the app only through what a user does and sees (spec §14.1).
final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsTheTimerWindow() {
        let e2e = E2EApp()
        e2e.launch()
        XCTAssertTrue(e2e.timerWindow.waitForExistence(timeout: 10))
    }
}
