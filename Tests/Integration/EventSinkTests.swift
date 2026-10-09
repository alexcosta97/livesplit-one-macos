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

/// A timer with one segment, so it can start.
private func makeTimer() -> SharedTimer {
    let run = Run()
    run.pushSegment(Segment("One"))
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
        #expect(timer.read().timer().currentPhase() == 1)  // Running
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

    @Test func encodesEventsForTheServer() {
        #expect(EventSink.encodeEvent(.splitted) == #"{"event":"Splitted"}"#)
    }
}
