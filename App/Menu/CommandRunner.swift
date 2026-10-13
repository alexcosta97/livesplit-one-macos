import Foundation
import LiveSplitCore
import Synchronization

/// Where a command from the menus or the keyboard came from, for the log (spec §12.1). Server
/// commands are logged by `ServerClient`, under Connection.
enum CommandSource: String, Sendable {
    case menu = "the menu"
    case keyboard = "the keyboard"
    /// The reset that quitting sends for an attempt in progress (spec §7.1).
    case quit = "quitting"
}

/// Runs the menus' and the keyboard's commands through the app's one event-reporting command
/// sink (spec §5.1, §7), on a serial background queue: a reset with new best times waits for
/// `decideReset` on the command's thread, which must never be the main thread (§5.3).
final class CommandRunner: Sendable {
    /// The app's one sink. `ServerClient` runs the server's messages through it on its own queue
    /// (spec §8.2).
    let sink: EventSink
    private let eventObserver: EventObserver
    private let queue = DispatchQueue(label: "dev.alexcosta.livesplit-one-macos.commands")
    private let preference: ResetPreference
    private let epoch: Epoch
    private let changed: @MainActor @Sendable () -> Void
    private let log: Log

    /// `changed` runs on the main actor after each command and each event, so the window shows
    /// the change at once (`TimerContent.markChanged()`). `ask` shows the reset question, on the
    /// main actor; `remember` stores the answer to *Yes* or *No* as the setting (spec §7.1).
    /// `answered` is called on the command's thread once the answer is back, so tests can hold
    /// that thread there.
    init(
        timer: SharedTimerRef, resetSavesBestTimes: Bool?, log: Log = .shared,
        changed: @escaping @MainActor @Sendable () -> Void,
        ask: @escaping @MainActor @Sendable () -> ResetAnswer = { ResetQuestion.ask() },
        remember: @escaping @MainActor @Sendable (Bool) -> Void,
        answered: @escaping @Sendable () -> Void = {}
    ) {
        let preference = ResetPreference(resetSavesBestTimes)
        let epoch = Epoch()
        let eventObserver = EventObserver()
        self.epoch = epoch
        self.eventObserver = eventObserver
        self.preference = preference
        self.changed = changed
        self.log = log
        sink = EventSink(
            timer: timer,
            // Runs on the command's thread: hand over and return at once.
            report: { result in
                if case .event(let event?) = result { eventObserver.value?(event) }
                Task { @MainActor in changed() }
            },
            // Runs on the command's thread, which waits for the answer (spec §5.3).
            decideReset: {
                if let saves = preference.value { return saves ? .save : .discard }
                // Commands queued before the answer waited behind the question and are dropped
                // (spec §7.1). The epoch moves on the main actor, as soon as the question is
                // answered, so a command sent from then on, such as a shortcut handled right
                // after the alert closes, runs.
                let answer = Self.waitOnMain {
                    let answer = ask()
                    epoch.bump()
                    return answer
                }
                answered()
                switch answer {
                case .yes:
                    // Set here as well, so a reset right after doesn't ask again before the
                    // main actor has remembered it.
                    preference.value = true
                    Task { @MainActor in remember(true) }
                    return .save
                case .no:
                    preference.value = false
                    Task { @MainActor in remember(false) }
                    return .discard
                case .dontReset:
                    return .cancel
                }
            })
    }

    /// Runs `body` on the main actor and waits for it on this thread, which is never the main
    /// thread: commands run on the command queue.
    ///
    /// `body` runs from a run loop block, not a `Task` or a main queue block: the reset question
    /// runs a modal loop, and while one main queue block runs no other main queue block does, so
    /// from a `Task` every other main-actor job, such as the window being told of a change, waits
    /// until the question is answered. A run loop block is no main queue block, so those jobs
    /// keep running. That also means another alert, or this question again, could open over an
    /// open question; that is accepted.
    static func waitOnMain<T: Sendable>(_ body: @escaping @MainActor @Sendable () -> T) -> T {
        precondition(!Thread.isMainThread)
        let result = Mutex<T?>(nil)
        let done = DispatchSemaphore(value: 0)
        performOnMainRunLoop {
            let value = body()
            result.withLock { $0 = value }
            done.signal()
        }
        done.wait()
        return result.withLock { $0! }
    }

    /// Runs `body` on the main actor from a run loop block, without waiting for it. Work that
    /// runs a modal loop, such as an alert, uses this rather than a `Task` for the reason given
    /// at `waitOnMain`.
    static func performOnMainRunLoop(_ body: @escaping @MainActor @Sendable () -> Void) {
        // The CF calls are thread-safe; `RunLoop` isn't documented to be.
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated { body() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    /// Runs `command` on the queue, logs it with its source and reply, tells the window, then
    /// calls `completion` with the reply, or with nil if the command was dropped because it
    /// waited behind the reset question. `completion` runs on the command queue, so it must
    /// return quickly and must never block or wait on another command, which would wait forever.
    func run(
        _ command: TimerCommand, from source: CommandSource,
        completion: (@Sendable (String?) -> Void)? = nil
    ) {
        let json = command.json
        let name = command.logName
        let queued = epoch.value
        queue.async { [sink, log, changed, epoch] in
            guard epoch.value == queued else {
                log.record(
                    .timer,
                    "\(name) from \(source.rawValue) dropped: it waited behind the reset question")
                completion?(nil)
                return
            }
            let reply = sink.handleCommand(json)
            log.record(.timer, "\(name) from \(source.rawValue): \(reply)")
            Task { @MainActor in changed() }
            completion?(reply)
        }
    }

    /// Calls `observer` with every event the sink reports, whatever sent the command, on the
    /// command's thread (spec §8.2). It must return at once and never call the sink
    /// (`EventSink.Report`). Rejections and events this version doesn't know aren't reported.
    func observeEvents(_ observer: @escaping @Sendable (TimerEvent) -> Void) {
        eventObserver.value = observer
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

/// Who is told of the sink's events, set once the server client exists.
private final class EventObserver: Sendable {
    private let stored = Mutex<(@Sendable (TimerEvent) -> Void)?>(nil)

    var value: (@Sendable (TimerEvent) -> Void)? {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }
}

/// Counts the answers to the reset question, so a command queued before one is told apart from
/// one queued after it.
private final class Epoch: Sendable {
    private let stored = Mutex(0)

    var value: Int { stored.withLock { $0 } }

    func bump() { stored.withLock { $0 += 1 } }
}
