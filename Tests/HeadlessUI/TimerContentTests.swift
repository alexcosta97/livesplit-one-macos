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
}
