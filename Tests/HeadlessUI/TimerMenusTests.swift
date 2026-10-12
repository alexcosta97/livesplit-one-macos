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
        #expect(content.setRun(run))
        folder = try TemporaryFolder()
        settings = SettingsStore(
            directory: folder.url.appending(path: "config", directoryHint: .isDirectory))
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        window = TimerWindowController(
            content: content, settings: settings, screens: [screen], mainScreen: screen,
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

    private func makeMenus() -> TimerMenus {
        TimerMenus(
            runner: runner, readState: { [unowned self] in state },
            shortcuts: { [unowned self] in shortcuts }, files: files)
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
                "LiveSplit One", "File", "Control", "Compare Against", "Window", "Help",
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
                "Open Splits", "Save Splits", "Save Splits As…", "Close Splits", "—",
                "Open Layout", "Save Layout As…",
            ])
        #expect(file.items[1].action == #selector(TimerMenus.saveSplits(_:)))
        #expect(file.items[1].keyEquivalent == "s")
        #expect(file.items[1].keyEquivalentModifierMask == .command)
        #expect(file.items[2].action == #selector(TimerMenus.saveSplitsAs(_:)))
        #expect(file.items[2].keyEquivalent == "s")
        #expect(file.items[2].keyEquivalentModifierMask == [.shift, .command])
        #expect(file.items[3].action == #selector(TimerMenus.closeSplits(_:)))
        #expect(file.items[6].action == #selector(TimerMenus.saveLayoutAs(_:)))
        #expect(
            file.items.allSatisfy { $0.identifier?.rawValue.hasPrefix("timer-") != true })

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
        #expect(titles(help) == ["Open Log Folder"])
        #expect(help.items[0].action == #selector(AppDelegate.openLogFolder(_:)))
    }

    @Test func theRightClickMenu() throws {
        let menu = makeMenus().contextMenu
        #expect(
            titles(menu) == [
                "Open Splits", "Save Splits", "Save Splits As…", "Close Splits", "—", "Control",
                "Compare Against", "—", "Open Layout", "Save Layout As…", "—", "Always on Top",
                "—", "Settings…", "Open Log Folder", "About LiveSplit One for macOS", "Quit",
            ])
        // The items AppKit leaves without an identifier take their action's name.
        #expect(
            menu.items.prefix(13).map { $0.identifier?.rawValue } == [
                "timer-open-splits", "timer-save-splits", "timer-save-splits-as",
                "timer-close-splits", nil, "timer-control", "timer-compare-against", nil,
                "timer-open-layout", "timer-save-layout-as", nil, "timer-always-on-top", nil,
            ])
        #expect(menu.items[1].keyEquivalent == "s")
        #expect(menu.items[2].keyEquivalentModifierMask == [.shift, .command])
        #expect(menu.items[11].action == #selector(AppDelegate.toggleAlwaysOnTop(_:)))
        #expect(menu.items[13].action == #selector(AppDelegate.showSettings(_:)))
        #expect(menu.items[13].keyEquivalent == ",")
        #expect(menu.items[14].action == #selector(AppDelegate.openLogFolder(_:)))
        #expect(menu.items[15].action == #selector(AppDelegate.showAbout(_:)))
        #expect(menu.items[16].action == #selector(NSApplication.terminate(_:)))
        #expect(menu.items[16].keyEquivalent == "q")
        let control = try submenu("Control", in: menu)
        #expect(
            control.items.map { $0.identifier?.rawValue } == [
                "timer-start_split", "timer-reset", "timer-undo_split", "timer-skip_split",
                "timer-pause", "timer-undo_all_pauses",
            ])
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

    @Test func theOpenSplitsParentStaysEnabledSoItsSubmenuOpens() throws {
        let menus = makeMenus()
        startAttempt()
        let parent = try contextItem("Open Splits", in: menus)
        #expect(parent.submenu != nil)
        #expect(parent.isEnabled)
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
