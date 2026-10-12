import Foundation
import LiveSplitCore
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct TimerContentTests {
    private func sink(_ content: TimerContent) -> EventSink {
        EventSink(timer: content.timer, report: { _ in }, decideReset: { .cancel })
    }

    @Test func anIdleContentIsntRenderedAgain() {
        let content = TimerContent(lang: 0)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).image != nil)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).image == nil)
    }

    @Test func aRunningTimerDrawsWithinAFewRenders() {
        let content = TimerContent(lang: 0)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        _ = sink(content).handleCommand(#"{"command":"start"}"#)
        content.markChanged()
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        // Time moves on while it runs, so the next frame differs without markChanged().
        var drew = false
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.05)
            if content.render(pixelWidth: 300, pixelHeight: 500).image != nil { drew = true }
        }
        #expect(drew)
    }

    @Test func aPausedFrameDrawsOnceMarkedChanged() {
        let content = TimerContent(lang: 0)
        let sink = sink(content)
        _ = sink.handleCommand(#"{"command":"start"}"#)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        _ = sink.handleCommand(#"{"command":"pause"}"#)
        content.markChanged()
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).image != nil)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).image == nil)
    }

    @Test func aResizeDrawsWithoutAnUpdate() {
        let content = TimerContent(lang: 0)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        #expect(content.render(pixelWidth: 320, pixelHeight: 500).image != nil)
    }

    @Test func isIdleUntilTheTimerRuns() {
        let content = TimerContent(lang: 0)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        #expect(content.isIdle)
        _ = sink(content).handleCommand(#"{"command":"start"}"#)
        content.markChanged()
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        #expect(!content.isIdle)
    }

    @Test func markChangedTellsTheListener() {
        let content = TimerContent(lang: 0)
        var calls = 0
        content.onChange = { calls += 1 }
        content.markChanged()
        #expect(calls == 1)
    }

    /// A change to what the layout shows, with no phase change and no `markChanged()`.
    private func changeWithoutPhase(_ content: TimerContent) {
        content.layout.push(TitleComponent().intoGeneric())
    }

    @Test func aChangeNobodyMarkedIsntShownBeforeTheBackstop() {
        let content = TimerContent(lang: 0)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        changeWithoutPhase(content)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).image == nil)
    }

    @Test func theBackstopShowsAChangeNobodyMarked() async throws {
        let content = TimerContent(lang: 0)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        changeWithoutPhase(content)
        try await Task.sleep(for: TimerContent.idleRefresh + .milliseconds(100))
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).image != nil)
    }

    @Test func aPhaseChangeDrawsWithoutMarkChanged() {
        let content = TimerContent(lang: 0)
        let sink = sink(content)
        _ = sink.handleCommand(#"{"command":"start"}"#)
        content.markChanged()
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        // The one segment's split ends the run: Running to Ended.
        _ = sink.handleCommand(#"{"command":"split"}"#)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).image != nil)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).image == nil)
    }

    @Test func markChangedEndsIdleAtOnce() {
        let content = TimerContent(lang: 0)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        #expect(content.isIdle)
        content.markChanged()
        #expect(!content.isIdle)
    }

    @Test func aNewRunReplacesTheOldOneAndOpensUnmodified() throws {
        let content = TimerContent(lang: 0)
        #expect(content.setRun(try SplitsFile.load(Fixtures.url("GameTime.lss"))) == .replaced)
        #expect(content.withRun { Int($0.len()) } > 1)
        #expect(!content.hasUnsavedChanges)
    }

    @Test func aResetAttemptIsAnUnsavedChange() {
        let content = TimerContent(lang: 0)
        let sink = EventSink(timer: content.timer, report: { _ in }, decideReset: { .save })
        _ = sink.handleCommand(#"{"command":"splitOrStart"}"#)
        _ = sink.handleCommand(#"{"command":"reset","saveAttempt":true}"#)
        #expect(content.hasUnsavedChanges)
    }

    @Test func savingMarksTheRunSavedOnlyIfItDidntChange() {
        let content = TimerContent(lang: 0)
        let sink = EventSink(timer: content.timer, report: { _ in }, decideReset: { .save })
        _ = sink.handleCommand(#"{"command":"splitOrStart"}"#)
        _ = sink.handleCommand(#"{"command":"reset","saveAttempt":true}"#)
        let text = content.lssText()
        _ = sink.handleCommand(#"{"command":"splitOrStart"}"#)
        _ = sink.handleCommand(#"{"command":"reset","saveAttempt":true}"#)
        content.markSaved(text)
        #expect(content.hasUnsavedChanges)
        content.markSaved(content.lssText())
        #expect(!content.hasUnsavedChanges)
    }

    @Test func aNewLayoutIsDrawnAtOnce() throws {
        let content = TimerContent(lang: 0)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        content.setLayout(try LayoutFile.load(Fixtures.url("Dark.lsl")), keepingWindowSize: false)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).image != nil)
    }

    @Test func aNewLayoutGivesItsSizeHint() throws {
        let content = TimerContent(lang: 0)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        content.setLayout(try LayoutFile.load(Fixtures.url("Dark.lsl")), keepingWindowSize: false)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).sizeHint != nil)
    }

    @Test func keepingTheWindowSizeDropsTheNextHintOnly() throws {
        let content = TimerContent(lang: 0)
        _ = content.render(pixelWidth: 300, pixelHeight: 500)
        content.setLayout(try LayoutFile.load(Fixtures.url("Dark.lsl")), keepingWindowSize: true)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).sizeHint == nil)
        // A later change of height gives its hint again. The layout is what changes the height
        // here: GameTime.lss's extra segments don't change Dark.lsl's height, so a run can't
        // show it.
        content.setLayout(Layout.defaultLayout(0), keepingWindowSize: false)
        #expect(content.render(pixelWidth: 300, pixelHeight: 500).sizeHint != nil)
    }

    @Test func aRunWithNoSegmentsIsRefusedAndNothingChanges() {
        let content = TimerContent(lang: 0)
        let before = content.withRun { Int($0.len()) }
        // A new `Run` has no segments, and `SplitsFile.load` would reject such a file.
        let empty = Run()
        #expect(empty.len() == 0)
        #expect(content.setRun(empty) == .noSegments)
        #expect(content.withRun { Int($0.len()) } == before)
    }

    /// The check is made under the lock that replaces the run, in every phase but not running.
    @Test func aRunIsntReplacedWhileAnAttemptIsInProgress() throws {
        let content = TimerContent(lang: 0)
        let sink = EventSink(timer: content.timer, report: { _ in }, decideReset: { .save })
        _ = sink.handleCommand(#"{"command":"splitOrStart"}"#)
        #expect(content.phase == .running)
        let before = content.lssText()
        let other = try SplitsFile.load(Fixtures.url("GameTime.lss"))
        #expect(content.setRun(other) == .attemptInProgress)
        #expect(content.setRun(Run()) == .attemptInProgress)
        #expect(content.phase == .running)
        #expect(content.withRun { Int($0.len()) } == 1)

        _ = sink.handleCommand(#"{"command":"pause"}"#)
        #expect(content.phase == .paused)
        #expect(
            content.setRun(try SplitsFile.load(Fixtures.url("GameTime.lss"))) == .attemptInProgress)

        _ = sink.handleCommand(#"{"command":"resume"}"#)
        _ = sink.handleCommand(#"{"command":"splitOrStart"}"#)
        #expect(content.phase == .ended)
        #expect(
            content.setRun(try SplitsFile.load(Fixtures.url("GameTime.lss"))) == .attemptInProgress)
        _ = before

        _ = sink.handleCommand(#"{"command":"reset","saveAttempt":true}"#)
        #expect(content.setRun(try SplitsFile.load(Fixtures.url("GameTime.lss"))) == .replaced)
    }

    /// GameTime.lss with a `<LayoutPath>` element added, loaded as a run.
    private func run(linking layoutPath: String) throws -> Run {
        let folder = try TemporaryFolder()
        return try SplitsFile.load(try LinkedSplits.write(linking: layoutPath, in: folder))
    }

    @Test func theLinkedLayoutIsRead() throws {
        let content = TimerContent(lang: 0)
        #expect(content.linkedLayout == .none)
        content.setRun(try run(linking: "/Users/runner/Layouts/Dark.lsl"))
        #expect(content.linkedLayout == .path("/Users/runner/Layouts/Dark.lsl"))
        content.setRun(try run(linking: "?default"))
        #expect(content.linkedLayout == .defaultLayout)
    }
}
