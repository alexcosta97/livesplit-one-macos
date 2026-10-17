import AppKit
import Carbon.HIToolbox
import Testing

@testable import LiveSplitOne

@MainActor
@Suite final class SettingsWindowTests {
    let folder: TemporaryFolder
    let store: SettingsStore
    var changes = 0

    init() throws {
        folder = try TemporaryFolder()
        store = SettingsStore(directory: folder.url)
    }

    private func makeController() -> SettingsViewController {
        let controller = SettingsViewController(
            store: store,
            onChange: { [unowned self] in
                changes += 1
            })
        _ = controller.view
        return controller
    }

    private func find<T: NSView>(_ identifier: String, in view: NSView) -> T? {
        if view.accessibilityIdentifier() == identifier, let match = view as? T { return match }
        for subview in view.subviews {
            if let match: T = find(identifier, in: subview) { return match }
        }
        return nil
    }

    private func press(_ identifier: String, in controller: SettingsViewController) throws {
        let button: NSButton = try #require(find(identifier, in: controller.view))
        button.sendAction(button.action, to: button.target)
    }

    private func recorder(in controller: SettingsViewController) throws -> KeyRecorderView {
        try #require(find("shortcut-recorder", in: controller.view))
    }

    /// Answering the reset question changes the setting; a Settings window that is open shows it.
    @Test func anOpenSettingsWindowShowsTheAnswerToTheResetQuestion() throws {
        let delegate = try #require(NSApplication.shared.delegate as? AppDelegate)
        let settings = try #require(delegate.settings)
        defer {
            settings.update { $0.resetSavesBestTimes = nil }
            delegate.settingsChanged()  // The host's runner too.
            delegate.settingsWindow?.close()
        }
        settings.update { $0.resetSavesBestTimes = nil }
        delegate.showSettings(nil)
        let content = try #require(delegate.settingsWindow?.content)
        let popUp: NSPopUpButton = try #require(find("reset-best-times", in: content.view))
        #expect(popUp.titleOfSelectedItem == "Ask")

        delegate.rememberResetAnswer(false)
        #expect(popUp.titleOfSelectedItem == "Keep the old ones")
        delegate.rememberResetAnswer(true)
        #expect(popUp.titleOfSelectedItem == "Update them")
    }

    @Test func theResetChoiceStartsAtAskAndSavesEachChoice() throws {
        let controller = makeController()
        let popUp: NSPopUpButton = try #require(find("reset-best-times", in: controller.view))
        #expect(popUp.titleOfSelectedItem == "Ask")
        #expect(popUp.itemTitles == ["Ask", "Update them", "Keep the old ones"])

        popUp.selectItem(at: 2)
        popUp.sendAction(popUp.action, to: popUp.target)
        #expect(store.settings.resetSavesBestTimes == false)
        popUp.selectItem(at: 1)
        popUp.sendAction(popUp.action, to: popUp.target)
        #expect(store.settings.resetSavesBestTimes == true)
        popUp.selectItem(at: 0)
        popUp.sendAction(popUp.action, to: popUp.target)
        #expect(store.settings.resetSavesBestTimes == nil)
        #expect(changes == 3)
    }

    @Test func theResetChoiceShowsWhatIsSaved() throws {
        store.update { $0.resetSavesBestTimes = false }
        let popUp: NSPopUpButton = try #require(find("reset-best-times", in: makeController().view))
        #expect(popUp.titleOfSelectedItem == "Keep the old ones")
    }

    @Test func eachCommandShowsItsShortcuts() throws {
        let controller = makeController()
        let space: NSButton = try #require(find("shortcut-start_split-0", in: controller.view))
        #expect(space.title == "Space  ✕")
        #expect(space.accessibilityLabel() == "Remove Space from Start/Split")
        let undo: NSButton = try #require(find("shortcut-undo_split-0", in: controller.view))
        #expect(undo.title == "U  ✕")
        let none: NSButton? = find("shortcut-undo_all_pauses-0", in: controller.view)
        #expect(none == nil)
        let add: NSButton? = find("add-shortcut-undo_all_pauses", in: controller.view)
        #expect(add != nil)
    }

    @Test(.onABCOrUSLayout) func recordingAddsTheKeyAndSavesIt() throws {
        let controller = makeController()
        try press("add-shortcut-start_split", in: controller)
        #expect(controller.recording == .startSplit)
        try recorder(in: controller).keyDown(with: keyDown(kVK_ANSI_K, "k"))

        #expect(controller.recording == nil)
        #expect(
            store.settings.shortcuts.shortcuts(for: .startSplit) == [
                Shortcut("Space")!, Shortcut("k")!,
            ])
        let added: NSButton? = find("shortcut-start_split-1", in: controller.view)
        #expect(added?.title == "K  ✕")
        let recorder: KeyRecorderView? = find("shortcut-recorder", in: controller.view)
        #expect(recorder == nil)
        #expect(changes == 1)
    }

    @Test(.onABCOrUSLayout) func aShortcutAnotherCommandHasIsRefusedAndSaid() throws {
        let controller = makeController()
        try press("add-shortcut-reset", in: controller)
        try recorder(in: controller).keyDown(with: keyDown(kVK_ANSI_U, "u"))

        #expect(store.settings.shortcuts.isDefault)
        #expect(controller.messages[.reset] == "U is already used by Undo Split.")
        let message: NSTextField? = find("shortcut-message-reset", in: controller.view)
        #expect(message?.stringValue == "U is already used by Undo Split.")
        #expect(changes == 0)
    }

    @Test(.onABCOrUSLayout) func theAppsOwnMenuShortcutsAreRefused() throws {
        let controller = makeController()
        try press("add-shortcut-undo_all_pauses", in: controller)
        try recorder(in: controller).keyDown(with: keyDown(kVK_ANSI_Q, "q", flags: .command))
        #expect(controller.messages[.undoAllPauses] == "⌘Q is kept for the app's menus.")
        #expect(store.settings.shortcuts.isDefault)
        #expect(changes == 0)
    }

    /// ⌘Q reaches a window as a key equivalent before the menus see it. The recorder takes it,
    /// so the window refuses it rather than the app quitting.
    @Test(.onABCOrUSLayout) func theRecorderTakesCommandQBeforeTheMenus() throws {
        let controller = SettingsWindowController(store: store, onChange: {})
        let window = try #require(controller.window)
        let content = controller.content
        try press("add-shortcut-undo_all_pauses", in: content)
        #expect(window.firstResponder === (try recorder(in: content)))

        let event = keyDown(
            kVK_ANSI_Q, "q", flags: .command, windowNumber: window.windowNumber)
        #expect(window.performKeyEquivalent(with: event))
        #expect(content.recording == nil)
        let message: NSTextField? = find("shortcut-message-undo_all_pauses", in: content.view)
        #expect(message?.stringValue == "⌘Q is kept for the app's menus.")
        #expect(store.settings.shortcuts.isDefault)
    }

    /// ⌘Z is the Edit menu's Undo, and not reserved: the recorder takes it before the menus, so
    /// it can be recorded as a shortcut.
    @Test(.onABCOrUSLayout) func theRecorderTakesTheEditMenusKeysBeforeTheMenus() throws {
        let controller = SettingsWindowController(store: store, onChange: {})
        let window = try #require(controller.window)
        let content = controller.content
        try press("add-shortcut-undo_all_pauses", in: content)

        let event = keyDown(
            kVK_ANSI_Z, "z", flags: .command, windowNumber: window.windowNumber)
        #expect(window.performKeyEquivalent(with: event))
        #expect(content.recording == nil)
        #expect(
            store.settings.shortcuts.shortcuts(for: .undoAllPauses)
                == [Shortcut(key: .character("z"), modifiers: .meta)])
    }

    @Test func escapeCancelsRecording() throws {
        let controller = makeController()
        try press("add-shortcut-pause", in: controller)
        try recorder(in: controller).keyDown(with: keyDown(kVK_Escape, "\u{1B}"))
        #expect(controller.recording == nil)
        #expect(store.settings.shortcuts.isDefault)
        #expect(changes == 0)
    }

    @Test func aKeyRepeatIsNotRecorded() throws {
        let controller = makeController()
        try press("add-shortcut-pause", in: controller)
        try recorder(in: controller).keyDown(with: keyDown(kVK_ANSI_K, "k", isRepeat: true))
        #expect(controller.recording == .pause)
        #expect(store.settings.shortcuts.isDefault)
    }

    @Test func removingAShortcut() throws {
        let controller = makeController()
        try press("shortcut-undo_split-0", in: controller)
        #expect(store.settings.shortcuts.shortcuts(for: .undoSplit) == [])
        let gone: NSButton? = find("shortcut-undo_split-0", in: controller.view)
        #expect(gone == nil)
        #expect(changes == 1)
    }

    @Test(.onABCOrUSLayout) func restoreDefaultsPutsBackEveryShortcut() throws {
        let controller = makeController()
        try press("shortcut-undo_split-0", in: controller)
        try press("add-shortcut-reset", in: controller)
        try recorder(in: controller).keyDown(with: keyDown(kVK_ANSI_U, "u"))
        #expect(!store.settings.shortcuts.isDefault)

        try press("restore-default-shortcuts", in: controller)
        #expect(store.settings.shortcuts.isDefault)
        #expect(changes == 3)
    }

    /// How the Settings window stops being the one the user is in.
    enum Leaving: String, CaseIterable, Sendable {
        case resigningKey, closing

        @MainActor func leave(_ window: NSWindow) {
            switch self {
            case .resigningKey:
                NotificationCenter.default.post(
                    name: NSWindow.didResignKeyNotification, object: window)
            case .closing:
                window.close()
            }
        }
    }

    /// Otherwise the recorder would still be there when the window is next opened, and take
    /// ⌘W or ⌘Q as a shortcut to refuse rather than run it.
    @Test(arguments: Leaving.allCases)
    func leavingTheWindowStopsRecording(_ leaving: Leaving) throws {
        let controller = SettingsWindowController(store: store, onChange: {})
        let window = try #require(controller.window)
        let content = controller.content
        try press("add-shortcut-pause", in: content)
        #expect(content.recording == .pause)

        leaving.leave(window)
        #expect(content.recording == nil)
        let recorder: KeyRecorderView? = find("shortcut-recorder", in: content.view)
        #expect(recorder == nil)
        let add: NSButton? = find("add-shortcut-pause", in: content.view)
        #expect(add != nil)
    }

    @Test(arguments: Leaving.allCases)
    func leavingTheWindowClearsItsMessages(_ leaving: Leaving) throws {
        let controller = SettingsWindowController(store: store, onChange: {})
        let window = try #require(controller.window)
        let content = controller.content
        try press("add-shortcut-start_split", in: content)
        try recorder(in: content).keyDown(with: keyDown(kVK_Delete, "\u{7F}"))
        #expect(content.messages[.startSplit] == "⌫ is already used by Reset.")

        leaving.leave(window)
        #expect(content.messages.isEmpty)
        let message: NSTextField? = find("shortcut-message-start_split", in: content.view)
        #expect(message == nil)
    }

    @Test func theWindowIsNamedAndClosable() {
        let controller = SettingsWindowController(store: store, onChange: {})
        let window = controller.window
        #expect(window?.title == "Settings")
        #expect(window?.styleMask.contains(.closable) == true)
        #expect(window?.accessibilityIdentifier() == "settings-window")
    }
}
