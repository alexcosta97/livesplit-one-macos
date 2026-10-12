import AppKit

/// A menu that refuses to match a key press against its items' key equivalents. Belt and braces:
/// some macOS versions (26) match the menu bar's items without calling this, so what keeps the
/// Control shortcuts out of other windows is `TimerMenus.showsShortcuts`, which gives the items
/// key equivalents only while the timer window is key.
final class ShortcutDisplayMenu: NSMenu {
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }
}

/// The menu bar and the timer's right-click menu (spec §7), built from the same items. Control
/// and Compare Against run their commands through `CommandRunner`, and the Files items call
/// `FileController`. The other items have no target, so they go up the responder chain to the
/// window, the app and the app delegate.
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
    private let files: FileController
    /// Which recent files an Open Splits or Open Layout submenu lists.
    private enum RecentKind { case splits, layouts }
    private var recentMenus: [(menu: NSMenu, kind: RecentKind, identifierPrefix: String?)] = []
    private var controlMenus: [NSMenu] = []
    private var compareMenus: [NSMenu] = []
    /// Whether the Control items show their shortcuts: only while the timer window is key
    /// (spec §7). Then `ShortcutKeys` takes every Control shortcut before a menu sees it. In
    /// any other window the items have no key equivalents, so no menu can match a plain key
    /// typed there, such as `u` in the Settings window, on any macOS version.
    var showsShortcuts = false {
        didSet { if showsShortcuts != oldValue { refreshShortcuts() } }
    }

    init(
        runner: CommandRunner, readState: @escaping @MainActor () -> TimerMenuState,
        shortcuts: @escaping @MainActor () -> Shortcuts, files: FileController
    ) {
        self.runner = runner
        self.files = files
        self.readState = readState
        self.shortcuts = shortcuts
        super.init()
        buildMainMenu()
        buildContextMenu()
        refreshShortcuts()
    }

    /// Shows the shortcuts while `controller`'s window is key, from now on (spec §7).
    func follow(_ controller: TimerWindowController) {
        controller.onKeyChange = { [weak self] isKey in self?.showsShortcuts = isKey }
        showsShortcuts = controller.window.isKeyWindow
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
        let menu = ShortcutDisplayMenu(title: "Control")
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

    /// An empty Open Splits or Open Layout menu: `menuNeedsUpdate(_:)` fills it each time it
    /// opens. `identifierPrefix` is for the right-click menu's items, which have identifiers.
    private func recentMenu(_ kind: RecentKind, identifierPrefix: String?) -> NSMenu {
        let menu = NSMenu(title: kind == .splits ? "Open Splits" : "Open Layout")
        menu.delegate = self
        recentMenus.append((menu, kind, identifierPrefix))
        return menu
    }

    private func identified(_ item: NSMenuItem, _ identifier: String) -> NSMenuItem {
        item.identifier = NSUserInterfaceItemIdentifier(identifier)
        return item
    }

    /// The Files items, the same in both menus; the right-click menu's have identifiers.
    private func fileItems(identified: Bool) -> (splits: [NSMenuItem], layout: [NSMenuItem]) {
        func named(_ item: NSMenuItem, _ identifier: String) -> NSMenuItem {
            item.target = self
            return identified ? self.identified(item, "timer-" + identifier) : item
        }
        let splits = [
            parent(
                "Open Splits", recentMenu(.splits, identifierPrefix: identified ? "timer-" : nil),
                identifier: identified ? "timer-open-splits" : nil),
            named(
                item("Save Splits", #selector(saveSplits(_:)), key: "s"), "save-splits"),
            named(
                item(
                    "Save Splits As…", #selector(saveSplitsAs(_:)), key: "s",
                    modifiers: [.shift, .command]), "save-splits-as"),
            named(item("Close Splits", #selector(closeSplits(_:))), "close-splits"),
        ]
        let layout = [
            parent(
                "Open Layout", recentMenu(.layouts, identifierPrefix: identified ? "timer-" : nil),
                identifier: identified ? "timer-open-layout" : nil),
            named(item("Save Layout As…", #selector(saveLayoutAs(_:))), "save-layout-as"),
        ]
        return (splits, layout)
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
        let fileMenu = NSMenu(title: "File")
        let fileItems = fileItems(identified: false)
        fileMenu.items = fileItems.splits + [.separator()] + fileItems.layout
        mainMenu.items = [
            parent("LiveSplit One", app),
            parent("File", fileMenu),
            parent("Control", controlMenu(identifierPrefix: nil)),
            parent("Compare Against", compareAgainstMenu()),
            parent("Window", windowMenu),
            parent("Help", helpMenu),
        ]
    }

    private func buildContextMenu() {
        let alwaysOnTop = item("Always on Top", #selector(AppDelegate.toggleAlwaysOnTop(_:)))
        alwaysOnTop.identifier = NSUserInterfaceItemIdentifier("timer-always-on-top")
        let fileItems = fileItems(identified: true)
        let control = parent(
            "Control", controlMenu(identifierPrefix: "timer-"), identifier: "timer-control")
        let compare = parent(
            "Compare Against", compareAgainstMenu(), identifier: "timer-compare-against")
        var items: [NSMenuItem] = fileItems.splits
        items += [.separator(), control, compare, .separator()]
        items += fileItems.layout
        items += [.separator(), alwaysOnTop, .separator()]
        items += [
            item("Settings…", #selector(AppDelegate.showSettings(_:)), key: ","),
            item("Open Log Folder", #selector(AppDelegate.openLogFolder(_:))),
            item("About LiveSplit One for macOS", #selector(AppDelegate.showAbout(_:))),
            item("Quit", #selector(NSApplication.terminate(_:)), key: "q"),
        ]
        contextMenu.items = items
    }

    /// Shows each Control command's first shortcut that a menu can show while `showsShortcuts`
    /// is on, and none otherwise (spec §7). Call after the shortcuts change.
    func refreshShortcuts() {
        let shortcuts = shortcuts()
        for menu in controlMenus {
            for item in menu.items {
                let command = ControlCommand.allCases[item.tag]
                let shown =
                    showsShortcuts
                    ? shortcuts.shortcuts(for: command).lazy.compactMap(\.menuKeyEquivalent).first
                    : nil
                item.keyEquivalent = shown?.key ?? ""
                item.keyEquivalentModifierMask = shown?.modifiers ?? []
            }
        }
    }

    // MARK: Running

    /// Runs `command` if its item is enabled now. Returns whether it ran.
    @discardableResult
    func perform(_ command: ControlCommand, from source: CommandSource) -> Bool {
        // The timer can change between this check and the command running on the queue, such
        // as when two keys are pressed at once. That's harmless: livesplit-core rejects a
        // command that no longer applies, and the rejection is logged.
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

    // MARK: Files

    @objc func openSplits(_ sender: Any?) { files.openSplits() }

    @objc func openRecentSplits(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        files.openSplits(atPath: path)
    }

    @objc func clearRecentSplits(_ sender: Any?) { files.clearRecentSplits() }
    @objc func saveSplits(_ sender: Any?) { _ = files.saveSplits() }
    @objc func saveSplitsAs(_ sender: Any?) { _ = files.saveSplitsAs() }
    @objc func closeSplits(_ sender: Any?) { files.closeSplits() }
    @objc func openLayout(_ sender: Any?) { files.openLayout() }

    @objc func openRecentLayouts(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        files.openLayout(atPath: path)
    }

    @objc func clearRecentLayouts(_ sender: Any?) { files.clearRecentLayouts() }
    @objc func saveLayoutAs(_ sender: Any?) { files.saveLayoutAs() }

    // MARK: Validation and updates

    /// Gives a Control item its title and enabled state from the timer, and enables the Files
    /// items that replace the run (Open Splits' items, Close Splits) only while no attempt is in
    /// progress (spec §7).
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(runControlCommand(_:)):
            break
        case #selector(openSplits(_:)), #selector(openRecentSplits(_:)),
            #selector(clearRecentSplits(_:)), #selector(closeSplits(_:)):
            // Replacing the run would drop an attempt in progress (spec §7).
            return files.canReplaceRun
        default:
            return true
        }
        let command = ControlCommand.allCases[item.tag]
        let state = readState()
        item.title = state.title(for: command)
        return state.isEnabled(command)
    }

    /// Fills Compare Against: the run's comparisons with a tick on the current one, then the
    /// timing methods below a separator (spec §7).
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let recent = recentMenus.first(where: { $0.menu === menu }) {
            fillRecent(recent.menu, kind: recent.kind, identifierPrefix: recent.identifierPrefix)
            return
        }
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

    /// Fills Open Splits or Open Layout: Open…, then the recent files, most recent first, and
    /// Clear Menu below a separator when there are any (spec §7).
    private func fillRecent(_ menu: NSMenu, kind: RecentKind, identifierPrefix: String?) {
        let name = kind == .splits ? "splits" : "layouts"
        let paths = kind == .splits ? files.recentSplits : files.recentLayouts
        menu.removeAllItems()
        // Only the right-click menu's items have identifiers (`identifierPrefix`): the menu
        // bar's, including its recent files, have none by design.
        func add(_ title: String, _ action: Selector, identifier: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            // AppKit doesn't validate the items added here before showing the submenu, so
            // they are enabled or not as they are filled in, as `validateMenuItem(_:)` would
            // have them: splits can't be replaced while an attempt runs (spec §7).
            item.isEnabled = kind == .layouts || files.canReplaceRun
            if let identifierPrefix {
                item.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + identifier)
            }
            menu.addItem(item)
            return item
        }
        _ = add(
            "Open…", kind == .splits ? #selector(openSplits(_:)) : #selector(openLayout(_:)),
            identifier: kind == .splits ? "open-splits-choose" : "open-layout-choose")
        let names = paths.map { URL(filePath: $0).lastPathComponent }
        for (index, path) in paths.enumerated() {
            // The parent folder's name tells apart files with the same name (spec §7).
            let title =
                names.filter { $0 == names[index] }.count > 1
                ? "\(names[index]) — \(URL(filePath: path).deletingLastPathComponent().lastPathComponent)"
                : names[index]
            let item = add(
                title,
                kind == .splits
                    ? #selector(openRecentSplits(_:)) : #selector(openRecentLayouts(_:)),
                identifier: "recent-\(name)-\(index)")
            item.toolTip = path
            item.representedObject = path
        }
        guard !paths.isEmpty else { return }
        menu.addItem(.separator())
        _ = add(
            "Clear Menu",
            kind == .splits ? #selector(clearRecentSplits(_:)) : #selector(clearRecentLayouts(_:)),
            identifier: "clear-recent-\(name)")
    }

    /// Menus show the Control shortcuts but never run them: `ShortcutKeys` does, only while the
    /// timer window is key (spec §7.2). Otherwise a plain `u` would run Undo Split while typing
    /// in the Settings window. Belt and braces, like `ShortcutDisplayMenu`: AppKit can match
    /// items itself whatever this returns. What makes it safe is `showsShortcuts`, which leaves
    /// the items without key equivalents while another window is key.
    func menuHasKeyEquivalent(
        _ menu: NSMenu, for event: NSEvent,
        target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
        action: UnsafeMutablePointer<Selector?>
    ) -> Bool {
        false
    }
}
