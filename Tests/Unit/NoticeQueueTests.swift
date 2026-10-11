import Foundation
import Testing

@testable import LiveSplitOne

/// Runs scheduled actions when the test says, instead of after a delay.
@MainActor
private final class ManualClock {
    private(set) var delays: [TimeInterval] = []
    private var actions: [@MainActor @Sendable () -> Void] = []

    var schedule: NoticeQueue.Schedule {
        { [self] delay, action in
            delays.append(delay)
            actions.append(action)
        }
    }

    /// Runs the oldest scheduled action, as if its delay had passed.
    func advance() {
        guard !actions.isEmpty else { return }
        actions.removeFirst()()
    }
}

@MainActor
@Suite struct NoticeQueueTests {
    @Test func aNoticeShowsForFourSeconds() {
        let clock = ManualClock()
        let queue = NoticeQueue(schedule: clock.schedule)
        var shown: [String?] = []
        queue.onChange = { shown.append($0) }

        queue.show("Connected to pc")
        #expect(queue.current == "Connected to pc")
        #expect(clock.delays == [4])

        clock.advance()
        #expect(queue.current == nil)
        #expect(shown == ["Connected to pc", nil])
    }

    @Test func noticesShowOneAfterAnother() {
        let clock = ManualClock()
        let queue = NoticeQueue(schedule: clock.schedule)
        var shown: [String?] = []
        queue.onChange = { shown.append($0) }

        queue.show("First")
        queue.show("Second")
        #expect(queue.current == "First")
        #expect(queue.waiting == ["Second"])

        clock.advance()
        #expect(queue.current == "Second")
        clock.advance()
        #expect(shown == ["First", "Second", nil])
        #expect(clock.delays == [4, 4])
    }

    @Test func threeNoticesArrivingTogetherShowInOrder() {
        let clock = ManualClock()
        let queue = NoticeQueue(schedule: clock.schedule)
        var shown: [String?] = []
        queue.onChange = { shown.append($0) }

        queue.show("Couldn't read the settings")
        queue.show("Couldn't open the splits")
        queue.show("Connected to pc")
        #expect(queue.waiting == ["Couldn't open the splits", "Connected to pc"])

        clock.advance()
        #expect(queue.waiting == ["Connected to pc"])
        clock.advance()
        #expect(queue.waiting.isEmpty)
        #expect(queue.current == "Connected to pc")
        clock.advance()
        #expect(queue.current == nil)
        #expect(
            shown == [
                "Couldn't read the settings", "Couldn't open the splits", "Connected to pc", nil,
            ])
        #expect(clock.delays == [4, 4, 4])
    }

    @Test func afterDelayRunsTheActionOnTheMainActorLater() async {
        let start = ContinuousClock.now
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            NoticeQueue.afterDelay(0.05) {
                MainActor.assertIsolated()
                done.resume()
            }
        }
        #expect(ContinuousClock.now - start >= .milliseconds(50))
    }

    @Test func aNoticeAlreadyShownOrWaitingIsntRepeated() {
        let clock = ManualClock()
        let queue = NoticeQueue(schedule: clock.schedule)
        queue.show("Lost connection")
        queue.show("Lost connection")
        queue.show("Other")
        queue.show("Other")
        #expect(queue.current == "Lost connection")
        #expect(queue.waiting == ["Other"])
    }

    @Test func theSameNoticeCanShowAgainLater() {
        let clock = ManualClock()
        let queue = NoticeQueue(schedule: clock.schedule)
        queue.show("Connected to pc")
        clock.advance()
        queue.show("Connected to pc")
        #expect(queue.current == "Connected to pc")
    }
}
