import AppKit
import LiveSplitCore
import Testing

@testable import LiveSplitOne

/// Edit Splits… opening the editor and OK and Cancel ending it (spec §9), with no modal
/// session: `runModal` and `stopModal` only count their calls.
@MainActor
@Suite final class SplitsEditorPresenterTests {
    let content = TimerContent(lang: 0)
    let window: TimerWindowController
    let settings: SettingsStore
    let unified = RecordingUnifiedLog()
    let log: Log
    let folder: TemporaryFolder
    let prompts = ScriptedPrompts()
    var modalRuns = 0
    var modalStops = 0

    init() throws {
        folder = try TemporaryFolder()
        settings = SettingsStore(
            directory: folder.url.appending(path: "config", directoryHint: .isDirectory))
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        window = TimerWindowController(
            content: content, settings: settings, screens: { [screen] }, mainScreen: { screen },
            notices: NoticeQueue(schedule: { _, _ in }))
        log = Log(directory: folder.url.appending(path: "logs"), unified: unified)
        #expect(content.setRun(try SplitsFile.load(Fixtures.url("Grouped.lss"))) == .replaced)
        content.timer.writeWith { $0.markAsUnmodified() }
    }

    // Ends the window's display link, so they don't pile up across tests.
    isolated deinit {
        window.window.contentView = nil
    }

    private func makePresenter() -> SplitsEditorPresenter {
        SplitsEditorPresenter(
            content: content, window: window, prompts: prompts, log: log, lang: 0,
            runModal: { [unowned self] _ in modalRuns += 1 },
            stopModal: { [unowned self] in modalStops += 1 })
    }

    private var game: String { content.withRun { $0.gameName() } }

    private func lines(_ category: LogCategory) -> [String] {
        unified.entries.filter { $0.category == category }.map(\.message)
    }

    private func startAttempt() {
        let sink = EventSink(timer: content.timer, report: { _ in }, decideReset: { .discard })
        _ = sink.handleCommand(#"{"command":"start"}"#)
    }

    private func find<T: NSView>(_ identifier: String, in view: NSView) -> T? {
        if view.accessibilityIdentifier() == identifier, let match = view as? T { return match }
        for subview in view.subviews {
            if let match: T = find(identifier, in: subview) { return match }
        }
        return nil
    }

    @Test func editSplitsOpensTheEditorInAModalWindow() throws {
        let presenter = makePresenter()
        presenter.open()
        defer { presenter.editorWindow?.close() }
        #expect(presenter.isOpen)
        #expect(modalRuns == 1)
        let editor = try #require(presenter.editorWindow)
        #expect(editor.title == "Edit Splits")
        #expect(editor.accessibilityIdentifier() == "splits-editor")
        #expect(editor.styleMask == [.titled, .closable, .resizable])
        let controller = try #require(presenter.controller)
        #expect(editor.contentViewController === controller)
        #expect(controller.editing.state.game == game)
    }

    @Test func theEditorOpensWithTheRunsLinkedLayout() throws {
        let linking = SplitsEditing(run: content.withRun { $0.clone() }, lang: 0)
        linking.setLinkedLayout(.path("/tmp/Linked.ls1l"))
        #expect(content.setRun(linking.finish()) == .replaced)
        let presenter = makePresenter()
        presenter.open()
        defer { presenter.editorWindow?.close() }
        #expect(presenter.controller?.linkedLayout == .path("/tmp/Linked.ls1l"))
    }

    @Test func okReplacesTheRunWithTheEditedOneAndLogsIt() throws {
        let presenter = makePresenter()
        presenter.open()
        let controller = try #require(presenter.controller)
        controller.editing.setGame("X")
        presenter.applyOK()
        #expect(game == "X")
        #expect(content.hasUnsavedChanges)
        #expect(!presenter.isOpen)
        #expect(modalStops == 1)
        #expect(presenter.editorWindow == nil)
        #expect(lines(.timer) == ["Edited the splits"])
    }

    @Test func okWithNoEditsLeavesTheSplitsSaved() throws {
        let presenter = makePresenter()
        presenter.open()
        presenter.applyOK()
        #expect(!content.hasUnsavedChanges)
        #expect(!presenter.isOpen)
        #expect(modalStops == 1)
        #expect(lines(.timer).isEmpty)
        #expect(lines(.error).isEmpty)
    }

    @Test func okThroughTheButtonAppliesTheEdits() throws {
        let presenter = makePresenter()
        presenter.open()
        let controller = try #require(presenter.controller)
        controller.editing.setGame("Y")
        controller.okPressed(nil)
        #expect(game == "Y")
        #expect(!presenter.isOpen)
    }

    private func reset() {
        let sink = EventSink(timer: content.timer, report: { _ in }, decideReset: { .save })
        _ = sink.handleCommand(#"{"command":"reset","saveAttempt":true}"#)
    }

    private static let attemptStartedMessage =
        "An attempt was started while the splits editor was open, so these changes can't be "
        + "applied. Choose Cancel, then edit the splits again."

    /// What a refused OK shows and logs, and that the window stays open with the edits.
    private func expectRefused(
        _ presenter: SplitsEditorPresenter, _ controller: SplitsEditorViewController
    ) throws {
        #expect(presenter.isOpen)
        #expect(modalStops == 0)
        #expect(presenter.controller === controller)
        #expect(controller.editing.state.game == "X")
        let message: NSTextField = try #require(find("editor-message", in: controller.view))
        #expect(!message.isHidden)
        #expect(message.stringValue == Self.attemptStartedMessage)
        #expect(
            lines(.error) == [
                "Couldn't apply the splits editor's changes: an attempt was started while it "
                    + "was open"
            ])
        #expect(lines(.timer).isEmpty)
    }

    /// An attempt started while the window was open, such as by a server (spec §9).
    @Test func okWhileAnAttemptRunsKeepsTheWindowTheEditsAndTheAttempt() throws {
        let presenter = makePresenter()
        presenter.open()
        defer { presenter.editorWindow?.close() }
        let controller = try #require(presenter.controller)
        controller.editing.setGame("X")
        startAttempt()
        presenter.applyOK()

        #expect(game != "X")
        #expect(content.phase == .running)
        try expectRefused(presenter, controller)
    }

    /// An attempt that started and was reset while the window was open added to the history
    /// and the attempt count, which the copy doesn't have, so OK stays refused (spec §9).
    @Test func okAfterAnAttemptStartedAndWasResetKeepsTheTimersRun() throws {
        let presenter = makePresenter()
        presenter.open()
        defer { presenter.editorWindow?.close() }
        let controller = try #require(presenter.controller)
        controller.editing.setGame("X")
        let attempts = content.withRun { $0.attemptCount() }
        startAttempt()
        reset()
        let before = content.lssText()
        #expect(content.withRun { $0.attemptCount() } == attempts + 1)

        presenter.applyOK()
        #expect(content.lssText() == before)
        #expect(content.withRun { $0.attemptCount() } == attempts + 1)
        #expect(game != "X")
        try expectRefused(presenter, controller)

        // It stays refused.
        presenter.applyOK()
        #expect(content.lssText() == before)
        #expect(presenter.isOpen)
    }

    @Test func aRefusedOKKeepsTheLinkedLayoutAndTheTimingMethodChosen() throws {
        let presenter = makePresenter()
        presenter.open()
        defer { presenter.editorWindow?.close() }
        let controller = try #require(presenter.controller)
        let popUp: NSPopUpButton = try #require(find("editor-layout", in: controller.view))
        popUp.selectItem(withTitle: "Default Layout")
        _ = popUp.sendAction(popUp.action, to: popUp.target)
        let timing: NSSegmentedControl = try #require(
            find("editor-timing-method", in: controller.view))
        timing.selectedSegment = 1
        _ = timing.sendAction(timing.action, to: timing.target)
        #expect(controller.editing.state.timingMethod == .gameTime)
        startAttempt()
        presenter.applyOK()
        #expect(controller.linkedLayout == .defaultLayout)
        #expect(controller.editing.state.timingMethod == .gameTime)
        #expect(timing.selectedSegment == 1)
    }

    @Test func cancelDiscardsTheEdits() throws {
        let presenter = makePresenter()
        presenter.open()
        let controller = try #require(presenter.controller)
        controller.editing.setGame("X")
        controller.cancelPressed(nil)
        #expect(game != "X")
        #expect(!content.hasUnsavedChanges)
        #expect(!presenter.isOpen)
        #expect(modalStops == 1)
        #expect(presenter.editorWindow == nil)
        #expect(unified.entries.filter { $0.category != .app }.isEmpty)
    }

    @Test func theCloseButtonIsCancel() throws {
        let presenter = makePresenter()
        presenter.open()
        let editor = try #require(presenter.editorWindow)
        try #require(presenter.controller).editing.setGame("X")
        #expect(editor.delegate?.windowShouldClose?(editor) == false)
        #expect(game != "X")
        #expect(!presenter.isOpen)
        #expect(modalStops == 1)
    }

    @Test func escapeIsCancel() throws {
        let presenter = makePresenter()
        presenter.open()
        let controller = try #require(presenter.controller)
        controller.editing.setGame("X")
        controller.cancelOperation(nil)
        #expect(game != "X")
        #expect(!presenter.isOpen)
        #expect(modalStops == 1)
    }

    /// Escape cancels the whole window even while a field or a cell is being edited (spec §9).
    /// A plain Escape isn't a key equivalent: the field editor gets it and sends
    /// `cancelOperation(_:)` up the responder chain, where the table would take it to end the
    /// cell's edit.
    @Test(arguments: ["editor-cell-split-0", "editor-cell-name-0", "editor-game"])
    func escapeIsCancelWhileEditing(_ identifier: String) throws {
        let presenter = makePresenter()
        presenter.open()
        defer { presenter.editorWindow?.close() }
        let editor = try #require(presenter.editorWindow)
        let controller = try #require(presenter.controller)
        let field: NSTextField = try #require(find(identifier, in: controller.view))
        #expect(editor.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor() as? NSTextView)
        fieldEditor.insertText("Typed", replacementRange: NSRange(location: 0, length: 0))

        fieldEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(!presenter.isOpen)
        #expect(modalStops == 1)
        #expect(!content.hasUnsavedChanges)
    }

    @Test func editSplitsOpensOneEditorAtATime() {
        let presenter = makePresenter()
        presenter.open()
        defer { presenter.editorWindow?.close() }
        let controller = presenter.controller
        presenter.open()
        #expect(modalRuns == 1)
        #expect(presenter.controller === controller)
    }

    @Test func editSplitsDoesNothingWhileAnAttemptIsInProgress() {
        startAttempt()
        let presenter = makePresenter()
        presenter.open()
        #expect(!presenter.isOpen)
        #expect(modalRuns == 0)
        #expect(presenter.editorWindow == nil)
    }

    @Test func theEditorOpensAgainAfterOK() {
        let presenter = makePresenter()
        presenter.open()
        presenter.applyOK()
        presenter.open()
        defer { presenter.editorWindow?.close() }
        #expect(presenter.isOpen)
        #expect(modalRuns == 2)
    }
}
