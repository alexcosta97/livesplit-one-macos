import AppKit
import Foundation
import Testing

@testable import LiveSplitOne

/// The splits editor's segment table (spec §9), on `Grouped.lss`: rows A, the group "Last",
/// B and C, and the comparison "Goal".
@MainActor
@Suite final class SegmentTableTests {
    let prompts = ScriptedPrompts()
    let folder: TemporaryFolder
    /// How many times the window's OK ran.
    var oks = 0

    init() throws {
        folder = try TemporaryFolder()
    }

    private func makeController(fixture: String = "Grouped.lss") throws
        -> SplitsEditorViewController
    {
        let controller = SplitsEditorViewController(
            editing: SplitsEditing(run: try SplitsFile.load(Fixtures.url(fixture)), lang: 0),
            linkedLayout: .none, currentLayout: nil, prompts: prompts,
            ok: { [unowned self] in oks += 1 }, cancel: {})
        _ = controller.view
        return controller
    }

    /// An offscreen window showing `controller`, laid out so the table has made its cells.
    /// The caller closes it.
    private func host(_ controller: SplitsEditorViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 900, height: 600))
        controller.view.layoutSubtreeIfNeeded()
        return window
    }

    private func find<T: NSView>(_ identifier: String, in view: NSView) -> T? {
        if view.accessibilityIdentifier() == identifier, let match = view as? T { return match }
        for subview in view.subviews {
            if let match: T = find(identifier, in: subview) { return match }
        }
        return nil
    }

    private func table(_ controller: SplitsEditorViewController) throws -> NSTableView {
        try #require(find("editor-segments", in: controller.view))
    }

    private func cell(_ column: String, _ row: Int, _ controller: SplitsEditorViewController)
        throws -> NSTextField
    {
        try #require(find("editor-cell-\(column)-\(row)", in: controller.view))
    }

    private func icon(_ row: Int, _ controller: SplitsEditorViewController) throws -> IconButton {
        try #require(find("editor-cell-icon-\(row)", in: controller.view))
    }

    /// Ends editing of a cell with `text` the way the field tells its delegate: first asked
    /// whether it may end, then told it ended if it may.
    @discardableResult
    private func enter(
        _ text: String, in column: String, _ row: Int, _ controller: SplitsEditorViewController
    ) throws -> Bool {
        let field = try cell(column, row, controller)
        field.stringValue = text
        let table = controller.segmentTable
        guard table.control(field, textShouldEndEditing: NSText()) else { return false }
        table.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field))
        return true
    }

    private func click(
        _ row: Int, _ flags: NSEvent.ModifierFlags = [], _ controller: SplitsEditorViewController
    ) throws -> IndexSet {
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        return try select([row], event: event, clickedRow: row, controller)
    }

    /// What the table does with a proposed selection: asks its delegate, then shows the answer.
    private func select(
        _ proposed: IndexSet, event: NSEvent?, clickedRow: Int,
        _ controller: SplitsEditorViewController
    ) throws -> IndexSet {
        let selected = controller.segmentTable.selection(
            proposed: proposed, event: event, clickedRow: clickedRow)
        try table(controller).selectRowIndexes(selected, byExtendingSelection: false)
        return selected
    }

    private func png() throws -> Data {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func theTableHasTheRowsAndColumns() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let table = try table(controller)
        #expect(table.numberOfRows == 4)
        #expect(table.allowsMultipleSelection)
        #expect(!table.allowsEmptySelection)
        #expect(!table.allowsColumnReordering)
        #expect(
            table.tableColumns.map(\.identifier.rawValue) == [
                "icon", "name", "split", "segment", "best", "comparison-0",
            ])
        #expect(
            table.tableColumns.map(\.title) == [
                "", "Segment Name", "Split Time", "Segment Time", "Best Segment", "Goal",
            ])
        #expect(table.tableColumns[0].headerCell.accessibilityLabel() == "Icon")
        #expect(try cell("name", 0, controller).stringValue == "A")
        #expect(try cell("name", 2, controller).stringValue == "B")
        #expect(try cell("name", 3, controller).stringValue == "C")
        #expect(try cell("comparison-0", 0, controller).isEditable)
    }

    @Test func theGroupRowShowsItsNameBoldAndNoTimes() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let name = try cell("name", 1, controller)
        #expect(name.stringValue == "Last")
        #expect(name.placeholderString == "Last")
        #expect(name.isEditable)
        #expect(name.font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(
            try cell("name", 0, controller).font?.fontDescriptor.symbolicTraits
                .contains(.bold) == false)
        for column in ["split", "segment", "best", "comparison-0"] {
            let time = try cell(column, 1, controller)
            #expect(time.stringValue == "")
            #expect(!time.isEditable)
            #expect(!time.isSelectable)
            #expect(!time.acceptsFirstResponder)
            // The field's cell is what VoiceOver reads.
            #expect(time.cell?.isAccessibilityElement() == false)
            let segmentTime = try cell(column, 2, controller)
            #expect(segmentTime.isSelectable)
            #expect(segmentTime.cell?.isAccessibilityElement() == true)
        }
    }

    @Test func theGroupsSegmentsAreIndented() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let a = try cell("name", 0, controller)
        let b = try cell("name", 2, controller)
        let group = try cell("name", 1, controller)
        #expect(b.frame.minX - a.frame.minX == 16)
        #expect(group.frame.minX == a.frame.minX)
    }

    @Test func aTimeIsSetAsTheEditorWritesIt() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        #expect(try enter("1:00", in: "split", 0, controller))
        #expect(try cell("split", 0, controller).stringValue == "1:00.00")
        guard case .segment(let a) = controller.editing.state.rows[0] else {
            Issue.record("Row 0 isn't a segment")
            return
        }
        #expect(a.splitTime == "1:00.00")
    }

    @Test func aTimeInAGroupGoesToItsSegmentNotItsRow() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        #expect(try enter("2:00", in: "comparison-0", 3, controller))
        #expect(try enter("Z", in: "name", 3, controller))
        guard case .segment(let c) = controller.editing.state.rows[3] else {
            Issue.record("Row 3 isn't a segment")
            return
        }
        #expect(c.segmentIndex == 2)
        #expect(c.name == "Z")
        #expect(c.comparisonTimes == ["2:00.00"])
        #expect(try cell("comparison-0", 3, controller).stringValue == "2:00.00")
        #expect(try cell("name", 1, controller).stringValue == "Last")
    }

    @Test func aBadTimeIsRefusedInRedWithAMessage() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let before = controller.editing.state.rows
        #expect(try !enter("abc", in: "split", 0, controller))
        let field = try cell("split", 0, controller)
        #expect(field.textColor == .systemRed)
        let message: NSTextField = try #require(find("editor-message", in: controller.view))
        #expect(!message.isHidden)
        #expect(message.stringValue == "Enter a time, such as 1:23.45.")
        guard case .segment(let a) = controller.editing.state.rows[0],
            case .segment(let old) = before[0]
        else {
            Issue.record("Row 0 isn't a segment")
            return
        }
        #expect(a.splitTime == old.splitTime)

        #expect(try enter("1:00", in: "split", 0, controller))
        #expect(field.textColor == .controlTextColor)
        #expect(message.isHidden)
    }

    /// Return in a cell ends only that cell's edit and leaves the window open (spec §9).
    @Test func returnInACellEndsItsEditOnly() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let b = try cell("name", 2, controller)
        #expect(window.makeFirstResponder(b))
        let editor = try #require(b.currentEditor() as? NSTextView)
        editor.string = "Bee"
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        guard case .segment(let segment) = controller.editing.state.rows[2] else {
            Issue.record("Row 2 isn't a segment")
            return
        }
        #expect(segment.name == "Bee")
        #expect(b.currentEditor() == nil)
        #expect(window.firstResponder === (try table(controller)))
        #expect(oks == 0)

        // Return again, with no cell being edited, is OK: the table gives it to the window.
        try table(controller).keyDown(with: try returnKey(window))
        #expect(oks == 1)
    }

    private func returnKey(_ window: NSWindow) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    }

    /// Return in a cell with a bad time keeps it being edited, in red.
    @Test func returnInACellWithABadTimeKeepsItsEdit() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let split = try cell("split", 0, controller)
        #expect(window.makeFirstResponder(split))
        let editor = try #require(split.currentEditor() as? NSTextView)
        // Typed, so the field knows its text changed and asks whether editing may end.
        editor.selectAll(nil)
        editor.insertText("abc", replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(split.currentEditor() != nil)
        #expect(split.textColor == .systemRed)
        #expect(oks == 0)
    }

    @Test func aForcedEndOfABadTimeShowsTheTimeAgain() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let field = try cell("split", 0, controller)
        field.stringValue = "abc"
        #expect(!controller.segmentTable.control(field, textShouldEndEditing: NSText()))
        controller.segmentTable.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(field.stringValue == "")
        #expect(field.textColor == .controlTextColor)
        #expect(try #require(find("editor-message", in: controller.view) as NSTextField?).isHidden)
    }

    @Test func aCommandClickLeavesTheTablesSelectionTheStates() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let table = try table(controller)
        #expect(table.selectedRowIndexes == [0])
        let selected = try click(3, .command, controller)
        #expect(selected == [0, 3])
        #expect(selected == EditorSelection.selectedRows(controller.editing.state.rows))
        controller.refresh()
        #expect(table.selectedRowIndexes == [0, 3])

        #expect(try click(3, .command, controller) == [0])
        #expect(try click(3, .shift, controller) == [0, 1, 2, 3])
    }

    /// Clicking another row while a cell is being edited, as AppKit orders it (seen in the
    /// app): the mouse down ends the cell's edit, then the table proposes the clicked row as
    /// the mouse goes up. The typed name goes to its own segment, and only the clicked row is
    /// selected and active.
    @Test func clickingAnotherRowWhileEditingCommitsToTheEditedSegment() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let table = try table(controller)
        _ = try click(2, [], controller)
        let b = try cell("name", 2, controller)
        #expect(window.makeFirstResponder(b))
        let editor = try #require(b.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("Bee", replacementRange: editor.selectedRange())

        #expect(window.makeFirstResponder(table))
        let up = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        #expect(try select([0], event: up, clickedRow: -1, controller) == [0])

        let rows = controller.editing.state.rows
        guard case .segment(let a) = rows[0], case .segment(let bee) = rows[2] else {
            Issue.record("Rows 0 and 2 aren't segments")
            return
        }
        #expect(bee.name == "Bee")
        #expect(bee.selected == .notSelected)
        #expect(a.selected == .active)
        #expect(table.selectedRowIndexes == [0])
    }

    @Test func clickingTheGroupRowSelectsItsSegments() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        #expect(try click(1, [], controller) == [1, 2, 3])
        #expect(EditorSelection.selectedRows(controller.editing.state.rows) == [1, 2, 3])
    }

    @Test func aSelectionWithNoClickIsProposed() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let keyDown = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
            keyCode: 125)
        #expect(try select([2], event: keyDown, clickedRow: -1, controller) == [2])
        // ⇧-arrow adds C to B, and so the whole group.
        #expect(try select([2, 3], event: nil, clickedRow: -1, controller) == [1, 2, 3])
        // A click outside the rows is a proposal too.
        let selected = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        #expect(try select([0], event: selected, clickedRow: -1, controller) == [0])
    }

    @Test func theModifierComesFromTheEvent() {
        #expect(SegmentTable.modifier([]) == EditorSelection.Modifier.none)
        #expect(SegmentTable.modifier(.command) == .command)
        #expect(SegmentTable.modifier(.shift) == .shift)
        #expect(SegmentTable.modifier([.command, .shift]) == .command)
    }

    @Test func refreshSelectsWhatTheStateSelects() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        controller.editing.apply([.only(1), .additionally(2)])
        controller.refresh()
        #expect(try table(controller).selectedRowIndexes == [1, 2, 3])
        // Setting the selection doesn't go back to the editor.
        guard case .segment(let c) = controller.editing.state.rows[3] else {
            Issue.record("Row 3 isn't a segment")
            return
        }
        #expect(c.selected == .active)
    }

    @Test func emptyingTheGroupsNameShowsItsLastSegmentsGreyed() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        #expect(try enter("", in: "name", 1, controller))
        let name = try cell("name", 1, controller)
        #expect(name.stringValue == "")
        #expect(name.placeholderString == "C")
        guard case .group(let group) = controller.editing.state.rows[1] else {
            Issue.record("Row 1 isn't a group")
            return
        }
        #expect(group.explicitName == nil)
        #expect(try enter("Ending", in: "name", 1, controller))
        #expect(name.stringValue == "Ending")
    }

    @Test func aRefreshDuringTabKeepsTheNextCellEditing() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let b = try cell("name", 2, controller)
        let c = try cell("name", 3, controller)
        let split = try cell("split", 3, controller)
        #expect(window.makeFirstResponder(b))
        b.currentEditor()?.string = "Bee"
        // Tab ends the edit through the delegate, which redraws, then edits the next field. A
        // real Tab moves along a row here (the next test) but doesn't wrap to the next row in
        // an offscreen window, so moving to C's name is done as Tab does it, with
        // makeFirstResponder; Task 8's E2E test presses a real Tab.
        #expect(window.makeFirstResponder(c))
        guard case .segment(let segment) = controller.editing.state.rows[2] else {
            Issue.record("Row 2 isn't a segment")
            return
        }
        #expect(segment.name == "Bee")
        #expect(b.stringValue == "Bee")
        #expect(c.currentEditor() != nil)
        c.currentEditor()?.string = "Typing"

        // An edit elsewhere in C's row selects it, and so the group, while C is being edited.
        let table = try table(controller)
        #expect(!table.selectedRowIndexes.contains(3))
        _ = controller.editing.setTime(.split, "1:00", segment: 2)
        controller.refresh()
        #expect(table.selectedRowIndexes == [0, 1, 2, 3])
        #expect(c.currentEditor()?.string == "Typing")
        #expect(try cell("name", 3, controller) === c)
        #expect(try cell("split", 3, controller) === split)
        #expect(split.stringValue == "1:00.00")
    }

    @Test func aRealTabKeepsTheNextCellEditingThroughARedraw() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let b = try cell("name", 2, controller)
        let split = try cell("split", 2, controller)
        #expect(window.makeFirstResponder(b))
        let editor = try #require(b.currentEditor() as? NSTextView)
        editor.string = "Bee"
        editor.insertTab(nil)
        guard case .segment(let segment) = controller.editing.state.rows[2] else {
            Issue.record("Row 2 isn't a segment")
            return
        }
        #expect(segment.name == "Bee")
        #expect(b.stringValue == "Bee")
        #expect(split.currentEditor() != nil)
        split.currentEditor()?.string = "Typing"

        let table = try table(controller)
        _ = controller.editing.setTime(.split, "1:00", segment: 2)
        controller.refresh()
        #expect(table.selectedRowIndexes == [0, 1, 2, 3])
        #expect(split.currentEditor()?.string == "Typing")
        #expect(try cell("split", 2, controller) === split)
        #expect(try cell("split", 3, controller).stringValue == "1:00.00")
    }

    @Test func comparisonColumnsKeepTheirWidths() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let table = try table(controller)
        let goal = try #require(table.tableColumns.last)
        goal.width = 150
        #expect(controller.editing.addComparison("Goal 2"))
        controller.refresh()
        #expect(table.tableColumns.map(\.width).suffix(2) == [150, 100])
        table.tableColumns.last?.width = 130

        // A rename keeps the column's place and width.
        #expect(controller.editing.renameComparison("Goal", to: "PB Goal"))
        controller.refresh()
        #expect(table.tableColumns.map(\.title).suffix(2) == ["PB Goal", "Goal 2"])
        #expect(table.tableColumns.map(\.width).suffix(2) == [150, 130])

        // A removed comparison takes its column; the others keep theirs.
        controller.editing.removeComparison("PB Goal")
        controller.refresh()
        #expect(table.tableColumns.last?.title == "Goal 2")
        #expect(table.tableColumns.last?.identifier.rawValue == "comparison-0")
        #expect(table.tableColumns.last?.width == 130)
    }

    @Test func aNewComparisonAddsAColumn() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        #expect(controller.editing.addComparison("Goal 2"))
        controller.refresh()
        controller.view.layoutSubtreeIfNeeded()
        let table = try table(controller)
        #expect(table.tableColumns.map(\.title).suffix(2) == ["Goal", "Goal 2"])
        #expect(table.tableColumns.last?.identifier.rawValue == "comparison-1")
        #expect(try cell("comparison-1", 0, controller).isEditable)

        controller.editing.removeComparison("Goal")
        controller.refresh()
        #expect(table.tableColumns.map(\.title).suffix(2) == ["Best Segment", "Goal 2"])
        #expect(table.tableColumns.last?.identifier.rawValue == "comparison-0")
    }

    @Test func aNewSegmentAddsARow() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        controller.editing.insertBelow()
        controller.refresh()
        controller.view.layoutSubtreeIfNeeded()
        let table = try table(controller)
        #expect(table.numberOfRows == 5)
        #expect(table.selectedRowIndexes == [1])
        #expect(try cell("name", 1, controller).placeholderString == nil)
        #expect(try cell("name", 2, controller).stringValue == "Last")
    }

    @Test func aSegmentsIconIsChosenAndRemoved() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let url = folder.url.appending(path: "icon.png")
        try png().write(to: url)
        prompts.images = [url]
        try icon(3, controller).chooseImage()
        guard case .segment(let c) = controller.editing.state.rows[3] else {
            Issue.record("Row 3 isn't a segment")
            return
        }
        #expect(controller.editing.image(c.icon) != nil)
        #expect(try icon(3, controller).icon != nil)
        #expect(try icon(3, controller).makeMenu().items[1].isEnabled)
        // The group takes its last segment's icon, which only the segment can remove.
        let group = try icon(1, controller)
        #expect(group.icon != nil)
        #expect(!group.makeMenu().items[1].isEnabled)
        #expect(try icon(3, controller).frame.width == 24)

        try icon(3, controller).removeImage()
        #expect(try icon(3, controller).icon == nil)
        #expect(group.icon == nil)
    }

    @Test func aGroupsIconIsItsOwn() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let url = folder.url.appending(path: "icon.png")
        try png().write(to: url)
        prompts.images = [url]
        let group = try icon(1, controller)
        group.chooseImage()
        guard case .group(let state) = controller.editing.state.rows[1] else {
            Issue.record("Row 1 isn't a group")
            return
        }
        #expect(state.hasExplicitIcon)
        #expect(group.icon != nil)
        #expect(group.makeMenu().items[1].isEnabled)
        #expect(try icon(3, controller).icon == nil)
        group.removeImage()
        #expect(group.icon == nil)
    }

    @Test func anIconThatIsNotAnImageIsReported() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        prompts.images = [Fixtures.url("NotSplits.txt")]
        try icon(0, controller).chooseImage()
        #expect(prompts.iconFailures.map(\.file) == ["NotSplits.txt"])
        #expect(try icon(0, controller).icon == nil)
    }
}
