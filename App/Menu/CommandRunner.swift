import Foundation
import LiveSplitCore
import Synchronization

/// Where a command came from, for the log (spec §12.1). #14 adds the server.
enum CommandSource: String, Sendable {
    case menu = "the menu"
    case keyboard = "the keyboard"
}

/// Runs the menus' and the keyboard's commands through the app's one event-reporting command
/// sink (spec §5.1, §7), on a serial background queue: a reset with new best times waits for
/// `decideReset` on the command's thread, which must never be the main thread (§5.3).
final class CommandRunner: Sendable {
    private let sink: EventSink
    private let queue = DispatchQueue(label: "dev.alexcosta.livesplit-one-macos.commands")
    private let preference: ResetPreference
    private let changed: @MainActor @Sendable () -> Void
    private let log: Log

    /// `changed` runs on the main actor after each command and each event, so the window shows
    /// the change at once (`TimerContent.markChanged()`).
    init(
        timer: SharedTimerRef, resetSavesBestTimes: Bool?, log: Log = .shared,
        changed: @escaping @MainActor @Sendable () -> Void
    ) {
        let preference = ResetPreference(resetSavesBestTimes)
        self.preference = preference
        self.changed = changed
        self.log = log
        sink = EventSink(
            timer: timer,
            // Runs on the command's thread: hand over to the main actor and return at once.
            report: { _ in Task { @MainActor in changed() } },
            // Until #12 asks, *Ask* (nil) updates the best times, livesplit-core's default
            // (spec §7.1).
            decideReset: { (preference.value ?? true) ? .save : .discard })
    }

    /// Runs `command` on the queue, logs it with its source and reply, tells the window, then
    /// calls `completion` with the reply. `completion` runs on the command queue, so it must
    /// return quickly and must never block or wait on another command, which would wait forever.
    func run(
        _ command: TimerCommand, from source: CommandSource,
        completion: (@Sendable (String) -> Void)? = nil
    ) {
        let json = command.json
        let name = command.logName
        queue.async { [sink, log, changed] in
            let reply = sink.handleCommand(json)
            log.record(.timer, "\(name) from \(source.rawValue): \(reply)")
            Task { @MainActor in changed() }
            completion?(reply)
        }
    }

    /// What a reset with new best times does from now on (spec §7.1).
    func setResetSavesBestTimes(_ value: Bool?) {
        preference.value = value
    }
}

/// `reset_saves_best_times`, shared between the main actor, which changes it, and the command
/// queue, which reads it in `decideReset`.
private final class ResetPreference: Sendable {
    private let stored: Mutex<Bool?>

    init(_ value: Bool?) { stored = Mutex(value) }

    var value: Bool? {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }
}
