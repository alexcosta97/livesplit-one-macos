import AppKit

/// The timer window (spec §6): borderless, moved by dragging anywhere in it, resized from its
/// edges.
final class TimerWindow: NSWindow {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect, styleMask: [.borderless, .resizable], backing: .buffered,
            defer: false)
        // For the Window menu, Mission Control and accessibility; it has no title bar to show it.
        title = "LiveSplit One"
        setAccessibilityIdentifier("timer-window")
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        // A layout with a transparent background shows what is behind the window.
        isOpaque = false
        backgroundColor = .clear
        minSize = WindowPlacement.minimumSize
    }

    // A borderless window can't become key unless it says so. The timer needs key focus for its
    // keyboard shortcuts and menus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Always on Top (spec §6): above other apps' windows.
    func setAlwaysOnTop(_ on: Bool) {
        level = on ? .floating : .normal
    }
}
