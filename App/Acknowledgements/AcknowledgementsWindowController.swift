import AppKit

/// The Acknowledgements window (spec §4.4), opened from Help ▸ Acknowledgements: the notices of
/// the third-party code in the app, to read, scroll and copy.
@MainActor
final class AcknowledgementsWindowController: NSWindowController {
    let textView: NSTextView

    init(text: String) {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        textView = NSTextView()
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        // The notices are laid out in 80 columns, with lines of = and - between them.
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = text
        textView.setAccessibilityIdentifier("acknowledgements-text")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
            defer: false)
        window.title = "Acknowledgements"
        window.contentView = scrollView
        window.contentMinSize = NSSize(width: 400, height: 300)
        window.setAccessibilityIdentifier("acknowledgements-window")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AcknowledgementsWindowController is built in code")
    }
}
