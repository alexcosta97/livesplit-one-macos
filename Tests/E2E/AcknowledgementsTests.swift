import XCTest

/// Help ▸ Acknowledgements as a user sees it: the notices of the third-party code in the app
/// (spec §4.4).
final class AcknowledgementsTests: XCTestCase {
    @MainActor
    func testHelpAcknowledgementsShowsTheNotices() throws {
        let e2e = E2EApp.launched()
        e2e.app.menuBars.menuBarItems["Help"].click()
        let item = e2e.app.menuBars.menuItems["help-acknowledgements"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()

        let window = e2e.app.windows["acknowledgements-window"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let text = try XCTUnwrap(window.textViews["acknowledgements-text"].value as? String)
        XCTAssertTrue(text.contains("  livesplit-core "), "livesplit-core isn't listed")
        XCTAssertTrue(text.contains("SIL OPEN FONT LICENSE"), "Fira Sans's licence isn't there")

        // Close (⌘W), then the timer window is key again.
        e2e.app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
    }
}
