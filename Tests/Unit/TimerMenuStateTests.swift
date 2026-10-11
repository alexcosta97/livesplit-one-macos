import LiveSplitCore
import Testing

@testable import LiveSplitOne

@Suite struct TimerMenuStateTests {
    /// A run of three segments in `phase`, on segment `split`: -1 when not running, and 3, the
    /// segment count, once ended.
    private func state(_ phase: TimerPhase, split: Int = -1) -> TimerMenuState {
        TimerMenuState(
            phase: phase, splitIndex: split, segmentCount: 3,
            comparisons: ["Personal Best", "Best Segments"], currentComparison: "Personal Best",
            timingMethod: .realTime)
    }

    private func enabled(_ state: TimerMenuState) -> Set<ControlCommand> {
        Set(ControlCommand.allCases.filter { state.isEnabled($0) })
    }

    @Test func notRunningOnlyStarts() {
        #expect(enabled(state(.notRunning)) == [.startSplit])
    }

    @Test func runningOnTheFirstSegment() {
        #expect(
            enabled(state(.running, split: 0))
                == [.startSplit, .reset, .skipSplit, .pause, .undoAllPauses])
    }

    @Test func runningOnTheLastSegment() {
        #expect(
            enabled(state(.running, split: 2))
                == [.startSplit, .reset, .undoSplit, .pause, .undoAllPauses])
    }

    @Test func pausedCantSplit() {
        #expect(
            enabled(state(.paused, split: 1))
                == [.reset, .undoSplit, .skipSplit, .pause, .undoAllPauses])
    }

    @Test func endedCanUndoTheLastSplitAndReset() {
        #expect(enabled(state(.ended, split: 3)) == [.reset, .undoSplit, .undoAllPauses])
    }

    @Test func titlesFollowThePhase() {
        #expect(state(.notRunning).title(for: .startSplit) == "Start")
        #expect(state(.running, split: 0).title(for: .startSplit) == "Split")
        #expect(state(.running, split: 0).title(for: .pause) == "Pause")
        #expect(state(.paused, split: 0).title(for: .pause) == "Resume")
        #expect(state(.notRunning).title(for: .undoAllPauses) == "Undo All Pauses")
    }

    @Test func pauseSendsPauseOrResumeAndDisabledSendsNothing() {
        #expect(state(.running, split: 0).command(for: .pause) == .pause)
        #expect(state(.paused, split: 0).command(for: .pause) == .resume)
        #expect(state(.notRunning).command(for: .startSplit) == .splitOrStart)
        #expect(state(.notRunning).command(for: .reset) == nil)
    }

    @Test func resetIsEnabledAndSentWhilePausedAndOnceEnded() {
        for stopped in [state(.paused, split: 1), state(.ended, split: 3)] {
            #expect(stopped.isEnabled(.reset))
            #expect(stopped.title(for: .reset) == "Reset")
            #expect(stopped.command(for: .reset) == .reset)
        }
    }

    @Test func readingARealTimer() throws {
        let run = Run()
        run.pushSegment(Segment("One"))
        run.pushSegment(Segment("Two"))
        let core = LiveSplitCore.Timer(run)
        let timer = try #require(core).intoShared()

        let before = TimerMenuState.read(from: timer)
        #expect(before.phase == .notRunning)
        #expect(before.segmentCount == 2)
        #expect(before.currentComparison == "Personal Best")
        #expect(before.comparisons.starts(with: ["Personal Best", "Best Segments"]))
        #expect(before.timingMethod == .realTime)
        #expect(before.splitIndex == -1)

        let sink = EventSink(timer: timer, report: { _ in }, decideReset: { .cancel })
        _ = sink.handleCommand(#"{"command":"start"}"#)
        let after = TimerMenuState.read(from: timer)
        #expect(after.phase == .running)
        #expect(after.splitIndex == 0)

        _ = sink.handleCommand(#"{"command":"split"}"#)
        _ = sink.handleCommand(#"{"command":"split"}"#)
        let ended = TimerMenuState.read(from: timer)
        #expect(ended.phase == .ended)
        #expect(ended.splitIndex == 2)
    }
}
