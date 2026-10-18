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
    /// Opens, saves and closes splits and layouts (spec §7).
    private(set) var files: FileController?
    /// Opens the splits editor (spec §9).
    private(set) var splitsEditor: SplitsEditorPresenter?
    private(set) var settingsWindow: SettingsWindowController?
    private var shortcutKeys: ShortcutKeys?
    /// Decides whether the app may quit (spec §7.1).
    private var quitFlow: QuitFlow?
    /// The connection to a server (spec §8).
    private(set) var client: ServerClient?
    /// The Connect to Server sheet while it is open.
    private var connectWindow: NSWindow?

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
        // Tabbing items would join the Window menu once the Settings window opens (spec §7).
        NSWindow.allowsAutomaticWindowTabbing = false
        let content = TimerContent()
        let timerWindow = TimerWindowController.make(content: content, settings: settings)
        let runner = CommandRunner(
            timer: content.timer, resetSavesBestTimes: settings.settings.resetSavesBestTimes,
            changed: { [weak content] in content?.markChanged() },
            remember: { [weak self] in self?.rememberResetAnswer($0) })
        let picker = SystemFilePicker.make()
        let files = FileController(
            content: content, window: timerWindow, settings: settings, picker: picker,
            alerts: SystemFileAlerts())
        let splitsEditor = SplitsEditorPresenter(
            content: content, window: timerWindow,
            prompts: SystemSplitsEditorPrompts(picker: picker))
        self.splitsEditor = splitsEditor
        let client = ServerClient(
            sink: runner.sink, notices: { [weak timerWindow] in timerWindow?.notices.show($0) })
        runner.observeEvents { client.send($0) }
        self.client = client
        let menus = TimerMenus(
            runner: runner, readState: { TimerMenuState.read(from: content.timer) },
            shortcuts: { settings.settings.shortcuts }, files: files,
            connectionStatus: { client.status }, splitsEditor: splitsEditor)
        client.onStatusChange = { [weak menus] _ in menus?.refreshConnection() }
        NSApp.mainMenu = menus.mainMenu
        NSApp.windowsMenu = menus.windowMenu
        NSApp.helpMenu = menus.helpMenu
        timerWindow.timerView.menu = menus.contextMenu
        self.runner = runner
        self.menus = menus
        self.files = files
        let shortcutKeys = ShortcutKeys(
            window: timerWindow.window, shortcuts: { settings.settings.shortcuts },
            perform: { [weak menus] in menus?.perform($0, from: .keyboard) })
        shortcutKeys.install()
        self.shortcutKeys = shortcutKeys
        self.quitFlow = QuitFlow(
            content: content, runner: runner, files: files, splitsEditor: splitsEditor)
        files.launch(settingsOutcome: settings.loadOutcome) {
            timerWindow.window.makeKeyAndOrderFront(nil)
            // After making it key, which can happen at once: `follow` reads whether it is key.
            menus.follow(timerWindow)
        }
        self.timerWindow = timerWindow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Quit (spec §7.1): resets an attempt in progress, then asks about unsaved changes. It is
    /// refused while the splits editor is open (spec §9).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let quitFlow else { return .terminateNow }
        return quitFlow.shouldTerminate { NSApp.reply(toApplicationShouldTerminate: $0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timerWindow?.saveFrameIfPending()
        // Closes the socket with the normal close code (spec §8.3).
        client?.disconnect()
    }

    /// Connect to Server… or Disconnect from `<host>` (spec §8), from both menus.
    @objc func toggleConnection(_ sender: Any?) {
        guard let client else { return }
        guard case .notConnected = client.status else {
            client.disconnect()
            return
        }
        showConnectSheet()
    }

    /// Opens the Connect to Server sheet on the timer window, prefilled with the last address
    /// (spec §8.1). Connect saves the address as typed, then connects.
    private func showConnectSheet() {
        guard connectWindow == nil, let window, let settings, let client else { return }
        let sheet = ConnectSheet(
            prefill: settings.settings.lastServerURL,
            connect: { [weak self] server, text in
                settings.update { $0.lastServerURL = text }
                self?.closeConnectSheet()
                client.connect(to: server)
            },
            cancel: { [weak self] in self?.closeConnectSheet() })
        let sheetWindow = sheet.makeWindow()
        connectWindow = sheetWindow
        window.beginSheet(sheetWindow)
        NSApp.activate()
    }

    private func closeConnectSheet() {
        guard let connectWindow else { return }
        self.connectWindow = nil
        window?.endSheet(connectWindow)
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

    /// After *Yes* or *No* in the reset question: remembers it as the setting (spec §7.1).
    func rememberResetAnswer(_ saves: Bool) {
        settings?.update { $0.resetSavesBestTimes = saves }
        settingsChanged()
        // An open Settings window shows the setting as it is now (keeping a recording going).
        settingsWindow?.content.reload()
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
