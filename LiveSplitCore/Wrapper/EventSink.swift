import CLiveSplitCore
import Foundation

/// An event livesplit-core reports after a command (its `src/event.rs`).
public enum TimerEvent: UInt32, Sendable {
    case started = 0
    case splitted = 1
    case finished = 2
    case reset = 3
    case splitUndone = 4
    case splitSkipped = 5
    case paused = 6
    case resumed = 7
    case pausesUndone = 8
    case pausesUndoneAndResumed = 9
    case comparisonChanged = 10
    case timingMethodChanged = 11
    case gameTimeInitialized = 12
    case gameTimeSet = 13
    case gameTimePaused = 14
    case gameTimeResumed = 15
    case loadingTimesSet = 16
    case customVariableSet = 17
}

/// Why livesplit-core rejected a command (its `src/event.rs`).
public enum TimerError: UInt32, Sendable, Error {
    case unsupported = 0
    case busy = 1
    case runAlreadyInProgress = 2
    case noRunInProgress = 3
    case runFinished = 4
    case negativeTime = 5
    case cantSkipLastSplit = 6
    case cantUndoFirstSplit = 7
    case alreadyPaused = 8
    case notPaused = 9
    case comparisonDoesntExist = 10
    case gameTimeAlreadyInitialized = 11
    case gameTimeAlreadyPaused = 12
    case gameTimeNotPaused = 13
    case couldNotParseTime = 14
    case timerPaused = 15
    case runnerDecidedAgainstReset = 16
}

/// A command's result, as the sink reports it.
public enum CommandResult: Equatable, Sendable {
    case event(TimerEvent?)
    case error(TimerError?)

    /// Decodes livesplit-core's C API encoding: an event is 0 or more, an
    /// error `e` is `-1 - e`. Numbers this version doesn't know give `nil`.
    init(raw: Int32) {
        if raw >= 0 {
            self = .event(TimerEvent(rawValue: UInt32(raw)))
        } else {
            self = .error(TimerError(rawValue: UInt32(-1 - raw)))
        }
    }
}

/// What to do when a reset has new best times, as in LiveSplit One's dialog.
public enum ResetDecision: UInt8, Sendable {
    case save = 0
    case discard = 1
    case cancel = 2
}

/// The event-reporting command sink from core/ (spec §5.3). Not the generated
/// `CommandSink`, which wraps a plain timer and reports nothing.
///
/// `@unchecked Sendable` is sound because the only stored property is an
/// immutable pointer, and core's sink is thread-safe: `LsoHost` is `Send +
/// Sync` and `EventSink<LsoHost>` is `Sync`, so commands may run from any
/// thread.
public final class EventSink: @unchecked Sendable {
    /// Called with every command's result, on the thread that ran the command.
    ///
    /// Never call into any `EventSink` from here, on the thread this runs on:
    /// it would abort the app. Dispatch to another queue asynchronously
    /// instead. For a decided reset this runs while the reset question still
    /// counts as open, so other commands get `Busy`: return promptly and don't
    /// wait on other commands.
    public typealias Report = @Sendable (CommandResult) -> Void
    /// Called when a reset needs a decision, on the thread that ran the
    /// command, which waits for the answer.
    ///
    /// Never call into any `EventSink` from here, on the thread this runs on:
    /// it would abort the app. The reset question counts as open until the
    /// result is reported, so other commands get `Busy` meanwhile: don't wait
    /// on other commands.
    public typealias DecideReset = @Sendable () -> ResetDecision

    private final class Callbacks {
        let report: Report
        let decideReset: DecideReset
        init(report: @escaping Report, decideReset: @escaping DecideReset) {
            self.report = report
            self.decideReset = decideReset
        }
    }

    private let ptr: UnsafeMutableRawPointer

    public init(timer: SharedTimerRef, report: @escaping Report, decideReset: @escaping DecideReset)
    {
        precondition(timer.ptr != nil)
        let context = Unmanaged.passRetained(Callbacks(report: report, decideReset: decideReset))
        let host = LsoHost(
            context: context.toOpaque(),
            report: { context, raw in
                Unmanaged<Callbacks>.fromOpaque(context!).takeUnretainedValue()
                    .report(CommandResult(raw: raw))
            },
            decide_reset: { context in
                Unmanaged<Callbacks>.fromOpaque(context!).takeUnretainedValue()
                    .decideReset().rawValue
            },
            release: { context in
                Unmanaged<Callbacks>.fromOpaque(context!).release()
            }
        )
        ptr = LsoCommandSink_new(timer.ptr, host)
    }

    deinit {
        LsoCommandSink_drop(ptr)
    }

    /// Runs one server protocol message and returns the reply to send back.
    public func handleCommand(_ json: String) -> String {
        String(cString: LsoCommandSink_handle_command(ptr, json))
    }

    /// Encodes an event as LiveSplit One sends it to the server.
    public static func encodeEvent(_ event: TimerEvent) -> String {
        String(cString: LsoServerProtocol_encode_event(event.rawValue))
    }
}
