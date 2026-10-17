import XCTest

/// Edit Splits as a user does it: rename a segment and change a time, then OK, and the same
/// with Cancel (spec §9, §14.3).
final class SplitsEditorTests: XCTestCase {
    /// Opens the editor from the right-click menu and returns its window.
    @MainActor
    private func openEditor(_ e2e: E2EApp) -> XCUIElement {
        e2e.choose("timer-edit-splits")
        // A modal window is a dialog to accessibility.
        let editor = e2e.app.dialogs["splits-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Edit Splits… didn't open the editor")
        XCTAssertEqual(editor.title, "Edit Splits")
        return editor
    }

    /// Renames the first segment `First` and types `1:23.45` as its split time, going from one
    /// cell to the next with Tab. The split time is left being edited.
    @MainActor
    private func editFirstSegment(in editor: XCUIElement, _ e2e: E2EApp) {
        let name = editor.descendants(matching: .any)["editor-cell-name-0"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "no name cell for the first segment")
        name.doubleClick()
        e2e.app.typeKey("a", modifierFlags: .command)
        e2e.app.typeText("First")
        e2e.app.typeKey(.tab, modifierFlags: [])
        e2e.app.typeText("1:23.45")
    }

    /// Saves the splits to `name` through Save Splits As… and returns the file's text.
    @MainActor
    private func saved(_ name: String, _ e2e: E2EApp) -> String? {
        e2e.choose("timer-save-splits-as")
        XCTAssertNotNil(e2e.logText(containing: "Saved splits to"), "the splits weren't saved")
        return try? String(contentsOf: e2e.savedFile(name), encoding: .utf8)
    }

    @MainActor
    func testEditingTheSplitsAndPressingOKChangesThem() {
        let e2e = E2EApp.launched(picks: ["saved:Edited.lss"])
        let editor = openEditor(e2e)
        editFirstSegment(in: editor, e2e)
        // Return in a cell ends only its edit (spec §9); the window stays open.
        e2e.app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(
            editor.waitForNonExistence(timeout: 1), "Return in a cell closed the editor")
        // Return again, with no cell being edited, is OK.
        e2e.app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "OK didn't close the editor")
        XCTAssertNotNil(e2e.logText(containing: "Edited the splits"))

        let text = saved("Edited.lss", e2e)
        XCTAssertNotNil(text, "Edited.lss wasn't written")
        XCTAssertTrue(text?.contains("<Name>First</Name>") == true, text ?? "")
        XCTAssertTrue(text?.contains("00:01:23.45") == true, "the split time wasn't kept")
    }

    @MainActor
    func testCancelDiscardsTheEdits() {
        let e2e = E2EApp.launched(picks: ["saved:Edited.lss"])
        let editor = openEditor(e2e)
        editFirstSegment(in: editor, e2e)
        // One Escape, though a cell is being edited, whose own Escape would end only its edit.
        e2e.app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "Escape didn't close the editor")

        let text = saved("Edited.lss", e2e)
        XCTAssertNotNil(text, "Edited.lss wasn't written")
        XCTAssertTrue(text?.contains("<Name>Time</Name>") == true, text ?? "")
        XCTAssertFalse(text?.contains("00:01:23.45") == true, "the split time was kept")
        XCTAssertNil(e2e.logText(containing: "Edited the splits", timeout: 0))
    }
}
