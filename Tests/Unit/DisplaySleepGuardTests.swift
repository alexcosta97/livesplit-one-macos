import Foundation
import LiveSplitCore
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct DisplaySleepGuardTests {
    /// Records the activities begun and ended, standing in for `ProcessInfo`.
    @MainActor
    final class Activities {
        var begun: [NSObject] = []
        var ended: [NSObject] = []
        var held: Int { begun.count - ended.count }

        func makeGuard() -> DisplaySleepGuard {
            DisplaySleepGuard(
                begin: {
                    let activity = NSObject()
                    self.begun.append(activity)
                    return activity
                },
                end: { self.ended.append($0 as! NSObject) })
        }
    }

    @Test func aRunningTimerKeepsTheDisplayAwake() {
        let activities = Activities()
        let sleepGuard = activities.makeGuard()
        sleepGuard.update(phase: .running)
        #expect(activities.held == 1)
        #expect(sleepGuard.isKeepingAwake)
    }

    @Test func theDisplayCanSleepOnceTheTimerStopsRunning() {
        for phase in [TimerPhase.paused, .ended, .notRunning] {
            let activities = Activities()
            let sleepGuard = activities.makeGuard()
            sleepGuard.update(phase: .running)
            sleepGuard.update(phase: phase)
            #expect(activities.held == 0)
            #expect(activities.ended == activities.begun)
            #expect(!sleepGuard.isKeepingAwake)
        }
    }

    @Test func aTimerThatIsntRunningNeverHoldsTheDisplay() {
        let activities = Activities()
        let sleepGuard = activities.makeGuard()
        for phase in [TimerPhase.notRunning, .paused, .ended] { sleepGuard.update(phase: phase) }
        #expect(activities.begun.isEmpty)
    }

    /// `changed` runs after every command and event, so most updates repeat the phase.
    @Test func repeatedUpdatesHoldOneActivity() {
        let activities = Activities()
        let sleepGuard = activities.makeGuard()
        sleepGuard.update(phase: .running)
        sleepGuard.update(phase: .running)
        #expect(activities.begun.count == 1)
        sleepGuard.update(phase: .paused)
        sleepGuard.update(phase: .paused)
        #expect(activities.ended.count == 1)
        sleepGuard.update(phase: .running)
        #expect(activities.held == 1)
        #expect(activities.begun.count == 2)
    }

    @Test func itFollowsTheRealTimer() {
        let activities = Activities()
        let sleepGuard = activities.makeGuard()
        let content = TimerContent(lang: 0)
        content.timer.writeWith { $0.start() }
        sleepGuard.update(phase: content.phase)
        #expect(sleepGuard.isKeepingAwake)
        content.timer.writeWith { $0.pause() }
        sleepGuard.update(phase: content.phase)
        #expect(!sleepGuard.isKeepingAwake)
    }
}
