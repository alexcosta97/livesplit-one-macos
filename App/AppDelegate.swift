import AppKit

/// Starts the app and opens its single window. No storyboards: everything is
/// built in code (spec §4). Later issues replace the window's contents with
/// the timer (spec §6).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var window: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = Self.makeWindow()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// The empty timer window.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LiveSplit One"
        window.setAccessibilityIdentifier("timer-window")
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
