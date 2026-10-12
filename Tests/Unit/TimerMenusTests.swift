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
    let timer: SharedTimer
    let unified = RecordingUnifiedLog()
    let folder: TemporaryFolder

    init() throws {
        let run = Run()
        run.pushSegment(Segment("Time"))
        timer = LiveSplitCore.Timer(run)!.intoShared()
        folder = try TemporaryFolder()
        runner = CommandRunner(
            timer: timer, resetSavesBestTimes: nil,
            log: Log(directory: folder.url, unified: unified), changed: {})
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
            shortcuts: { [unowned self] in shortcuts })
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
                "LiveSplit One", "Control", "Compare Against", "Window", "Help",
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
                "Control", "Compare Against", "—", "Always on Top", "—", "Settings…",
                "Open Log Folder", "About LiveSplit One for macOS", "Quit",
            ])
        #expect(menu.items[0].identifier?.rawValue == "timer-control")
        #expect(menu.items[1].identifier?.rawValue == "timer-compare-against")
        #expect(menu.items[3].identifier?.rawValue == "timer-always-on-top")
        #expect(menu.items[3].action == #selector(AppDelegate.toggleAlwaysOnTop(_:)))
        #expect(menu.items[5].action == #selector(AppDelegate.showSettings(_:)))
        #expect(menu.items[5].keyEquivalent == ",")
        #expect(menu.items[6].action == #selector(AppDelegate.openLogFolder(_:)))
        #expect(menu.items[7].action == #selector(AppDelegate.showAbout(_:)))
        #expect(menu.items[8].action == #selector(NSApplication.terminate(_:)))
        #expect(menu.items[8].keyEquivalent == "q")
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
            for title in ["Control", "Compare Against"] {
                #expect(try submenu(title, in: root).delegate === menus)
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
