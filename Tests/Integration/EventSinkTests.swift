import Foundation
import LiveSplitCore
import Testing

/// Collects results from whatever thread the sink reports on.
private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CommandResult] = []

    func append(_ value: CommandResult) { lock.withLock { values.append(value) } }
    var all: [CommandResult] { lock.withLock { values } }
}

/// Counts calls from whatever thread makes them.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

/// livesplit-core's timer phases, as `Timer.currentPhase()` returns them (the
/// generated bindings only give the raw number).
private enum TimerPhase: UInt8 {
    case notRunning = 0
    case running = 1
    case ended = 2
    case paused = 3
}

private func phase(of timer: SharedTimer) -> TimerPhase? {
    TimerPhase(rawValue: timer.read().timer().currentPhase())
}

/// A timer with the given number of segments (one is enough to start; a
/// second lets a split leave the attempt running).
private func makeTimer(segments: Int = 1) -> SharedTimer {
    let run = Run()
    for index in 1...segments {
        run.pushSegment(Segment("Segment \(index)"))
    }
    // `LiveSplitCore.Timer`, not Foundation's.
    return LiveSplitCore.Timer(run)!.intoShared()
}

@Suite struct EventSinkTests {
    @Test func aServerCommandStartsTheTimerAndReportsTheEvent() {
        let timer = makeTimer()
        let results = Results()
        let sink = EventSink(timer: timer, report: { results.append($0) }, decideReset: { .cancel })

        #expect(sink.handleCommand(#"{"command":"splitOrStart"}"#) == #"{"success":null}"#)
        #expect(results.all == [.event(.started)])
        #expect(phase(of: timer) == .running)
    }

    @Test func aRejectedCommandReportsTheError() {
        let results = Results()
        let sink = EventSink(
            timer: makeTimer(), report: { results.append($0) }, decideReset: { .cancel })

        let reply = sink.handleCommand(#"{"command":"split"}"#)
        #expect(reply == #"{"error":{"code":"NoRunInProgress"}}"#)
        #expect(results.all == [.error(.noRunInProgress)])
    }

    @Test func invalidJSONGetsInvalidCommand() {
        let sink = EventSink(timer: makeTimer(), report: { _ in }, decideReset: { .cancel })
        #expect(sink.handleCommand("not json").contains(#""code":"InvalidCommand""#))
    }

    @Test func theSinkKeepsTheTimerAlive() {
        let results = Results()
        let sink = EventSink(
            timer: makeTimer(), report: { results.append($0) }, decideReset: { .cancel })
        #expect(sink.handleCommand(#"{"command":"start"}"#) == #"{"success":null}"#)
    }

    /// Starts, waits and splits the first of two segments, which gives the
    /// attempt new best times, so a reset has to ask what to do.
    private func sinkWithNewBestTimes(
        report: @escaping EventSink.Report = { _ in },
        decideReset: @escaping EventSink.DecideReset
    ) -> (EventSink, SharedTimer) {
        let timer = makeTimer(segments: 2)
        let sink = EventSink(timer: timer, report: report, decideReset: decideReset)
        #expect(sink.handleCommand(#"{"command":"start"}"#) == #"{"success":null}"#)
        Thread.sleep(forTimeInterval: 0.01)
        #expect(sink.handleCommand(#"{"command":"split"}"#) == #"{"success":null}"#)
        return (sink, timer)
    }

    private func firstSegmentHasBestTime(_ timer: SharedTimer) -> Bool {
        timer.read().timer().getRun().segment(0).bestSegmentTime().realTime() != nil
    }

    @Test func cancellingTheResetDecisionKeepsTheRunGoing() {
        let results = Results()
        let asked = Counter()
        let (sink, timer) = sinkWithNewBestTimes(
            report: { results.append($0) },
            decideReset: {
                asked.increment()
                return .cancel
            })
        let before = results.all.count

        let reply = sink.handleCommand(#"{"command":"reset"}"#)

        #expect(reply == #"{"error":{"code":"RunnerDecidedAgainstReset"}}"#)
        #expect(Array(results.all.dropFirst(before)) == [.error(.runnerDecidedAgainstReset)])
        #expect(phase(of: timer) == .running)
        #expect(asked.value == 1)
    }

    @Test func savingTheResetDecisionKeepsTheTimes() {
        let results = Results()
        let asked = Counter()
        let (sink, timer) = sinkWithNewBestTimes(
            report: { results.append($0) },
            decideReset: {
                asked.increment()
                return .save
            })
        let before = results.all.count

        let reply = sink.handleCommand(#"{"command":"reset"}"#)

        #expect(reply == #"{"success":null}"#)
        #expect(Array(results.all.dropFirst(before)) == [.event(.reset)])
        #expect(phase(of: timer) == .notRunning)
        #expect(asked.value == 1)
        #expect(timer.read().timer().getRun().attemptHistoryLen() == 1)
        #expect(firstSegmentHasBestTime(timer))
    }

    @Test func discardingTheResetDecisionDropsTheTimes() {
        let results = Results()
        let asked = Counter()
        let (sink, timer) = sinkWithNewBestTimes(
            report: { results.append($0) },
            decideReset: {
                asked.increment()
                return .discard
            })
        let before = results.all.count

        let reply = sink.handleCommand(#"{"command":"reset"}"#)

        #expect(reply == #"{"success":null}"#)
        #expect(Array(results.all.dropFirst(before)) == [.event(.reset)])
        #expect(phase(of: timer) == .notRunning)
        #expect(asked.value == 1)
        #expect(!firstSegmentHasBestTime(timer))
    }

    @Test func droppingTheSinkReleasesTheCallbacks() {
        final class Probe: Sendable {}
        weak var weakProbe: Probe?
        do {
            let probe = Probe()
            weakProbe = probe
            let sink = EventSink(
                timer: makeTimer(), report: { _ in _ = probe }, decideReset: { .cancel })
            #expect(sink.handleCommand(#"{"command":"start"}"#) == #"{"success":null}"#)
            #expect(weakProbe != nil)
        }
        #expect(weakProbe == nil)
    }

    @Test func encodesEventsForTheServer() {
        #expect(EventSink.encodeEvent(.splitted) == #"{"event":"Splitted"}"#)
    }
}
