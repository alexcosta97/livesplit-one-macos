import AppKit
import LiveSplitCore

/// Opens the splits editor and applies OK (spec §9).
///
/// Edit Splits… opens a modal window, **Edit Splits**, on a copy of the timer's run. OK
/// replaces the run through `TimerContent.setRun(_:)`, the one way the run is replaced; Cancel,
/// Escape and the close button discard the copy. While it is open, nothing else may replace the
/// run (`TimerMenus` disables those items and the app refuses to quit), so OK never overwrites a
/// run opened meanwhile.
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

    /// The text below the table when an attempt keeps OK from replacing the run (spec §9).
    static let attemptInProgressMessage =
        "The splits can't change while an attempt is in progress. Reset it, or choose Cancel."

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

    /// Edit Splits…: does nothing while the editor is open or an attempt is in progress, which
    /// is when `FileController.canReplaceRun` is false (spec §7).
    func open() {
        guard !isOpen, content.phase == .notRunning else { return }
        let controller = SplitsEditorViewController(
            editing: SplitsEditing(run: content.withRun { $0.clone() }, lang: lang),
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
    /// window was open, keeps the window and the edits and says why (spec §9).
    func applyOK() {
        guard let controller else { return }
        let run = controller.editing.finish()
        let changed = run.hasBeenModified()
        switch content.setRun(run) {
        case .replaced:
            // `setRun` marked the content changed and collected the unused images.
            finish()
            if changed { log.record(.timer, "Edited the splits") }
        case .attemptInProgress:
            keepEditing(run, controller)
            controller.showMessage(Self.attemptInProgressMessage)
            log.record(
                .error, "Couldn't apply the splits editor's changes: an attempt is in progress")
        case .noSegments:
            // `RunEditor` always keeps a segment.
            assertionFailure("The splits editor made a run with no segments")
            keepEditing(run, controller)
        }
    }

    /// Goes on editing `run`: finishing it consumed the editor. The link the window keeps
    /// stays, and `run` carries it too.
    private func keepEditing(_ run: Run, _ controller: SplitsEditorViewController) {
        controller.editing = SplitsEditing(run: run, lang: lang)
        controller.refresh()
    }

    /// Cancel, Escape and the close button: the copy is dropped.
    private func cancel() {
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
