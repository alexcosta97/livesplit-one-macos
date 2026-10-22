import AppKit
import LiveSplitCore
import Testing

@testable import LiveSplitOne

@MainActor
@Suite final class TimerMenusTests {
    var state = TimerMenuState(
        phase: .notRunning, splitIndex: -1, segmentCount: 2,
        comparisons: ["Sub", "Personal Best", "Best Segments"], currentComparison: "Personal Best",
        timingMethod: .realTime)
    var shortcuts = Shortcuts()
    var connection = ConnectionStatus.notConnected
    let runner: CommandRunner
    let content = TimerContent(lang: 0)
    var timer: SharedTimer { content.timer }
    let window: TimerWindowController
    let settings: SettingsStore
    let files: FileController
    let unified = RecordingUnifiedLog()
    let folder: TemporaryFolder

    init() throws {
        let run = Run()
        run.pushSegment(Segment("Time"))
        #expect(content.setRun(run) == .replaced)
        folder = try TemporaryFolder()
        settings = SettingsStore(
            directory: folder.url.appending(path: "config", directoryHint: .isDirectory))
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        window = TimerWindowController(
            content: content, settings: settings, screens: { [screen] }, mainScreen: { screen },
            notices: NoticeQueue(schedule: { _, _ in }))
        let log = Log(directory: folder.url.appending(path: "logs"), unified: unified)
        files = FileController(
            content: content, window: window, settings: settings, picker: FakeFilePicker(),
            alerts: FakeFileAlerts(), lang: 0, log: log)
        runner = CommandRunner(
            timer: content.timer, resetSavesBestTimes: nil, log: log, changed: {},
            remember: { _ in })
    }

    // Ends the window's display link, so they don't pile up across tests.
    isolated deinit {
        window.window.contentView = nil
    }

    /// Waits until every command sent so far has run: the runner's queue is serial, so a
    /// command sent now runs only once every earlier one has.
    private func finishCommands() async {
        await withCheckedContinuation { continuation in
            runner.run(.undoAllPauses, from: .keyboard) { _ in continuation.resume() }
        }
    }

    private func makeMenus(splitsEditor: SplitsEditorPresenter? = nil) -> TimerMenus {
        TimerMenus(
            runner: runner, readState: { [unowned self] in state },
            shortcuts: { [unowned self] in shortcuts }, files: files,
            connectionStatus: { [unowned self] in connection }, splitsEditor: splitsEditor)
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    private func submenu(_ title: String, in menu: NSMenu) throws -> NSMenu {
        try #require(menu.items.first { $0.title == title }?.submenu)
    }

    @Test func theMenuBar() throws {
        let menus = makeMenus()
        #expect(
            titles(menus.mainMenu) == [
                "LiveSplit One", "File", "Edit", "Control", "Compare Against", "Window", "Help",
            ])

        let app = try submenu("LiveSplit One", in: menus.mainMenu)
        #expect(
            titles(app) == [
                "About LiveSplit One for macOS", "—", "Settings…", "—",
                "Hide LiveSplit One for macOS", "Hide Others", "Show All", "—",
                "Quit LiveSplit One for macOS",
            ])
        #expect(app.items[0].action == #selector(AppDelegate.showAbout(_:)))
        #expect(app.items[2].action == #selector(AppDelegate.showSettings(_:)))
        #expect(app.items[2].keyEquivalent == ",")
        #expect(app.items[4].action == #selector(NSApplication.hide(_:)))
        #expect(app.items[5].action == #selector(NSApplication.hideOtherApplications(_:)))
        #expect(app.items[5].keyEquivalent == "h")
        #expect(app.items[6].action == #selector(NSApplication.unhideAllApplications(_:)))
        #expect(app.items[4].keyEquivalent == "h")
        #expect(app.items[5].keyEquivalentModifierMask == [.option, .command])
        #expect(app.items[8].keyEquivalent == "q")
        #expect(app.items[8].action == #selector(NSApplication.terminate(_:)))

        let file = try submenu("File", in: menus.mainMenu)
        #expect(
            titles(file) == [
                "Edit Splits…", "Open Splits", "Save Splits", "Save Splits As…", "Close Splits",
                "—", "Open Layout", "Save Layout As…", "—", "Connect to Server…",
            ])
        #expect(file.items[0].action == #selector(TimerMenus.editSplits(_:)))
        #expect(file.items[0].target === menus)
        #expect(file.items[0].keyEquivalent == "")
        #expect(file.items[2].action == #selector(TimerMenus.saveSplits(_:)))
        #expect(file.items[2].keyEquivalent == "s")
        #expect(file.items[2].keyEquivalentModifierMask == .command)
        #expect(file.items[3].action == #selector(TimerMenus.saveSplitsAs(_:)))
        #expect(file.items[3].keyEquivalent == "s")
        #expect(file.items[3].keyEquivalentModifierMask == [.shift, .command])
        #expect(file.items[4].action == #selector(TimerMenus.closeSplits(_:)))
        #expect(file.items[7].action == #selector(TimerMenus.saveLayoutAs(_:)))
        #expect(file.items[9].action == #selector(AppDelegate.toggleConnection(_:)))
        #expect(file.items[9].identifier?.rawValue == "file-connect")
        #expect(
            file.items.allSatisfy { $0.identifier?.rawValue.hasPrefix("timer-") != true })

        // For the text fields of the splits editor and the Connect sheet: AppKit's text fields
        // only get these keys from menu items (spec §7). They go to the first responder.
        let edit = try submenu("Edit", in: menus.mainMenu)
        #expect(
            titles(edit) == ["Undo", "Redo", "—", "Cut", "Copy", "Paste", "Select All"])
        #expect(
            edit.items.map(\.action) == [
                Selector(("undo:")), Selector(("redo:")), nil, #selector(NSText.cut(_:)),
                #selector(NSText.copy(_:)), #selector(NSText.paste(_:)),
                #selector(NSText.selectAll(_:)),
            ])
        let editItems = edit.items.filter { !$0.isSeparatorItem }
        #expect(editItems.map(\.keyEquivalent) == ["z", "z", "x", "c", "v", "a"])
        #expect(
            editItems.map(\.keyEquivalentModifierMask) == [
                .command, [.shift, .command], .command, .command, .command, .command,
            ])
        #expect(edit.items.allSatisfy { $0.target == nil })

        let window = try submenu("Window", in: menus.mainMenu)
        #expect(window === menus.windowMenu)
        #expect(titles(window) == ["Close", "Minimize", "—", "Always on Top"])
        #expect(window.items[0].action == #selector(NSWindow.performClose(_:)))
        #expect(window.items[0].keyEquivalent == "w")
        #expect(window.items[3].action == #selector(AppDelegate.toggleAlwaysOnTop(_:)))
        #expect(window.items[1].keyEquivalent == "m")
        #expect(window.items[1].action == #selector(NSWindow.miniaturize(_:)))

        let help = try submenu("Help", in: menus.mainMenu)
        #expect(help === menus.helpMenu)
        #expect(titles(help) == ["Open Log Folder", "Acknowledgements"])
        #expect(help.items[0].action == #selector(AppDelegate.openLogFolder(_:)))
        #expect(help.items[1].action == #selector(AppDelegate.showAcknowledgements(_:)))
        #expect(help.items[1].identifier?.rawValue == "help-acknowledgements")
    }

    @Test func theRightClickMenu() throws {
        let menus = makeMenus()
        let menu = menus.contextMenu
        #expect(
            titles(menu) == [
                "Edit Splits…", "Open Splits", "Save Splits", "Save Splits As…", "Close Splits",
                "—", "Control", "Compare Against", "—", "Open Layout", "Save Layout As…", "—",
                "Connect to Server…", "Always on Top", "—", "Settings…", "Open Log Folder",
                "About LiveSplit One for macOS", "Quit",
            ])
        // The items AppKit leaves without an identifier take their action's name.
        #expect(
            menu.items.prefix(15).map { $0.identifier?.rawValue } == [
                "timer-edit-splits", "timer-open-splits", "timer-save-splits",
                "timer-save-splits-as", "timer-close-splits", nil, "timer-control",
                "timer-compare-against", nil, "timer-open-layout", "timer-save-layout-as", nil,
                "timer-connect", "timer-always-on-top", nil,
            ])
        #expect(menu.items[0].action == #selector(TimerMenus.editSplits(_:)))
        #expect(menu.items[0].target === menus)
        #expect(menu.items[2].keyEquivalent == "s")
        #expect(menu.items[3].keyEquivalentModifierMask == [.shift, .command])
        #expect(menu.items[12].action == #selector(AppDelegate.toggleConnection(_:)))
        #expect(menu.items[13].action == #selector(AppDelegate.toggleAlwaysOnTop(_:)))
        #expect(menu.items[15].action == #selector(AppDelegate.showSettings(_:)))
        #expect(menu.items[15].keyEquivalent == ",")
        #expect(menu.items[16].action == #selector(AppDelegate.openLogFolder(_:)))
        #expect(menu.items[17].action == #selector(AppDelegate.showAbout(_:)))
        #expect(menu.items[18].action == #selector(NSApplication.terminate(_:)))
        #expect(menu.items[18].keyEquivalent == "q")
        let control = try submenu("Control", in: menu)
        #expect(
            control.items.map { $0.identifier?.rawValue } == [
                "timer-start_split", "timer-reset", "timer-undo_split", "timer-skip_split",
                "timer-pause", "timer-undo_all_pauses",
            ])
    }

    @Test func theConnectItemFollowsTheConnectionInBothMenus() throws {
        let menus = makeMenus()
        let items = [
            try #require(
                menus.contextMenu.items.first { $0.identifier?.rawValue == "timer-connect" }),
            try #require(
                try submenu("File", in: menus.mainMenu).items.first {
                    $0.identifier?.rawValue == "file-connect"
                }),
        ]
        #expect(items.map(\.title) == ["Connect to Server…", "Connect to Server…"])
        let server = try ServerURL.parse("192.168.1.20:9087").get()
        for status: ConnectionStatus in [
            .connecting(server), .connected(server), .retrying(server, attempt: 2),
        ] {
            connection = status
            menus.refreshConnection()
            #expect(items.allSatisfy { $0.title == "Disconnect from 192.168.1.20:9087" })
        }
        connection = .notConnected
        menus.refreshConnection()
        #expect(items.allSatisfy { $0.title == "Connect to Server…" })
    }

    /// Validates every Control item in both menus, as AppKit does before showing them, and
    /// returns each one's title and whether it is enabled.
    private func validated(_ menus: TimerMenus) throws -> [[String]] {
        let controls = [
            try submenu("Control", in: menus.mainMenu),
            try submenu("Control", in: menus.contextMenu),
        ]
        return controls.map { menu in
            menu.items.map { item in
                let enabled = menus.validateMenuItem(item)
                return item.title + (enabled ? "" : " (off)")
            }
        }
    }

    @Test func controlItemsFollowTheTimerInBothMenus() throws {
        let menus = makeMenus()
        let idle = [
            "Start", "Reset (off)", "Undo Split (off)", "Skip Split (off)", "Pause (off)",
            "Undo All Pauses (off)",
        ]
        #expect(try validated(menus) == [idle, idle])

        state.phase = .paused
        state.splitIndex = 0
        let paused = [
            "Split (off)", "Reset", "Undo Split (off)", "Skip Split", "Resume", "Undo All Pauses",
        ]
        #expect(try validated(menus) == [paused, paused])
    }

    @Test func compareAgainstListsTheComparisonsAndTicksTheCurrentOne() throws {
        let menus = makeMenus()
        for compare in [
            try submenu("Compare Against", in: menus.mainMenu),
            try submenu("Compare Against", in: menus.contextMenu),
        ] {
            menus.menuNeedsUpdate(compare)
            #expect(
                titles(compare) == [
                    "Sub", "Personal Best", "Best Segments", "—", "Real Time", "Game Time",
                ])
            #expect(compare.items.map(\.state) == [.off, .on, .off, .off, .on, .off])
            let comparisons = compare.items[0..<3]
            #expect(comparisons.allSatisfy { $0.action == #selector(TimerMenus.setComparison(_:)) })
            #expect(comparisons.allSatisfy { $0.target === menus })
            #expect(
                comparisons.map { $0.representedObject as? String } == [
                    "Sub", "Personal Best", "Best Segments",
                ])
            let methods = compare.items[4...]
            #expect(
                methods.allSatisfy { $0.action == #selector(TimerMenus.setTimingMethod(_:)) })
            #expect(methods.allSatisfy { $0.target === menus })
            #expect(
                methods.map(\.tag) == [
                    Int(TimingMethod.realTime.rawValue), Int(TimingMethod.gameTime.rawValue),
                ])
        }

        state.currentComparison = "Sub"
        state.timingMethod = .gameTime
        let compare = try submenu("Compare Against", in: menus.mainMenu)
        menus.menuNeedsUpdate(compare)
        #expect(compare.items.map(\.state) == [.on, .off, .off, .off, .off, .on])
    }

    /// The Control items of both menus.
    private func controlItems(_ menus: TimerMenus) throws -> [[NSMenuItem]] {
        [
            try submenu("Control", in: menus.mainMenu).items,
            try submenu("Control", in: menus.contextMenu).items,
        ]
    }

    @Test func controlItemsShowNoShortcutsUntilTheTimerWindowIsInFront() throws {
        let menus = makeMenus()
        #expect(!menus.showsShortcuts)
        for items in try controlItems(menus) {
            #expect(items.allSatisfy { $0.keyEquivalent.isEmpty })
            #expect(items.allSatisfy { $0.keyEquivalentModifierMask == [] })
        }

        menus.showsShortcuts = true
        for items in try controlItems(menus) {
            #expect(items.map(\.keyEquivalent) == [" ", "\u{8}", "u", "s", "p", ""])
        }

        menus.showsShortcuts = false
        shortcuts.remove(Shortcut("Space")!, from: .startSplit)
        _ = shortcuts.add(Shortcut("Control+Shift+Space")!, to: .startSplit)
        menus.refreshShortcuts()
        for items in try controlItems(menus) {
            #expect(items.allSatisfy { $0.keyEquivalent.isEmpty })
            #expect(items.allSatisfy { $0.keyEquivalentModifierMask == [] })
        }

        // A shortcut changed while they were hidden shows once they're shown again.
        menus.showsShortcuts = true
        for items in try controlItems(menus) {
            #expect(items[0].keyEquivalent == " ")
            #expect(items[0].keyEquivalentModifierMask == [.control, .shift])
        }
    }

    /// While another window is in front, such as the Settings window, the Control items have no
    /// key equivalents, so a plain `u` or Space typed there can't match one on any macOS.
    @Test func aKeyPressedWhileTheTimerWindowIsntInFrontRunsNoCommand() async throws {
        let menus = makeMenus()
        menus.showsShortcuts = false
        #expect(!menus.mainMenu.performKeyEquivalent(with: keyDown(32, "u")))  // kVK_ANSI_U
        #expect(!menus.mainMenu.performKeyEquivalent(with: keyDown(49, " ")))  // kVK_Space
        #expect(!menus.contextMenu.performKeyEquivalent(with: keyDown(49, " ")))
        await finishCommands()
        #expect(TimerMenuState.read(from: timer).phase == .notRunning)
        #expect(!unified.entries.contains { $0.message.contains("from the menu") })
    }

    @Test func controlItemsShowTheirFirstShortcutThatAMenuCanShow() throws {
        let menus = makeMenus()
        menus.showsShortcuts = true
        let control = try submenu("Control", in: menus.mainMenu)
        #expect(control.items.map(\.keyEquivalent) == [" ", "\u{8}", "u", "s", "p", ""])
        #expect(control.items.allSatisfy { $0.keyEquivalentModifierMask == [] })

        shortcuts.remove(Shortcut("Space")!, from: .startSplit)
        _ = shortcuts.add(Shortcut("Numpad1")!, to: .startSplit)
        _ = shortcuts.add(Shortcut("Control+Shift+Space")!, to: .startSplit)
        shortcuts.remove(Shortcut("u")!, from: .undoSplit)
        _ = shortcuts.add(Shortcut("Numpad8")!, to: .undoSplit)
        menus.refreshShortcuts()

        #expect(control.items[0].keyEquivalent == " ")
        #expect(control.items[0].keyEquivalentModifierMask == [.control, .shift])
        #expect(control.items[2].keyEquivalent == "")
        let context = try submenu("Control", in: menus.contextMenu)
        #expect(context.items[0].keyEquivalentModifierMask == [.control, .shift])
    }

    @Test func menusNeverRunAShortcutThemselves() throws {
        let menus = makeMenus()
        let control = try submenu("Control", in: menus.mainMenu)
        let event = keyDown(49, " ")  // kVK_Space
        var target: AnyObject?
        var action: Selector?
        #expect(!menus.menuHasKeyEquivalent(control, for: event, target: &target, action: &action))
    }

    /// The delegate fills Compare Against each time it opens (`menuNeedsUpdate`) and gives the
    /// Control items their titles and enabled state (validation), so every such menu needs it.
    /// What stops the menus running a key press is `showsShortcuts`, not the delegate.
    @Test func everyMenuThatCanRunACommandHasTheDelegate() throws {
        let menus = makeMenus()
        for root in [menus.mainMenu, menus.contextMenu] {
            let parent = root === menus.mainMenu ? try submenu("File", in: root) : root
            for title in ["Control", "Compare Against"] {
                #expect(try submenu(title, in: root).delegate === menus)
            }
            for title in ["Open Splits", "Open Layout"] {
                #expect(try submenu(title, in: parent).delegate === menus)
            }
        }
    }

    /// Plain `u` and Space are Control shortcuts. Even with the items showing them, the menus
    /// don't match a key press against them (belt and braces: what makes this safe on every
    /// macOS is that the items have no key equivalents unless the timer window is in front).
    @Test func aKeyPressedInTheMenuBarRunsNoCommand() async throws {
        let menus = makeMenus()
        menus.showsShortcuts = true
        #expect(!menus.mainMenu.performKeyEquivalent(with: keyDown(32, "u")))  // kVK_ANSI_U
        #expect(!menus.mainMenu.performKeyEquivalent(with: keyDown(49, " ")))  // kVK_Space
        #expect(!menus.contextMenu.performKeyEquivalent(with: keyDown(49, " ")))
        await finishCommands()
        #expect(TimerMenuState.read(from: timer).phase == .notRunning)
    }

    // MARK: Files

    private func startAttempt() {
        let sink = EventSink(timer: timer, report: { _ in }, decideReset: { .discard })
        _ = sink.handleCommand(#"{"command":"start"}"#)
    }

    private func send(_ command: String) {
        let sink = EventSink(timer: timer, report: { _ in }, decideReset: { .discard })
        _ = sink.handleCommand(#"{"command":"\#(command)"}"#)
    }

    private func contextItem(_ title: String, in menus: TimerMenus) throws -> NSMenuItem {
        try #require(menus.contextMenu.items.first { $0.title == title })
    }

    /// Opens the Open Splits or Open Layout submenu as AppKit does, and returns its items.
    private func opened(_ title: String, in root: NSMenu, _ menus: TimerMenus) throws
        -> [NSMenuItem]
    {
        let menu = try submenu(title, in: root)
        menus.menuNeedsUpdate(menu)
        return menu.items
    }

    @Test func openSplitsListsTheRecentFilesMostRecentFirstAndClearMenuClearsThem() throws {
        let menus = makeMenus()
        for root in [menus.mainMenu, menus.contextMenu] {
            let parent = root === menus.mainMenu ? try submenu("File", in: root) : root
            let items = try opened("Open Splits", in: parent, menus)
            #expect(items.map(\.title) == ["Open…"])
        }
        settings.update {
            $0.recentSplits.add("/tmp/first.lss")
            $0.recentSplits.add("/tmp/second.lss")
        }
        let items = try opened("Open Splits", in: menus.contextMenu, menus)
        #expect(
            items.map { $0.isSeparatorItem ? "—" : $0.title } == [
                "Open…", "second.lss", "first.lss", "—", "Clear Menu",
            ])
        #expect(
            items.map { $0.identifier?.rawValue } == [
                "timer-open-splits-choose", "timer-recent-splits-0", "timer-recent-splits-1", nil,
                "timer-clear-recent-splits",
            ])
        #expect(items[1].toolTip == "/tmp/second.lss")
        #expect(items[1].representedObject as? String == "/tmp/second.lss")
        #expect(items[1].action == #selector(TimerMenus.openRecentSplits(_:)))
        #expect(items[0].action == #selector(TimerMenus.openSplits(_:)))
        #expect(items.allSatisfy { $0.isSeparatorItem || $0.target === menus })

        let clear = items[4]
        #expect(clear.action == #selector(TimerMenus.clearRecentSplits(_:)))
        menus.clearRecentSplits(clear)
        #expect(settings.settings.recentSplits.paths.isEmpty)
        #expect(try opened("Open Splits", in: menus.contextMenu, menus).map(\.title) == ["Open…"])
    }

    @Test func openLayoutListsTheRecentLayoutsMostRecentFirstAndClearMenuClearsThem() throws {
        let menus = makeMenus()
        settings.update {
            $0.recentLayouts.add("/tmp/a.ls1l")
            $0.recentLayouts.add("/tmp/b.ls1l")
        }
        let items = try opened("Open Layout", in: menus.contextMenu, menus)
        #expect(
            items.map { $0.isSeparatorItem ? "—" : $0.title } == [
                "Open…", "b.ls1l", "a.ls1l", "—", "Clear Menu",
            ])
        #expect(
            items.map { $0.identifier?.rawValue } == [
                "timer-open-layout-choose", "timer-recent-layouts-0", "timer-recent-layouts-1", nil,
                "timer-clear-recent-layouts",
            ])
        #expect(items[2].representedObject as? String == "/tmp/a.ls1l")
        #expect(items[1].action == #selector(TimerMenus.openRecentLayouts(_:)))
        menus.clearRecentLayouts(items[4])
        #expect(settings.settings.recentLayouts.paths.isEmpty)
    }

    @Test func recentFilesWithTheSameNameAddTheirFolder() throws {
        let menus = makeMenus()
        settings.update {
            $0.recentSplits.add("/tmp/Races/Splits.lss")
            $0.recentSplits.add("/tmp/Other/Splits.lss")
            $0.recentSplits.add("/tmp/Unique.lss")
        }
        let items = try opened("Open Splits", in: menus.contextMenu, menus)
        #expect(
            items.map { $0.isSeparatorItem ? "—" : $0.title } == [
                "Open…", "Unique.lss", "Splits.lss — Other", "Splits.lss — Races", "—",
                "Clear Menu",
            ])
        #expect(items[2].toolTip == "/tmp/Other/Splits.lss")
        #expect(items[3].representedObject as? String == "/tmp/Races/Splits.lss")
    }

    // MARK: Save actions reach the controller

    private func makeMenusWithFiles(picker: FakeFilePicker) -> TimerMenus {
        let log = Log(directory: folder.url.appending(path: "logs"), unified: unified)
        let controller = FileController(
            content: content, window: window, settings: settings, picker: picker,
            alerts: FakeFileAlerts(), lang: 0, log: log)
        return TimerMenus(
            runner: runner, readState: { [unowned self] in state },
            shortcuts: { [unowned self] in shortcuts }, files: controller)
    }

    private func fileItem(_ title: String, in menus: TimerMenus) throws -> NSMenuItem {
        let file = try submenu("File", in: menus.mainMenu)
        return try #require(file.items.first { $0.title == title })
    }

    private func invoke(_ item: NSMenuItem) throws {
        let action = try #require(item.action)
        _ = NSApp.sendAction(action, to: item.target, from: item)
    }

    @Test func saveSplitsFromTheMenuAsksForANameWhenTheRunHasNoFile() throws {
        let target = folder.url.appending(path: "Saved.lss")
        let picker = FakeFilePicker(save: [target])
        let menus = makeMenusWithFiles(picker: picker)
        try invoke(fileItem("Save Splits", in: menus))
        #expect(picker.saves.map(\.kind) == ["splits"])
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(settings.settings.recentSplits.paths == [target.standardizedFileURL.path])

        // With a file now, Save Splits writes it without asking again.
        try invoke(fileItem("Save Splits", in: menus))
        #expect(picker.saves.count == 1)
    }

    @Test func saveSplitsAsFromTheMenuAsksEvenWithAFile() throws {
        let first = folder.url.appending(path: "One.lss")
        let second = folder.url.appending(path: "Two.lss")
        let picker = FakeFilePicker(save: [first, second])
        let menus = makeMenusWithFiles(picker: picker)
        try invoke(fileItem("Save Splits As…", in: menus))
        try invoke(fileItem("Save Splits As…", in: menus))
        #expect(picker.saves.map(\.kind) == ["splits", "splits"])
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func saveLayoutAsFromTheMenuWritesTheLayout() throws {
        let target = folder.url.appending(path: "Layout.ls1l")
        let picker = FakeFilePicker(save: [target])
        let menus = makeMenusWithFiles(picker: picker)
        try invoke(fileItem("Save Layout As…", in: menus))
        #expect(picker.saves.map(\.kind) == ["layout"])
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(settings.settings.recentLayouts.paths == [target.standardizedFileURL.path])
    }

    /// Validates the Files items of both menus and returns which are enabled, in order: Open
    /// Splits' Open…, a recent file and Clear Menu, then Close Splits, Save Splits, Save
    /// Splits As…, Open Layout's Open… and Save Layout As….
    private func filesEnabled(_ menus: TimerMenus) throws -> [[Bool]] {
        settings.update { $0.recentSplits.add("/tmp/first.lss") }
        return try [menus.mainMenu, menus.contextMenu].map { root in
            let parent = root === menus.mainMenu ? try submenu("File", in: root) : root
            let open = try opened("Open Splits", in: parent, menus)
            let layout = try opened("Open Layout", in: parent, menus)
            let named = ["Close Splits", "Save Splits", "Save Splits As…", "Save Layout As…"]
                .map { title in parent.items.first { $0.title == title }! }
            let all = open + [named[0], named[1], named[2], layout[0], named[3]]
            return all.filter { !$0.isSeparatorItem }.map { menus.validateMenuItem($0) }
        }
    }

    @Test func openSplitsAndCloseSplitsAreEnabledOnlyWhenNoAttemptIsInProgress() throws {
        let menus = makeMenus()
        let idle = [true, true, true, true, true, true, true, true]
        #expect(try filesEnabled(menus) == [idle, idle])

        startAttempt()
        #expect(content.phase == .running)
        let busy = [false, false, false, false, true, true, true, true]
        #expect(try filesEnabled(menus) == [busy, busy])

        send("pause")
        #expect(content.phase == .paused)
        #expect(try filesEnabled(menus) == [busy, busy])

        send("resume")
        send("split")
        #expect(content.phase == .ended)
        #expect(try filesEnabled(menus) == [busy, busy])

        send("reset")
        #expect(content.phase == .notRunning)
        #expect(try filesEnabled(menus) == [idle, idle])
    }

    /// AppKit shows the items `menuNeedsUpdate` adds without validating them, so they must be
    /// enabled or not as they are filled in: the end-to-end test found Open… looking enabled
    /// while an attempt ran.
    @Test func theRecentItemsAreFilledInDisabledWhileAnAttemptRuns() throws {
        let menus = makeMenus()
        settings.update { $0.recentSplits.add("/tmp/first.lss") }
        startAttempt()
        let busy = try opened("Open Splits", in: menus.contextMenu, menus)
            .filter { !$0.isSeparatorItem }
        #expect(busy.count == 3)  // Open…, the recent file, Clear Menu
        #expect(busy.allSatisfy { !$0.isEnabled })

        send("reset")
        let idle = try opened("Open Splits", in: menus.contextMenu, menus)
            .filter { !$0.isSeparatorItem }
        #expect(idle.allSatisfy { $0.isEnabled })
    }

    @Test func theOpenSplitsParentStaysEnabledSoItsSubmenuOpens() throws {
        let menus = makeMenus()
        startAttempt()
        let parent = try contextItem("Open Splits", in: menus)
        #expect(parent.submenu != nil)
        #expect(parent.isEnabled)
    }

    // MARK: Edit Splits

    /// A presenter that runs no modal session; `modalRuns` counts its openings.
    private var modalRuns = 0

    private func makePresenter() -> SplitsEditorPresenter {
        let log = Log(directory: folder.url.appending(path: "logs"), unified: unified)
        return SplitsEditorPresenter(
            content: content, window: window, prompts: ScriptedPrompts(), log: log, lang: 0,
            runModal: { [unowned self] _ in modalRuns += 1 }, stopModal: {})
    }

    /// Edit Splits… in the menu bar's File menu and in the right-click menu.
    private func editSplitsItems(_ menus: TimerMenus) throws -> [NSMenuItem] {
        [try fileItem("Edit Splits…", in: menus), try contextItem("Edit Splits…", in: menus)]
    }

    @Test func editSplitsOpensTheEditor() throws {
        let presenter = makePresenter()
        let menus = makeMenus(splitsEditor: presenter)
        defer { presenter.editorWindow?.close() }
        try invoke(try contextItem("Edit Splits…", in: menus))
        #expect(presenter.isOpen)
        #expect(modalRuns == 1)
    }

    @Test func editSplitsIsDisabledWithoutAnEditor() throws {
        let menus = makeMenus()
        #expect(try editSplitsItems(menus).map { menus.validateMenuItem($0) } == [false, false])
    }

    @Test func editSplitsIsEnabledOnlyWhenNoAttemptIsInProgress() throws {
        let menus = makeMenus(splitsEditor: makePresenter())
        let items = try editSplitsItems(menus)
        #expect(items.map { menus.validateMenuItem($0) } == [true, true])

        startAttempt()
        #expect(items.map { menus.validateMenuItem($0) } == [false, false])
        send("pause")
        #expect(items.map { menus.validateMenuItem($0) } == [false, false])
        send("resume")
        send("split")
        #expect(content.phase == .ended)
        #expect(items.map { menus.validateMenuItem($0) } == [false, false])

        send("reset")
        #expect(items.map { menus.validateMenuItem($0) } == [true, true])
    }

    /// So OK never overwrites a run opened while the editor was open (spec §7).
    @Test func nothingThatReplacesTheRunIsEnabledWhileTheEditorIsOpen() throws {
        let presenter = makePresenter()
        let menus = makeMenus(splitsEditor: presenter)
        presenter.open()
        defer { presenter.editorWindow?.close() }
        #expect(presenter.isOpen)

        let busy = [false, false, false, false, true, true, true, true]
        #expect(try filesEnabled(menus) == [busy, busy])
        #expect(try editSplitsItems(menus).map { menus.validateMenuItem($0) } == [false, false])
        let recent = try opened("Open Splits", in: menus.contextMenu, menus)
            .filter { !$0.isSeparatorItem }
        #expect(recent.count == 3)
        #expect(recent.allSatisfy { !$0.isEnabled })

        presenter.applyOK()
        #expect(!presenter.isOpen)
        let idle = [true, true, true, true, true, true, true, true]
        #expect(try filesEnabled(menus) == [idle, idle])
        #expect(try editSplitsItems(menus).map { menus.validateMenuItem($0) } == [true, true])
    }

    @Test func aDisabledCommandIsntRun() async {
        let menus = makeMenus()
        #expect(!menus.perform(.reset, from: .keyboard))
        await finishCommands()
        #expect(!unified.entries.contains { $0.message.hasPrefix("Reset from") })

        #expect(menus.perform(.startSplit, from: .keyboard))
        await finishCommands()
        #expect(unified.entries.contains { $0.message.hasPrefix("Start/Split from the keyboard") })
        #expect(TimerMenuState.read(from: timer).phase == .running)
    }
}
