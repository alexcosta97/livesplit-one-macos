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

    init() {
        let run = Run()
        run.pushSegment(Segment("Time"))
        runner = CommandRunner(
            timer: LiveSplitCore.Timer(run)!.intoShared(), resetSavesBestTimes: nil, changed: {})
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
        #expect(app.items[2].keyEquivalent == ",")
        #expect(app.items[4].keyEquivalent == "h")
        #expect(app.items[5].keyEquivalentModifierMask == [.option, .command])
        #expect(app.items[8].keyEquivalent == "q")
        #expect(app.items[8].action == #selector(NSApplication.terminate(_:)))

        let window = try submenu("Window", in: menus.mainMenu)
        #expect(window === menus.windowMenu)
        #expect(titles(window) == ["Close", "Minimize", "—", "Always on Top"])
        #expect(window.items[0].keyEquivalent == "w")
        #expect(window.items[1].keyEquivalent == "m")
        #expect(window.items[1].action == #selector(NSWindow.miniaturize(_:)))

        #expect(titles(try submenu("Help", in: menus.mainMenu)) == ["Open Log Folder"])
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
        #expect(menu.items[6].action == #selector(AppDelegate.openLogFolder(_:)))
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
        }

        state.currentComparison = "Sub"
        state.timingMethod = .gameTime
        let compare = try submenu("Compare Against", in: menus.mainMenu)
        menus.menuNeedsUpdate(compare)
        #expect(compare.items.map(\.state) == [.on, .off, .off, .off, .off, .on])
    }

    @Test func controlItemsShowTheirFirstShortcutThatAMenuCanShow() throws {
        let menus = makeMenus()
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

    @Test func aDisabledCommandIsntRun() {
        let menus = makeMenus()
        #expect(!menus.perform(.reset, from: .keyboard))
        #expect(menus.perform(.startSplit, from: .keyboard))
    }
}
