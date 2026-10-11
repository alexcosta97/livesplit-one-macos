import AppKit

/// The menu bar and the timer's right-click menu (spec §7), built from the same items. Control
/// and Compare Against run their commands through `CommandRunner`. The other items have no
/// target, so they go up the responder chain to the window, the app and the app delegate.
@MainActor
final class TimerMenus: NSObject, NSMenuDelegate, NSMenuItemValidation {
    let mainMenu = NSMenu(title: "Main Menu")
    let contextMenu = NSMenu(title: "Timer")
    /// The menu bar's Window menu, for `NSApp.windowsMenu`, which lists the windows in it.
    let windowMenu = NSMenu(title: "Window")
    /// The menu bar's Help menu, for `NSApp.helpMenu`.
    let helpMenu = NSMenu(title: "Help")

    private let runner: CommandRunner
    private let readState: @MainActor () -> TimerMenuState
    private let shortcuts: @MainActor () -> Shortcuts
    private var controlMenus: [NSMenu] = []
    private var compareMenus: [NSMenu] = []

    init(
        runner: CommandRunner, readState: @escaping @MainActor () -> TimerMenuState,
        shortcuts: @escaping @MainActor () -> Shortcuts
    ) {
        self.runner = runner
        self.readState = readState
        self.shortcuts = shortcuts
        super.init()
        buildMainMenu()
        buildContextMenu()
        refreshShortcuts()
    }

    // MARK: Building

    private func item(
        _ title: String, _ action: Selector?, key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        return item
    }

    private func parent(_ title: String, _ submenu: NSMenu, identifier: String? = nil)
        -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        if let identifier { item.identifier = NSUserInterfaceItemIdentifier(identifier) }
        return item
    }

    /// A Control menu: one item per command, its tag the command's index. Titles and enabling
    /// come from `validateMenuItem(_:)`, key equivalents from `refreshShortcuts()`.
    private func controlMenu(identifierPrefix: String?) -> NSMenu {
        let menu = NSMenu(title: "Control")
        menu.delegate = self
        for (index, command) in ControlCommand.allCases.enumerated() {
            let item = NSMenuItem(
                title: command.name, action: #selector(runControlCommand(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            if let identifierPrefix {
                item.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + command.rawValue)
            }
            menu.addItem(item)
        }
        controlMenus.append(menu)
        return menu
    }

    /// An empty Compare Against menu: `menuNeedsUpdate(_:)` fills it each time it opens.
    private func compareAgainstMenu() -> NSMenu {
        let menu = NSMenu(title: "Compare Against")
        menu.delegate = self
        compareMenus.append(menu)
        return menu
    }

    private func buildMainMenu() {
        let app = NSMenu(title: "LiveSplit One")
        app.items = [
            item("About LiveSplit One for macOS", #selector(AppDelegate.showAbout(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), key: ","),
            .separator(),
            item("Hide LiveSplit One for macOS", #selector(NSApplication.hide(_:)), key: "h"),
            item(
                "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h",
                modifiers: [.option, .command]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit LiveSplit One for macOS", #selector(NSApplication.terminate(_:)), key: "q"),
        ]
        windowMenu.items = [
            item("Close", #selector(NSWindow.performClose(_:)), key: "w"),
            item("Minimize", #selector(NSWindow.miniaturize(_:)), key: "m"),
            .separator(),
            item("Always on Top", #selector(AppDelegate.toggleAlwaysOnTop(_:))),
        ]
        helpMenu.items = [item("Open Log Folder", #selector(AppDelegate.openLogFolder(_:)))]
        mainMenu.items = [
            parent("LiveSplit One", app),
            parent("Control", controlMenu(identifierPrefix: nil)),
            parent("Compare Against", compareAgainstMenu()),
            parent("Window", windowMenu),
            parent("Help", helpMenu),
        ]
    }

    private func buildContextMenu() {
        let alwaysOnTop = item("Always on Top", #selector(AppDelegate.toggleAlwaysOnTop(_:)))
        alwaysOnTop.identifier = NSUserInterfaceItemIdentifier("timer-always-on-top")
        contextMenu.items = [
            parent("Control", controlMenu(identifierPrefix: "timer-"), identifier: "timer-control"),
            parent("Compare Against", compareAgainstMenu(), identifier: "timer-compare-against"),
            .separator(),
            alwaysOnTop,
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), key: ","),
            item("Open Log Folder", #selector(AppDelegate.openLogFolder(_:))),
            item("About LiveSplit One for macOS", #selector(AppDelegate.showAbout(_:))),
            item("Quit", #selector(NSApplication.terminate(_:)), key: "q"),
        ]
    }

    /// Shows each Control command's first shortcut that a menu can show (spec §7). Call after the
    /// shortcuts change.
    func refreshShortcuts() {
        let shortcuts = shortcuts()
        for menu in controlMenus {
            for item in menu.items {
                let command = ControlCommand.allCases[item.tag]
                let shown = shortcuts.shortcuts(for: command).lazy
                    .compactMap(\.menuKeyEquivalent).first
                item.keyEquivalent = shown?.key ?? ""
                item.keyEquivalentModifierMask = shown?.modifiers ?? []
            }
        }
    }

    // MARK: Running

    /// Runs `command` if its item is enabled now. Returns whether it ran.
    @discardableResult
    func perform(_ command: ControlCommand, from source: CommandSource) -> Bool {
        guard let timerCommand = readState().command(for: command) else { return false }
        runner.run(timerCommand, from: source)
        return true
    }

    @objc func runControlCommand(_ sender: NSMenuItem) {
        perform(ControlCommand.allCases[sender.tag], from: .menu)
    }

    @objc func setComparison(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        runner.run(.setComparison(name), from: .menu)
    }

    @objc func setTimingMethod(_ sender: NSMenuItem) {
        guard let method = TimingMethod(rawValue: UInt8(sender.tag)) else { return }
        runner.run(.setTimingMethod(method), from: .menu)
    }

    // MARK: Validation and updates

    /// Gives a Control item its title and enabled state from the timer (spec §7).
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(runControlCommand(_:)) else { return true }
        let command = ControlCommand.allCases[item.tag]
        let state = readState()
        item.title = state.title(for: command)
        return state.isEnabled(command)
    }

    /// Fills Compare Against: the run's comparisons with a tick on the current one, then the
    /// timing methods below a separator (spec §7).
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard compareMenus.contains(menu) else { return }
        let state = readState()
        menu.removeAllItems()
        for name in state.comparisons {
            let item = NSMenuItem(
                title: name, action: #selector(setComparison(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = name == state.currentComparison ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for method in TimingMethod.allCases {
            let item = NSMenuItem(
                title: method.title, action: #selector(setTimingMethod(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(method.rawValue)
            item.state = method == state.timingMethod ? .on : .off
            menu.addItem(item)
        }
    }

    /// Menus show the Control shortcuts but never run them: `ShortcutKeys` does, only while the
    /// timer window is key (spec §7.2). Otherwise a plain `u` would run Undo Split while typing
    /// in the Settings window.
    func menuHasKeyEquivalent(
        _ menu: NSMenu, for event: NSEvent,
        target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
        action: UnsafeMutablePointer<Selector?>
    ) -> Bool {
        false
    }
}
