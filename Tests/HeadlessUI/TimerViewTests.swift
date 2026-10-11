import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct TimerViewTests {
    private func makeView(width: CGFloat = 300, height: CGFloat = 500) -> TimerView {
        let view = TimerView(content: TimerContent(lang: 0))
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return view
    }

    @Test func theFirstFrameShowsTheLayout() {
        let view = makeView()
        view.drawFrame()
        #expect(view.framesDrawn == 1)
        #expect(view.layer?.contents != nil)
    }

    @Test func anIdleTimerIsntDrawnAgain() {
        let view = makeView()
        view.drawFrame()
        view.drawFrame()
        view.drawFrame()
        #expect(view.framesDrawn == 1)
    }

    @Test func aResizedViewIsDrawnAgain() {
        let view = makeView()
        view.drawFrame()
        view.setFrameSize(CGSize(width: 320, height: 500))
        view.drawFrame()
        #expect(view.framesDrawn == 2)
    }

    @Test func anEmptyViewDrawsNothing() {
        let view = makeView(width: 0, height: 0)
        view.drawFrame()
        #expect(view.framesDrawn == 0)
    }

    @Test func dragsMoveTheWindow() {
        #expect(makeView().mouseDownCanMoveWindow)
    }

    @Test func theLayoutIsNamedForAccessibility() {
        let view = makeView()
        #expect(view.accessibilityIdentifier() == "timer-layout")
        #expect(view.accessibilityRole() == .image)
    }

    @Test func theDefaultRunIsLiveSplitOnes() {
        let run = TimerContent.defaultRun()
        #expect(run.len() == 1)
        #expect(run.segment(0).name() == "Time")
    }
}
