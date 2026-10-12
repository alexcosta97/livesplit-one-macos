import XCTest

/// The right-click menu, the menu bar and the keyboard shortcuts as a user uses them (spec §7,
/// §14.3).
final class MenuTests: XCTestCase {
    @MainActor
    private func launched() -> E2EApp {
        let e2e = E2EApp()
        e2e.launch()
        XCTAssertTrue(e2e.timerWindow.waitForExistence(timeout: 10))
        return e2e
    }

    /// Right-clicks the timer and opens Control. Returns the right-click menu's item for
    /// `command`, such as `start_split`.
    @MainActor
    private func controlItem(_ command: String, _ e2e: E2EApp) -> XCUIElement {
        e2e.timerWindow.rightClick()
        let control = e2e.app.menuItems["timer-control"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.hover()
        let item = control.menuItems["timer-\(command)"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        return item
    }

    @MainActor
    private func closeMenus(_ e2e: E2EApp) {
        e2e.app.typeKey(.escape, modifierFlags: [])
        e2e.app.typeKey(.escape, modifierFlags: [])
    }

    /// How many times `text` is in `log`.
    private func occurrences(of text: String, in log: String) -> Int {
        log.components(separatedBy: text).count - 1
    }

    /// Waits until the log holds `text` `count` times, and returns the log.
    @MainActor
    @discardableResult
    private func waitForLog(_ text: String, count: Int = 1, _ e2e: E2EApp) -> String {
        let deadline = Date().addingTimeInterval(10)
        var log = ""
        while Date() < deadline {
            log = e2e.logText(containing: text, timeout: 1) ?? log
            if occurrences(of: text, in: log) >= count { return log }
        }
        XCTFail("the log doesn't hold \"\(text)\" \(count) times. The log:\n\(log)")
        return log
    }

    @MainActor
    func testControlItemsFollowTheTimer() {
        let e2e = launched()

        let start = controlItem("start_split", e2e)
        XCTAssertEqual(start.title, "Start")
        XCTAssertFalse(e2e.app.menuItems["timer-reset"].isEnabled)
        XCTAssertFalse(e2e.app.menuItems["timer-undo_split"].isEnabled)
        start.click()
        waitForLog("Start/Split from the menu", e2e)

        let split = controlItem("start_split", e2e)
        XCTAssertEqual(split.title, "Split")
        XCTAssertTrue(e2e.app.menuItems["timer-pause"].isEnabled)
        split.click()  // One segment: the run ends.
        waitForLog("Start/Split from the menu", count: 2, e2e)

        let undo = controlItem("undo_split", e2e)
        XCTAssertTrue(undo.isEnabled)
        XCTAssertFalse(e2e.app.menuItems["timer-start_split"].isEnabled)
        undo.click()
        waitForLog("Undo Split from the menu", e2e)

        let reset = controlItem("reset", e2e)
        XCTAssertTrue(reset.isEnabled)
        XCTAssertEqual(e2e.app.menuItems["timer-start_split"].title, "Split")
        reset.click()
        waitForLog("Reset from the menu", e2e)

        XCTAssertEqual(controlItem("start_split", e2e).title, "Start")
        XCTAssertFalse(e2e.app.menuItems["timer-reset"].isEnabled)
        closeMenus(e2e)
    }

    @MainActor
    func testSpaceStartsTheTimer() {
        let e2e = launched()
        e2e.app.typeKey(" ", modifierFlags: [])
        waitForLog("Start/Split from the keyboard", e2e)
        XCTAssertEqual(controlItem("start_split", e2e).title, "Split")
        closeMenus(e2e)
    }

    @MainActor
    func testAShortcutAddedInSettingsRunsItsCommand() {
        let e2e = launched()
        e2e.app.typeKey(",", modifierFlags: .command)
        let settings = e2e.app.windows["settings-window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        settings.buttons["add-shortcut-start_split"].click()
        e2e.app.typeKey("k", modifierFlags: [])
        XCTAssertTrue(settings.buttons["shortcut-start_split-1"].waitForExistence(timeout: 5))
        let saved = e2e.settingsText(containing: "\"k\"")
        XCTAssertNotNil(saved, "app.toml doesn't hold the new shortcut")
        XCTAssertTrue(saved?.contains("start_split") == true)

        // Close (⌘W) from the Window menu, then the timer window is key again.
        e2e.app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
        e2e.app.typeKey("k", modifierFlags: [])
        waitForLog("Start/Split from the keyboard", e2e)
    }

    /// Space and `u` are Control shortcuts, and Split and Undo Split are enabled while the run
    /// goes on, but typed in the Settings window they run nothing (spec §7.2).
    @MainActor
    func testControlShortcutsDontRunInTheSettingsWindow() {
        let e2e = launched()
        e2e.app.typeKey(" ", modifierFlags: [])
        waitForLog("Start/Split from the keyboard", e2e)

        e2e.app.typeKey(",", modifierFlags: .command)
        let settings = e2e.app.windows["settings-window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        e2e.app.typeKey(" ", modifierFlags: [])
        e2e.app.typeKey("u", modifierFlags: [])
        e2e.app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5))

        // Commands run in order, so once Pause from the timer window is logged, anything the
        // Settings window had sent would be logged too.
        e2e.app.typeKey("p", modifierFlags: [])
        let log = waitForLog("Pause from the keyboard", e2e)
        XCTAssertEqual(occurrences(of: "from the menu", in: log), 0, log)
        XCTAssertEqual(occurrences(of: "Start/Split from the keyboard", in: log), 1, log)
        XCTAssertEqual(occurrences(of: "Undo Split from", in: log), 0, log)
    }

    @MainActor
    func testCompareAgainstAndTheTimingMethod() {
        let e2e = launched()
        for choice in ["Best Segments", "Game Time", "Real Time"] {
            e2e.timerWindow.rightClick()
            let compare = e2e.app.menuItems["timer-compare-against"]
            XCTAssertTrue(compare.waitForExistence(timeout: 5))
            compare.hover()
            let item = compare.menuItems[choice]
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.click()
        }
        waitForLog(#"Compare Against Best Segments from the menu: {"success":null}"#, e2e)
        waitForLog(#"Game Time from the menu: {"success":null}"#, e2e)
        waitForLog(#"Real Time from the menu: {"success":null}"#, e2e)
    }

    @MainActor
    func testAlwaysOnTopFromTheMenuIsSaved() {
        let e2e = launched()
        e2e.timerWindow.rightClick()
        let item = e2e.app.menuItems["timer-always-on-top"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        // XCUITest shows no tick on a menu item: a ticked item's `value` is "" and `isSelected`
        // is false, as for an unticked one. So the saved setting is what is checked here.
        XCTAssertNotNil(e2e.settingsText(containing: "always_on_top = true"))
    }

    @MainActor
    func testCommandQQuits() {
        let e2e = launched()
        e2e.app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(e2e.app.wait(for: .notRunning, timeout: 10))
    }
}
