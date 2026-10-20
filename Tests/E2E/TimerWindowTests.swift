import XCTest

/// The timer window as a user sees and handles it (spec §6, §14.3).
final class TimerWindowTests: XCTestCase {
    @MainActor
    func testFirstLaunchShowsTheDefaultLayout() {
        let e2e = E2EApp()
        e2e.launch()
        let window = e2e.timerWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        XCTAssertEqual(window.frame.size, CGSize(width: 300, height: 500))
        let layout = window.images["timer-layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            e2e.colours(in: e2e.waitForDrawnPicture(of: window)), 10, "the window shows no layout")

        // The empty run: one segment named "Time" (TimerContent.defaultRun()), seen in the editor.
        e2e.choose("timer-edit-splits")
        let editor = e2e.app.dialogs["splits-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Edit Splits… didn't open the editor")
        let cells = editor.descendants(matching: .any)
        XCTAssertTrue(
            cells["editor-cell-name-0"].waitForExistence(timeout: 5),
            "no name cell for the first segment")
        XCTAssertEqual(cells["editor-cell-name-0"].value as? String, "Time")
        XCTAssertFalse(cells["editor-cell-name-1"].exists, "the run has a second segment")
        e2e.app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testTheWindowMovesAndOpensThereAgain() throws {
        let e2e = E2EApp()
        e2e.launch()
        let window = e2e.timerWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let before = window.frame

        // Built from .zero plus explicit offsets: normalized offsets landed in the wrong place on
        // the borderless window.
        let middle = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.width / 2, dy: before.height / 2))
        let target = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.width / 2 + 120, dy: before.height / 2 + 80))
        // click(forDuration:thenDragTo:), not press(forDuration:thenDragTo:): on macOS 27 the
        // press variant sends the app no mouse events at all (#57).
        middle.click(forDuration: 0.2, thenDragTo: target)

        let moved = window.frame
        XCTAssertEqual(moved.minX, before.minX + 120, accuracy: 2)
        XCTAssertEqual(moved.minY, before.minY + 80, accuracy: 2)
        // The frame is saved once the window stops. x is the same in XCUITest's coordinates and
        // AppKit's (only y is flipped), and app.toml writes it as a Double, such as "x = 690.0".
        let saved = e2e.settingsText(containing: "x = \(Double(moved.minX))")
        XCTAssertNotNil(saved, "app.toml doesn't hold the moved frame")
        XCTAssertTrue(saved?.contains("[default_layout_window]") == true)

        e2e.relaunch()
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(window.frame.minX, moved.minX, accuracy: 1)
        XCTAssertEqual(window.frame.minY, moved.minY, accuracy: 1)
        XCTAssertEqual(window.frame.size, moved.size)
    }

    @MainActor
    func testTheWindowResizesFromItsCorner() throws {
        let e2e = E2EApp()
        e2e.launch()
        let window = e2e.timerWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let before = window.frame

        // Built from .zero plus explicit offsets: normalized offsets landed in the wrong place on
        // the borderless window.
        let corner = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.width - 2, dy: before.height - 2))
        corner.click(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: 60, dy: 40)))

        XCTAssertEqual(window.frame.width, before.width + 60, accuracy: 3)
        XCTAssertEqual(window.frame.height, before.height + 40, accuracy: 3)
        XCTAssertEqual(window.frame.minX, before.minX, accuracy: 1)
        XCTAssertEqual(window.frame.minY, before.minY, accuracy: 1)
    }
}
