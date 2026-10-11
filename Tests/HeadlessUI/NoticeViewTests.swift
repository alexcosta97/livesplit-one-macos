import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct NoticeViewTests {
    private func placed() -> (NoticeView, NSView) {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        let notice = NoticeView()
        notice.place(in: parent)
        return (notice, parent)
    }

    @Test func itIsHiddenUntilANoticeShows() {
        let (notice, _) = placed()
        #expect(notice.isHidden)
    }

    @Test func itShowsTheTextForAccessibility() throws {
        let (notice, _) = placed()
        notice.show("Connected to pc")

        #expect(!notice.isHidden)
        #expect(notice.text == "Connected to pc")
        let label = try #require(
            notice.subviews.first { $0.accessibilityIdentifier() == "overlay-notice" })
        #expect((label as? NSTextField)?.stringValue == "Connected to pc")
    }

    @Test func showingNothingHidesIt() {
        let (notice, _) = placed()
        notice.show("Connected to pc")
        notice.show(nil)
        #expect(notice.isHidden)
    }

    @Test func itDoesntTakeClicks() {
        let (notice, parent) = placed()
        notice.show("Connected to pc")
        parent.layoutSubtreeIfNeeded()
        let middle = CGPoint(x: notice.frame.midX, y: notice.frame.midY)
        #expect(notice.hitTest(middle) == nil)
    }

    @Test func itSitsAtTheBottomInsideTheWindow() {
        let (notice, parent) = placed()
        let long =
            "Couldn't read the settings, so the defaults are used. The old file is app.toml.bad."
        notice.show(long)
        parent.layoutSubtreeIfNeeded()
        #expect(notice.frame.minY >= 0 && notice.frame.minY < 20)
        #expect(notice.frame.minX >= 0 && notice.frame.maxX <= 300)
    }
}
