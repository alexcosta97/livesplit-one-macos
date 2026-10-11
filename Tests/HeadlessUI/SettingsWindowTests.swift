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

    @Test func recordingAddsTheKeyAndSavesIt() throws {
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

    @Test func aShortcutAnotherCommandHasIsRefusedAndSaid() throws {
        let controller = makeController()
        try press("add-shortcut-reset", in: controller)
        try recorder(in: controller).keyDown(with: keyDown(kVK_ANSI_U, "u"))

        #expect(store.settings.shortcuts.isDefault)
        #expect(controller.messages[.reset] == "U is already used by Undo Split.")
        let message: NSTextField? = find("shortcut-message-reset", in: controller.view)
        #expect(message?.stringValue == "U is already used by Undo Split.")
        #expect(changes == 0)
    }

    @Test func theAppsOwnMenuShortcutsAreRefused() throws {
        let controller = makeController()
        try press("add-shortcut-undo_all_pauses", in: controller)
        try recorder(in: controller).keyDown(with: keyDown(kVK_ANSI_Q, "q", flags: .command))
        #expect(controller.messages[.undoAllPauses] == "⌘Q is kept for the app's menus.")
        #expect(store.settings.shortcuts.isDefault)
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

    @Test func restoreDefaultsPutsBackEveryShortcut() throws {
        let controller = makeController()
        try press("shortcut-undo_split-0", in: controller)
        try press("add-shortcut-reset", in: controller)
        try recorder(in: controller).keyDown(with: keyDown(kVK_ANSI_U, "u"))
        #expect(!store.settings.shortcuts.isDefault)

        try press("restore-default-shortcuts", in: controller)
        #expect(store.settings.shortcuts.isDefault)
        #expect(changes == 3)
    }

    @Test func theWindowIsNamedAndClosable() {
        let controller = SettingsWindowController(store: store, onChange: {})
        let window = controller.window
        #expect(window?.title == "Settings")
        #expect(window?.styleMask.contains(.closable) == true)
        #expect(window?.accessibilityIdentifier() == "settings-window")
    }
}
