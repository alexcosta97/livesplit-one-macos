import AppKit
import Foundation
import Testing

@testable import LiveSplitOne

/// The splits editor's buttons, pull-downs, OK and Cancel (spec §9), on `Grouped.lss` (rows A,
/// the group "Last", B and C; the comparison "Goal") unless a test says otherwise.
@MainActor
@Suite final class SplitsEditorButtonsTests {
    var oks = 0
    var cancels = 0
    /// The game name when `ok` was called.
    var gameAtOK: String?
    let prompts = ScriptedPrompts()
    private var controller: SplitsEditorViewController?

    private func makeController(fixture: String? = "Grouped.lss") throws
        -> SplitsEditorViewController
    {
        let run =
            try fixture.map { try SplitsFile.load(Fixtures.url($0)) } ?? TimerContent.defaultRun()
        let controller = SplitsEditorViewController(
            editing: SplitsEditing(run: run, lang: 0), linkedLayout: .none, currentLayout: nil,
            prompts: prompts,
            ok: { [unowned self] in
                oks += 1
                gameAtOK = self.controller?.editing.state.game
            },
            cancel: { [unowned self] in cancels += 1 })
        self.controller = controller
        _ = controller.view
        return controller
    }

    /// An offscreen window showing `controller`. The caller closes it.
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

    private func button(_ identifier: String, _ controller: SplitsEditorViewController) throws
        -> NSButton
    {
        try #require(find(identifier, in: controller.view))
    }

    private func popUp(_ identifier: String, _ controller: SplitsEditorViewController) throws
        -> NSPopUpButton
    {
        try #require(find(identifier, in: controller.view))
    }

    private func field(_ identifier: String, _ controller: SplitsEditorViewController) throws
        -> NSTextField
    {
        try #require(find(identifier, in: controller.view))
    }

    private func click(_ identifier: String, _ controller: SplitsEditorViewController) throws {
        let button = try button(identifier, controller)
        #expect(button.isEnabled)
        button.performClick(nil)
    }

    /// Chooses the item titled `title` in a pull-down, as a click on it does.
    private func choose(
        _ title: String, in identifier: String, _ controller: SplitsEditorViewController
    ) throws {
        let menu = try #require(try popUp(identifier, controller).menu)
        let index = menu.indexOfItem(withTitle: title)
        try #require(index > 0)
        menu.performActionForItem(at: index)
    }

    /// Selects `row` as a click on it does.
    private func select(_ rows: [Int], _ controller: SplitsEditorViewController) throws {
        var proposed = IndexSet()
        for row in rows {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: .leftMouseDown, location: .zero,
                    modifierFlags: proposed.isEmpty ? [] : .command, timestamp: 0,
                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            proposed.insert(row)
            let selected = controller.segmentTable.selection(
                proposed: proposed, event: event, clickedRow: row)
            controller.segmentTable.tableView.selectRowIndexes(
                selected, byExtendingSelection: false)
            proposed = selected
        }
    }

    /// Types `text` over what `field` holds, as the user does, so the field counts it as edited.
    private func type(_ text: String, into field: NSTextField) throws {
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange)
    }

    private func rowNames(_ controller: SplitsEditorViewController) -> [String] {
        controller.editing.state.rows.map {
            switch $0 {
            case .segment(let segment): segment.name
            case .group(let group): group.name
            }
        }
    }

    private func segmentNames(_ controller: SplitsEditorViewController) -> [String] {
        controller.editing.state.rows.compactMap {
            if case .segment(let segment) = $0 { segment.name } else { nil }
        }
    }

    @Test func aNewRunCanOnlyInsert() throws {
        let controller = try makeController(fixture: nil)
        #expect(try button("editor-insert-above", controller).isEnabled)
        #expect(try button("editor-insert-below", controller).isEnabled)
        #expect(!(try button("editor-remove", controller).isEnabled))
        #expect(!(try button("editor-move-up", controller).isEnabled))
        #expect(!(try button("editor-move-down", controller).isEnabled))
        let rows = controller.editing.state.rows.count
        try click("editor-insert-below", controller)
        #expect(controller.editing.state.rows.count == rows + 1)
        #expect(try button("editor-remove", controller).isEnabled)
    }

    @Test func moveDownSwapsTheNames() throws {
        let controller = try makeController(fixture: nil)
        try click("editor-insert-below", controller)
        controller.editing.setName("First", segment: 0)
        controller.editing.setName("Second", segment: 1)
        controller.refresh()
        try select([0], controller)
        #expect(try button("editor-move-down", controller).isEnabled)
        try click("editor-move-down", controller)
        #expect(segmentNames(controller) == ["Second", "First"])
    }

    @Test func removeSegmentRemovesIt() throws {
        let controller = try makeController()
        try select([0], controller)
        try click("editor-remove", controller)
        #expect(!segmentNames(controller).contains("A"))
    }

    @Test func createGroupIsDisabledWhenASelectedSegmentIsGrouped() throws {
        let controller = try makeController()
        try select([0, 2], controller)
        #expect(!(try button("editor-create-group", controller).isEnabled))
    }

    @Test func createGroupGroupsAndRemoveGroupUngroups() throws {
        let controller = try makeController()
        try select([0], controller)
        #expect(try button("editor-create-group", controller).isEnabled)
        try click("editor-create-group", controller)
        #expect(rowNames(controller).first == "A")
        guard case .group = controller.editing.state.rows[0] else {
            Issue.record("Row 0 isn't a group")
            return
        }
        #expect(controller.editing.state.rows.count == 5)
        try select([0], controller)
        #expect(try button("editor-remove-group", controller).isEnabled)
        try click("editor-remove-group", controller)
        #expect(controller.editing.state.rows.count == 4)
    }

    @Test func removeGroupRemovesTheSelectedGroup() throws {
        let controller = try makeController()
        try select([1], controller)
        try click("editor-remove-group", controller)
        #expect(controller.editing.state.rows.count == 3)
    }

    @Test func addComparisonAsksAgainWhenTheNameIsTaken() throws {
        let controller = try makeController()
        prompts.names = ["Goal", "Goal 2"]
        try click("editor-add-comparison", controller)
        #expect(prompts.titlesAsked == ["Add Comparison"])
        #expect(controller.editing.state.comparisonNames.contains("Goal 2"))
        // The prompt loops over refused names (spec §9); a second click asks again.
        prompts.names = ["Third"]
        try click("editor-add-comparison", controller)
        #expect(prompts.titlesAsked == ["Add Comparison", "Add Comparison"])
        #expect(
            controller.segmentTable.tableView.tableColumns.contains {
                $0.identifier.rawValue.hasPrefix("comparison")
            })
        #expect(controller.editing.state.comparisonNames == ["Goal", "Goal 2", "Third"])
    }

    @Test func renamingAComparisonAsksWithTheOldNameFilledIn() throws {
        let controller = try makeController()
        prompts.names = ["PB Goal"]
        try choose("Goal", in: "editor-rename-comparison", controller)
        #expect(prompts.titlesAsked == ["Rename Comparison"])
        #expect(prompts.prefillsAsked == ["Goal"])
        #expect(controller.editing.state.comparisonNames == ["PB Goal"])
        #expect(
            try popUp("editor-rename-comparison", controller).menu?.items.map(\.title)
                == ["Rename Comparison", "PB Goal"])
    }

    @Test func removingAComparisonDoesNotAsk() throws {
        let controller = try makeController()
        try choose("Goal", in: "editor-remove-comparison", controller)
        #expect(controller.editing.state.comparisonNames.isEmpty)
        #expect(prompts.titlesAsked.isEmpty)
        #expect(prompts.confirmationsAsked.isEmpty)
        #expect(!(try popUp("editor-rename-comparison", controller).isEnabled))
        #expect(!(try popUp("editor-remove-comparison", controller).isEnabled))
    }

    @Test func theComparisonPullDownsListTheNames() throws {
        let controller = try makeController()
        for id in ["editor-rename-comparison", "editor-remove-comparison"] {
            let popUp = try popUp(id, controller)
            #expect(popUp.pullsDown)
            #expect(popUp.isEnabled)
            #expect(popUp.menu?.items.map(\.title).dropFirst() == ["Goal"])
            // An item names its comparison by its represented object, not by its title.
            #expect(
                popUp.menu?.items.dropFirst().map { $0.representedObject as? String } == ["Goal"])
        }
        let other = try popUp("editor-other", controller)
        #expect(other.pullsDown)
        #expect(other.menu?.items.map(\.title) == ["Other", "Clear History…", "Clear Times…"])
    }

    @Test func clearTimesChangesNothingWhenDeclined() throws {
        let controller = try makeController()
        let before = controller.editing.state
        prompts.confirmations = [false]
        try choose("Clear Times…", in: "editor-other", controller)
        #expect(prompts.confirmationsAsked.count == 1)
        #expect(controller.editing.state == before)
    }

    @Test func clearTimesEmptiesTheTimesWhenConfirmed() throws {
        let controller = try makeController()
        prompts.confirmations = [true]
        try choose("Clear Times…", in: "editor-other", controller)
        for case .segment(let segment) in controller.editing.state.rows {
            #expect(segment.splitTime.isEmpty)
        }
        #expect(controller.editing.state.comparisonNames.isEmpty)
    }

    @Test func clearHistoryAsksFirst() throws {
        let controller = try makeController()
        prompts.confirmations = [false]
        try choose("Clear History…", in: "editor-other", controller)
        #expect(prompts.confirmationsAsked.count == 1)
    }

    @Test func cancelCancels() throws {
        let controller = try makeController()
        try click("editor-cancel", controller)
        #expect(cancels == 1)
        #expect(oks == 0)
    }

    // MARK: Ending an edit first

    @Test func aButtonAppliesANameBeingTypedBeforeMovingSegments() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        try select([3], controller)
        let c = try field("editor-cell-name-3", controller)
        #expect(window.makeFirstResponder(c))
        try type("Cee", into: c)
        try click("editor-move-up", controller)
        // C moved up past B, and it is C that has the new name.
        #expect(segmentNames(controller) == ["A", "Cee", "B"])
    }

    @Test func aButtonDoesNothingWhileATimeIsInvalid() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        try select([3], controller)
        let split = try field("editor-cell-split-3", controller)
        #expect(window.makeFirstResponder(split))
        try type("abc", into: split)
        let before = controller.editing.state
        try click("editor-move-up", controller)
        #expect(controller.editing.state == before)
        #expect(split.currentEditor() != nil)
        #expect(split.currentEditor()?.string == "abc")
    }

    @Test func aPullDownActionEndsEditingToo() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let split = try field("editor-cell-split-3", controller)
        #expect(window.makeFirstResponder(split))
        try type("abc", into: split)
        prompts.confirmations = [true]
        try choose("Clear Times…", in: "editor-other", controller)
        #expect(prompts.confirmationsAsked.isEmpty)
        #expect(split.currentEditor() != nil)
    }

    @Test func okAppliesTheGameBeingTypedFirst() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let game = try field("editor-game", controller)
        #expect(window.makeFirstResponder(game))
        try type("Typed Game", into: game)
        try click("editor-ok", controller)
        #expect(oks == 1)
        #expect(gameAtOK == "Typed Game")
    }

    @Test func okDoesNotCloseWhileATimeIsInvalid() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let offset = try field("editor-offset", controller)
        #expect(window.makeFirstResponder(offset))
        try type("abc", into: offset)
        try click("editor-ok", controller)
        #expect(oks == 0)
        #expect(offset.currentEditor() != nil)
    }

    @Test func okWithoutAWindowJustCallsOK() throws {
        let controller = try makeController()
        try click("editor-ok", controller)
        #expect(oks == 1)
    }

    // MARK: Icons, the timing switch and the minimum width

    private func png() throws -> Data {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func choosingASegmentIconAppliesANameBeingTypedFirst() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "icon.png")
        try png().write(to: url)
        prompts.images = [url]
        let c = try field("editor-cell-name-3", controller)
        #expect(window.makeFirstResponder(c))
        try type("Cee", into: c)
        let icon: IconButton = try #require(find("editor-cell-icon-0", in: controller.view))
        icon.chooseImage()
        #expect(segmentNames(controller) == ["A", "B", "Cee"])
        #expect(icon.icon != nil)
    }

    @Test func choosingTheGameIconDoesNothingWhileATimeIsInvalid() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let split = try field("editor-cell-split-3", controller)
        #expect(window.makeFirstResponder(split))
        try type("abc", into: split)
        let icon: IconButton = try #require(find("editor-game-icon", in: controller.view))
        let before = controller.editing.state.icon
        #expect(controller.editing.image(before) != nil)
        icon.chooseImage()
        #expect(prompts.imagesAsked == 0)
        #expect(split.currentEditor() != nil)
        icon.removeImage()
        #expect(split.currentEditor() != nil)
        #expect(controller.editing.state.icon == before)
        #expect(controller.editing.image(controller.editing.state.icon) != nil)
    }

    @Test func theTimingSwitchIsRefusedWhileATimeIsInvalid() throws {
        let controller = try makeController()
        let window = host(controller)
        defer { window.close() }
        let method = controller.editing.state.timingMethod
        let split = try field("editor-cell-split-3", controller)
        #expect(window.makeFirstResponder(split))
        try type("abc", into: split)
        let control: NSSegmentedControl = try #require(
            find("editor-timing-method", in: controller.view))
        control.selectedSegment = 1
        _ = control.sendAction(control.action, to: control.target)
        #expect(controller.editing.state.timingMethod == method)
        #expect(control.selectedSegment == (method == .realTime ? 0 : 1))
        #expect(split.currentEditor() != nil)
    }

    @Test func theButtonRowsFitAtTheMinimumWidth() throws {
        let controller = try makeController()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SplitsEditorViewController.minimumSize),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = controller
        window.setContentSize(SplitsEditorViewController.minimumSize)
        controller.view.layoutSubtreeIfNeeded()
        func controls(_ view: NSView) -> [NSView] {
            (view is NSButton ? [view] : []) + view.subviews.flatMap(controls)
        }
        let bounds = controller.view.bounds
        for control in controls(controller.buttonRows) {
            let frame = controller.view.convert(control.bounds, from: control)
            #expect(bounds.contains(frame), "\(control.accessibilityIdentifier()) \(frame)")
        }
        func ambiguous(_ view: NSView) -> Bool {
            view.hasAmbiguousLayout || view.subviews.contains(where: ambiguous)
        }
        #expect(!ambiguous(controller.view))
    }
}
