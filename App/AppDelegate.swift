import AppKit

/// Starts the app and opens its single window. No storyboards: everything is
/// built in code (spec §4). Later issues replace the window's contents with
/// the timer (spec §6).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var window: NSWindow?

    /// The settings, read at launch (spec §11).
    private(set) var settings: SettingsStore?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        Log.shared.record(
            .app,
            "LiveSplit One for macOS \(AppVersion.current) started on macOS "
                + "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)")
        settings = SettingsStore(directory: ConfigFolder.current)
        let window = Self.makeWindow()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Open Log Folder (spec §7, §12.2). The menu items that send it come with #13.
    @objc func openLogFolder(_ sender: Any?) {
        let folder = Log.shared.directory
        guard !LogFolderOpener.system.open(folder) else { return }
        let alert = LogFolderAlert.make(folder: folder)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
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
