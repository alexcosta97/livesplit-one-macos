import AppKit

/// The Settings window (spec §7.3), opened with Settings… (⌘,).
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let content: SettingsViewController

    init(store: SettingsStore, onChange: @escaping () -> Void) {
        content = SettingsViewController(store: store, onChange: onChange)
        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable]
        window.setAccessibilityIdentifier("settings-window")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is built in code")
    }

    // Leaving the window, by clicking elsewhere or closing it, ends any recording, so the
    // recorder isn't waiting there to take ⌘W or ⌘Q when the window is next opened.
    func windowDidResignKey(_ notification: Notification) {
        content.stopRecording()
    }

    func windowWillClose(_ notification: Notification) {
        content.stopRecording()
    }
}
