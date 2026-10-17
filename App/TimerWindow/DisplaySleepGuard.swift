import Foundation
import LiveSplitCore

/// Keeps the display awake while the timer runs, as a video player does while it plays (spec
/// §5.1), so neither the screen saver nor the lock that follows it hides a run. A paused, finished
/// or reset timer lets the display sleep again. The Mac can still be slept or locked by hand.
@MainActor
final class DisplaySleepGuard {
    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    private var activity: NSObjectProtocol?

    init(begin: @escaping () -> NSObjectProtocol, end: @escaping (NSObjectProtocol) -> Void) {
        self.begin = begin
        self.end = end
    }

    /// An idle display-sleep assertion through `ProcessInfo`, the one video players hold.
    static var system: DisplaySleepGuard {
        DisplaySleepGuard(
            begin: {
                ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled, .userInitiated],
                    reason: "The timer is running")
            },
            end: { ProcessInfo.processInfo.endActivity($0) })
    }

    /// Whether the display is being kept awake.
    var isKeepingAwake: Bool { activity != nil }

    /// Keeps the display awake if `phase` is running, and lets it sleep otherwise. Call after
    /// anything that can change the phase; repeating a phase changes nothing.
    func update(phase: TimerPhase) {
        let running = phase == .running
        if running, activity == nil {
            activity = begin()
        } else if !running, let activity {
            end(activity)
            self.activity = nil
        }
    }
}
