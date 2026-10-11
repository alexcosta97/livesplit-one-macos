import AppKit

/// Starts the app and opens the timer window. No storyboards: everything is
/// built in code (spec §4).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// The timer window (spec §6).
    private(set) var timerWindow: TimerWindowController?
    var window: NSWindow? { timerWindow?.window }

    /// The settings, read at launch (spec §11).
    private(set) var settings: SettingsStore?
    /// Runs the menus' and the keyboard's commands (spec §5.1, §7).
    private(set) var runner: CommandRunner?
    /// The menu bar and the right-click menu (spec §7).
    private(set) var menus: TimerMenus?
    private var settingsWindow: SettingsWindowController?

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
        let content = TimerContent()
        let timerWindow = TimerWindowController.make(content: content, settings: settings)
        let runner = CommandRunner(
            timer: content.timer, resetSavesBestTimes: settings.settings.resetSavesBestTimes,
            changed: { [weak content] in content?.markChanged() })
        let menus = TimerMenus(
            runner: runner, readState: { TimerMenuState.read(from: content.timer) },
            shortcuts: { settings.settings.shortcuts })
        NSApp.mainMenu = menus.mainMenu
        NSApp.windowsMenu = menus.windowMenu
        NSApp.helpMenu = menus.helpMenu
        timerWindow.timerView.menu = menus.contextMenu
        self.runner = runner
        self.menus = menus
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

    /// Always on Top (spec §6), from both menus.
    @objc func toggleAlwaysOnTop(_ sender: Any?) {
        timerWindow?.toggleAlwaysOnTop()
    }

    /// Open Log Folder (spec §7, §12.2), from both menus.
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

    /// About LiveSplit One for macOS, with the full version (spec §4.2).
    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "LiveSplit One for macOS",
            .applicationVersion: AppVersion.current,
            .version: "",
        ])
        NSApp.activate()
    }

    /// Settings… (spec §7.3).
    @objc func showSettings(_ sender: Any?) {
        guard let settings else { return }
        let controller =
            settingsWindow
            ?? SettingsWindowController(
                store: settings, onChange: { [weak self] in self?.settingsChanged() })
        settingsWindow = controller
        controller.content.reload()
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
        NSApp.activate()
    }

    /// After the Settings window saves a change: the command queue gets the reset setting, and
    /// the menus show the new shortcuts.
    func settingsChanged() {
        guard let settings else { return }
        runner?.setResetSavesBestTimes(settings.settings.resetSavesBestTimes)
        menus?.refreshShortcuts()
    }

    /// Ticks Always on Top. The Control and Compare Against items are `TimerMenus`'s to validate.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAlwaysOnTop(_:)) {
            item.state = settings?.settings.alwaysOnTop == true ? .on : .off
            return timerWindow != nil
        }
        return true
    }
}
