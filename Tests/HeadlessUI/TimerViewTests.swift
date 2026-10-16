import AppKit
import LiveSplitCore
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

    /// WindowServer sends a click on a fully transparent pixel to the window below, so a layout
    /// with a transparent background couldn't be dragged or resized from its empty parts. The
    /// view keeps a backing that is invisible but not transparent to it.
    @Test func theBackingIsntFullyTransparent() throws {
        let view = makeView()
        let alpha = try #require(view.layer?.backgroundColor?.alpha)
        #expect(alpha >= TimerView.hitTestableAlpha)
        #expect(TimerView.hitTestableAlpha >= 4.0 / 255)
        #expect(alpha <= 0.05, "the backing would show")
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

    @Test func theFrameRateIsLowWhileIdle() {
        #expect(TimerView.frameRate(idle: true) == TimerView.idleFrameRate)
        #expect(TimerView.frameRate(idle: false) == .default)
    }

    @Test func theDisplayLinkFollowsIdleness() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 500), styleMask: [.borderless],
            backing: .buffered, defer: false)
        let view = makeView()
        window.contentView = view
        #expect(view.preferredFrameRate == .default)
        view.drawFrame()
        #expect(view.preferredFrameRate == TimerView.idleFrameRate)
        view.content.markChanged()
        #expect(view.preferredFrameRate == .default)
        view.drawFrame()
        #expect(view.preferredFrameRate == TimerView.idleFrameRate)
        view.stopDisplayLink()
    }

    @Test func stoppingTheDisplayLinkEndsIt() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 500), styleMask: [.borderless],
            backing: .buffered, defer: false)
        let view = makeView()
        window.contentView = view
        #expect(view.preferredFrameRate != nil)

        view.stopDisplayLink()

        #expect(view.preferredFrameRate == nil)
        // A frame drawn by hand afterwards still works.
        view.drawFrame()
        #expect(view.framesDrawn == 1)
    }

    // AppKit traps on a frame that isn't finite and clamps a huge one, so the guard in
    // `drawFrame` can't be reached from here; this checks a huge view draws nothing.
    @Test func aHugeViewDrawsNothing() {
        let view = makeView(width: 1e20, height: 500)
        view.drawFrame()
        #expect(view.framesDrawn == 0)
    }

    @Test func aTallerLayoutAsksForATallerWindow() throws {
        let view = makeView()
        var hints: [CGSize] = []
        view.onSizeHint = { hints.append($0) }
        view.drawFrame()
        #expect(hints.isEmpty)

        view.content.layout.push(BlankSpaceComponent().intoGeneric())
        view.content.markChanged()
        view.drawFrame()

        #expect(hints.count == 1)
        let hint = try #require(hints.first)
        #expect(hint.width == 300)
        #expect(hint.height > 500)
    }
}
