import AppKit

/// What quitting asks and does (spec §7.1): an attempt in progress is reset first, which may
/// ask the reset question, then unsaved changes are asked about. Kept apart from the app
/// delegate so the tests need not quit.
@MainActor
final class QuitFlow {
    private let content: TimerContent
    private let runner: CommandRunner
    private let files: FileController

    init(content: TimerContent, runner: CommandRunner, files: FileController) {
        self.content = content
        self.runner = runner
        self.files = files
    }

    /// The answer to `applicationShouldTerminate`. With an attempt in progress it queues a reset
    /// and returns `.terminateLater`; `reply` is then called once, on the main actor, with
    /// whether to quit. In any other case `reply` is never called.
    ///
    /// The main thread never waits for the command queue: the reset question runs on it while
    /// the queue waits.
    func shouldTerminate(
        reply: @escaping @MainActor (Bool) -> Void
    ) -> NSApplication.TerminateReply {
        guard content.phase != .notRunning else {
            return files.confirmUnsavedChanges() ? .terminateNow : .terminateCancel
        }
        // `nil` is a reset dropped behind the reset question; an error includes *Don't Reset*.
        runner.run(.reset, from: .menu) { [files] result in
            let reset = result?.hasPrefix(#"{"success""#) == true
            Task { @MainActor in
                reply(reset && files.confirmUnsavedChanges())
            }
        }
        return .terminateLater
    }
}
