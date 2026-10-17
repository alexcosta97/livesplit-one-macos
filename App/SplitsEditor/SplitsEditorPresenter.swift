import AppKit
import LiveSplitCore

/// Opens the splits editor and applies OK (spec §9).
///
/// Edit Splits… opens a modal window, **Edit Splits**, on a copy of the timer's run. OK
/// replaces the run through `TimerContent.setRun(_:ifAttemptCount:)`, the one way the run is
/// replaced; Cancel, Escape and the close button discard the copy. While it is open, nothing
/// else may replace the run (the modal session disables the timer's menus and the app refuses
/// to quit), so OK never overwrites a run opened meanwhile. A server can still start an
/// attempt, and OK is then refused.
@MainActor
final class SplitsEditorPresenter: NSObject, NSWindowDelegate {
    /// The editor's window while it is open, for the tests.
    private(set) var editorWindow: NSWindow?
    /// The editor while it is open, for the tests.
    private(set) var controller: SplitsEditorViewController?
    /// Whether the editor is open.
    private(set) var isOpen = false

    private let content: TimerContent
    private let window: TimerWindowController
    private let prompts: SplitsEditorPrompts
    private let log: Log
    private let lang: UInt8
    private let runModal: (NSWindow) -> Void
    private let stopModal: () -> Void

    /// The timer's attempt count when the copy was taken: an attempt started since, even one
    /// reset since, refuses OK (spec §9).
    private var attemptsAtOpen: UInt32 = 0

    /// The text below the table when an attempt started while the window was open (spec §9).
    static let attemptStartedMessage =
        "An attempt was started while the splits editor was open, so these changes can't be "
        + "applied. Choose Cancel, then edit the splits again."

    /// `runModal` shows the window and returns once `stopModal` was called; tests pass ones
    /// that don't start a modal session.
    init(
        content: TimerContent, window: TimerWindowController, prompts: SplitsEditorPrompts,
        log: Log = .shared, lang: UInt8 = TimerContent.systemLanguage,
        runModal: @escaping (NSWindow) -> Void = { NSApp.runModal(for: $0) },
        stopModal: @escaping () -> Void = { NSApp.stopModal() }
    ) {
        self.content = content
        self.window = window
        self.prompts = prompts
        self.log = log
        self.lang = lang
        self.runModal = runModal
        self.stopModal = stopModal
        super.init()
    }

    /// Edit Splits…: does nothing while the editor is open or an attempt is in progress
    /// (`TimerContent.canReplaceRun`, spec §7).
    func open() {
        guard !isOpen, content.canReplaceRun else { return }
        let (copy, attempts) = content.withRun { ($0.clone(), $0.attemptCount()) }
        attemptsAtOpen = attempts
        let controller = SplitsEditorViewController(
            editing: SplitsEditing(run: copy, lang: lang),
            linkedLayout: content.linkedLayout, currentLayout: window.layoutPath,
            prompts: prompts,
            ok: { [weak self] in self?.applyOK() },
            cancel: { [weak self] in self?.cancel() })
        let editor = NSWindow(contentViewController: controller)
        editor.styleMask = [.titled, .closable, .resizable]
        editor.title = "Edit Splits"
        editor.setAccessibilityIdentifier("splits-editor")
        editor.isReleasedWhenClosed = false
        editor.delegate = self
        editor.setContentSize(controller.preferredContentSize)
        editor.contentMinSize = SplitsEditorViewController.minimumSize
        center(editor)
        self.controller = controller
        editorWindow = editor
        isOpen = true
        runModal(editor)
    }

    /// Brings the editor's window to the front, for a Quit it refused (spec §9).
    func bringToFront() {
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    /// Centres `editor` on the timer window's screen.
    private func center(_ editor: NSWindow) {
        guard let screen = window.window.screen ?? NSScreen.main else {
            editor.center()
            return
        }
        let visible = screen.visibleFrame
        let size = editor.frame.size
        editor.setFrameOrigin(
            NSPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.midY - size.height / 2).rounded()))
    }

    /// What OK does, once editing has ended; internal so tests can call it without a modal
    /// session. It replaces the run and closes the window, or, if an attempt started while the
    /// window was open, whether it is still in progress or was reset, keeps the window and the
    /// edits and says why (spec §9).
    func applyOK() {
        guard let controller else { return }
        let run = controller.editing.finish()
        let changed = run.hasBeenModified()
        switch content.setRun(run, ifAttemptCount: attemptsAtOpen) {
        case .replaced:
            // `setRun` marked the content changed and collected the unused images.
            finish()
            if changed { log.record(.timer, "Edited the splits") }
        case .attemptInProgress:
            keepEditing(run, controller)
            controller.showMessage(Self.attemptStartedMessage)
            log.record(
                .error,
                "Couldn't apply the splits editor's changes: an attempt was started while it "
                    + "was open")
        case .noSegments:
            // `RunEditor` always keeps a segment, so this can't happen. `Timer.setRun` handed
            // `run` back refused, and `TimerContent.setRun` dropped it, so it can't be edited
            // again: the editor ends as Cancel ends it.
            log.record(
                .error, "Couldn't apply the splits editor's changes: the splits have no segments")
            assertionFailure("The splits editor made a run with no segments")
            cancel()
        }
    }

    /// Goes on editing `run`, which `setRun` didn't take: finishing it consumed the editor. The
    /// link the window keeps stays, and `run` carries it too. The timing method and the
    /// selection are the old editor's own, so they are set again on the new one.
    private func keepEditing(_ run: Run, _ controller: SplitsEditorViewController) {
        let old = controller.editing.state
        let editing = SplitsEditing(run: run, lang: lang)
        editing.selectTimingMethod(old.timingMethod)
        editing.apply(EditorSelection.restoring(old.rows))
        controller.editing = editing
        controller.refresh()
    }

    /// Cancel, Escape and the close button: the editor and its copy are freed.
    private func cancel() {
        controller?.editing.discard()
        finish()
    }

    private func finish() {
        guard let editor = editorWindow else { return }
        stopModal()
        editor.delegate = nil
        editor.close()
        editorWindow = nil
        controller = nil
        isOpen = false
    }

    /// The close button is Cancel.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }
}
