import LiveSplitCore

/// What the menus need to know about the timer, read under its read lock: which items are
/// enabled, their titles, and Compare Against's ticks (spec §7). Reading never changes the timer.
struct TimerMenuState: Equatable, Sendable {
    var phase: TimerPhase
    /// The current segment's index, as livesplit-core's `currentSplitIndex()` gives it: -1 with no
    /// attempt in progress, and the segment count once the run has ended, until it is reset.
    var splitIndex: Int
    var segmentCount: Int
    /// The run's comparisons, custom ones first, as livesplit-core lists them.
    var comparisons: [String]
    var currentComparison: String
    var timingMethod: TimingMethod

    /// Reads the state, holding the timer's read lock only while reading (spec §5.1).
    static func read(from timer: SharedTimerRef) -> TimerMenuState {
        var state: TimerMenuState!
        timer.readWith { timer in
            let run = timer.getRun()
            state = TimerMenuState(
                phase: TimerPhase(rawValue: timer.currentPhase()) ?? .notRunning,
                splitIndex: Int(timer.currentSplitIndex()),
                segmentCount: Int(run.len()),
                comparisons: (0..<run.comparisonsLen()).map { run.comparison($0) },
                currentComparison: timer.currentComparison(),
                timingMethod: TimingMethod(rawValue: timer.currentTimingMethod()) ?? .realTime)
        }
        return state
    }

    private var attemptInProgress: Bool { phase == .running || phase == .paused }

    /// Whether the command's menu item is enabled: items that can't be used are disabled, not
    /// hidden (spec §7). These follow livesplit-core's own checks, so an enabled item isn't
    /// rejected unless the timer changes first.
    func isEnabled(_ command: ControlCommand) -> Bool {
        switch command {
        case .startSplit: phase == .notRunning || phase == .running
        case .reset: phase != .notRunning
        case .undoSplit: phase == .ended || (attemptInProgress && splitIndex > 0)
        case .skipSplit: attemptInProgress && splitIndex + 1 < segmentCount
        case .pause: attemptInProgress
        case .undoAllPauses: phase != .notRunning
        }
    }

    /// The menu item's title: Start/Split and Pause/Resume follow the timer (spec §7).
    func title(for command: ControlCommand) -> String {
        switch command {
        case .startSplit: phase == .notRunning ? "Start" : "Split"
        case .reset: "Reset"
        case .undoSplit: "Undo Split"
        case .skipSplit: "Skip Split"
        case .pause: phase == .paused ? "Resume" : "Pause"
        case .undoAllPauses: "Undo All Pauses"
        }
    }

    /// The command to send now, or `nil` if the item is disabled. Pause sends `pause` or
    /// `resume`, never `togglePauseOrStart`, which would start a stopped timer (spec §7).
    func command(for command: ControlCommand) -> TimerCommand? {
        guard isEnabled(command) else { return nil }
        return switch command {
        case .startSplit: .splitOrStart
        case .reset: .reset
        case .undoSplit: .undoSplit
        case .skipSplit: .skipSplit
        case .pause: phase == .paused ? .resume : .pause
        case .undoAllPauses: .undoAllPauses
        }
    }
}
