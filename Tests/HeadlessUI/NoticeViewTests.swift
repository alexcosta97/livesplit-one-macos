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

    private static let long =
        "Couldn't read the settings, so the defaults are used. The old file is app.toml.bad."

    private func label(of notice: NoticeView) throws -> NSTextField {
        try #require(notice.subviews.first as? NSTextField)
    }

    @Test func aLongNoticeWrapsInsideTheWindow() throws {
        let (notice, parent) = placed()
        notice.show(Self.long)
        parent.layoutSubtreeIfNeeded()

        let label = try label(of: notice)
        let oneLine = try #require(label.font).boundingRectForFont.height
        #expect(label.frame.height > oneLine * 1.5)
        #expect(notice.frame.width <= 300 - 12)
    }

    @Test func theWrapWidthFollowsTheWindow() throws {
        let (notice, parent) = placed()
        notice.show(Self.long)
        parent.layoutSubtreeIfNeeded()
        let narrow = notice.frame.width

        parent.setFrameSize(CGSize(width: 600, height: 500))
        parent.layoutSubtreeIfNeeded()

        #expect(try label(of: notice).preferredMaxLayoutWidth == 600 - 2 * (6 + 8))
        #expect(notice.frame.width > narrow)
        #expect(notice.frame.width <= 600 - 12)

        parent.setFrameSize(CGSize(width: 200, height: 500))
        parent.layoutSubtreeIfNeeded()

        #expect(try label(of: notice).preferredMaxLayoutWidth == 200 - 2 * (6 + 8))
        #expect(notice.frame.width <= 200 - 12)
    }

    @Test func theWrapWidthFollowsAResizedWindow() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 500), styleMask: [.borderless],
            backing: .buffered, defer: false)
        let parent = NSView()
        window.contentView = parent
        let notice = NoticeView()
        notice.place(in: parent)
        notice.show(Self.long)
        window.layoutIfNeeded()
        let narrow = notice.frame.width

        window.setFrame(CGRect(x: 0, y: 0, width: 600, height: 500), display: false)
        window.layoutIfNeeded()

        #expect(try label(of: notice).preferredMaxLayoutWidth == 600 - 2 * (6 + 8))
        #expect(notice.frame.width > narrow)
    }
}
