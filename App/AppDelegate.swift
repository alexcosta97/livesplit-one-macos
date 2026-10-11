import AppKit

/// Starts the app and opens the timer window. No storyboards: everything is
/// built in code (spec §4).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The timer window (spec §6).
    private(set) var timerWindow: TimerWindowController?
    var window: NSWindow? { timerWindow?.window }

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
        let settings = SettingsStore(directory: ConfigFolder.current)
        self.settings = settings
        let timerWindow = TimerWindowController.make(content: TimerContent(), settings: settings)
        timerWindow.window.makeKeyAndOrderFront(nil)
        if let notice = LaunchNotices.settings(settings.loadOutcome) {
            timerWindow.notices.show(notice)
        }
        self.timerWindow = timerWindow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        timerWindow?.saveFrameIfPending()
    }

    /// Always on Top (spec §6). The menu items that send it come with #13.
    @objc func toggleAlwaysOnTop(_ sender: Any?) {
        timerWindow?.toggleAlwaysOnTop()
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
}
