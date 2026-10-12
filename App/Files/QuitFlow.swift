import AppKit

/// What quitting asks and does (spec §7.1): an attempt in progress is reset first, which may
/// ask the reset question, then unsaved changes are asked about. Kept apart from the app
/// delegate so the tests need not quit.
@MainActor
final class QuitFlow {
    private let content: TimerContent
    private let runner: CommandRunner
    private let files: FileController
    /// Whether a quit is being decided, so a second request is cancelled rather than queuing
    /// another reset and another reply.
    private var pending = false

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
        guard !pending else { return .terminateCancel }
        // A Start queued just after this read can't lose more than an attempt that is
        // milliseconds old, so the phase isn't held against the queue.
        guard content.phase != .notRunning else {
            pending = true
            defer { pending = false }
            return files.confirmUnsavedChanges() ? .terminateNow : .terminateCancel
        }
        pending = true
        runner.run(.reset, from: .menu) { result in
            // `nil` is a reset dropped behind the reset question; an error includes *Don't
            // Reset*. A reset that found no attempt, because a queued one ran first, has
            // nothing left to ask about, so quitting goes on.
            let reset = Self.resetAllowsQuitting(result)
            // A run loop block, not a `Task`: the save question runs a modal loop.
            CommandRunner.performOnMainRunLoop { [self] in
                let quit = reset && files.confirmUnsavedChanges()
                pending = false
                reply(quit)
            }
        }
        return .terminateLater
    }

    nonisolated static func resetAllowsQuitting(_ result: String?) -> Bool {
        guard let result else { return false }
        return result.hasPrefix(#"{"success""#)
            || result == #"{"error":{"code":"NoRunInProgress"}}"#
    }
}
