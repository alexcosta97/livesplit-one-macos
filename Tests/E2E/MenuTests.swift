import XCTest

/// The right-click menu, the menu bar and the keyboard shortcuts as a user uses them (spec §7,
/// §14.3).
final class MenuTests: XCTestCase {
    /// How many times `text` is in `log`.
    private func occurrences(of text: String, in log: String) -> Int {
        log.components(separatedBy: text).count - 1
    }

    @MainActor
    func testControlItemsFollowTheTimer() {
        let e2e = E2EApp.launched()

        let start = e2e.menuItem("timer-start_split", under: ["timer-control"])
        XCTAssertEqual(start.title, "Start")
        XCTAssertFalse(e2e.app.menuItems["timer-reset"].isEnabled)
        XCTAssertFalse(e2e.app.menuItems["timer-undo_split"].isEnabled)
        start.click()
        e2e.waitForLog("Start/Split from the menu")

        let split = e2e.menuItem("timer-start_split", under: ["timer-control"])
        XCTAssertEqual(split.title, "Split")
        XCTAssertTrue(e2e.app.menuItems["timer-pause"].isEnabled)
        split.click()  // One segment: the run ends.
        e2e.waitForLog("Start/Split from the menu", count: 2)

        let undo = e2e.menuItem("timer-undo_split", under: ["timer-control"])
        XCTAssertTrue(undo.isEnabled)
        XCTAssertFalse(e2e.app.menuItems["timer-start_split"].isEnabled)
        undo.click()
        e2e.waitForLog("Undo Split from the menu")

        let reset = e2e.menuItem("timer-reset", under: ["timer-control"])
        XCTAssertTrue(reset.isEnabled)
        XCTAssertEqual(e2e.app.menuItems["timer-start_split"].title, "Split")
        reset.click()
        e2e.waitForLog("Reset from the menu")

        XCTAssertEqual(e2e.menuItem("timer-start_split", under: ["timer-control"]).title, "Start")
        XCTAssertFalse(e2e.app.menuItems["timer-reset"].isEnabled)
        e2e.closeMenus()
    }

    @MainActor
    func testSpaceStartsTheTimer() {
        let e2e = E2EApp.launched()
        e2e.app.typeKey(" ", modifierFlags: [])
        e2e.waitForLog("Start/Split from the keyboard")
        XCTAssertEqual(e2e.menuItem("timer-start_split", under: ["timer-control"]).title, "Split")
        e2e.closeMenus()
    }

    @MainActor
    func testAShortcutAddedInSettingsRunsItsCommand() {
        let e2e = E2EApp.launched()
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
        e2e.waitForLog("Start/Split from the keyboard")
    }

    /// Space and `u` are Control shortcuts, and Split and Undo Split are enabled while the run
    /// goes on, but typed in the Settings window they run nothing (spec §7.2).
    @MainActor
    func testControlShortcutsDontRunInTheSettingsWindow() {
        let e2e = E2EApp.launched()
        e2e.app.typeKey(" ", modifierFlags: [])
        e2e.waitForLog("Start/Split from the keyboard")

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
        let log = e2e.waitForLog("Pause from the keyboard")
        XCTAssertEqual(occurrences(of: "from the menu", in: log), 0, log)
        XCTAssertEqual(occurrences(of: "Start/Split from the keyboard", in: log), 1, log)
        XCTAssertEqual(occurrences(of: "Undo Split from", in: log), 0, log)
    }

    /// The timer isn't started: a running timer redraws the window all the time, so every
    /// picture would differ. The default layout's splits show each segment's comparison time,
    /// which differs between Personal Best and Best Segments, and between Real Time and Game Time
    /// in GameTime.lss.
    @MainActor
    func testCompareAgainstAndTheTimingMethodChangeWhatTheWindowShows() {
        let e2e = E2EApp.launched(picks: ["GameTime.lss"])
        let window = e2e.timerWindow
        let empty = e2e.waitForPicture(differentFrom: [], in: window)
        e2e.choose("timer-open-splits-choose", under: ["timer-open-splits"])
        e2e.waitForLog("Opened splits")
        let opened = e2e.waitForPicture(differentFrom: empty, in: window)
        XCTAssertFalse(opened == empty, "the window doesn't show the opened splits")
        XCTAssertTrue(e2e.picture(of: window) == opened, "the window changes by itself")

        e2e.choose("Best Segments", under: ["timer-compare-against"])
        let bestSegments = e2e.waitForPicture(differentFrom: opened, in: window)
        XCTAssertFalse(bestSegments == opened, "Best Segments didn't change the window")

        e2e.choose("Game Time", under: ["timer-compare-against"])
        XCTAssertFalse(
            e2e.waitForPicture(differentFrom: bestSegments, in: window) == bestSegments,
            "Game Time didn't change the window")
    }

    @MainActor
    func testAlwaysOnTopFromTheMenuIsSaved() {
        let e2e = E2EApp.launched()
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
        let e2e = E2EApp.launched()
        e2e.app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(e2e.app.wait(for: .notRunning, timeout: 10))
    }
}
