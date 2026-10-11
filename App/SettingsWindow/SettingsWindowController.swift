import AppKit

/// The Settings window (spec §7.3), opened with Settings… (⌘,).
@MainActor
final class SettingsWindowController: NSWindowController {
    let content: SettingsViewController

    init(store: SettingsStore, onChange: @escaping () -> Void) {
        content = SettingsViewController(store: store, onChange: onChange)
        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable]
        window.setAccessibilityIdentifier("settings-window")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is built in code")
    }
}
