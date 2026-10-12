import Testing

@testable import LiveSplitOne

@Suite struct ShortcutsTests {
    private func shortcut(_ text: String) -> Shortcut { Shortcut(text)! }

    @Test func theDefaults() {
        let shortcuts = Shortcuts()
        #expect(shortcuts.shortcuts(for: .startSplit) == [shortcut("Space")])
        #expect(shortcuts.shortcuts(for: .reset) == [shortcut("Backspace")])
        #expect(shortcuts.shortcuts(for: .undoSplit) == [shortcut("u")])
        #expect(shortcuts.shortcuts(for: .skipSplit) == [shortcut("s")])
        #expect(shortcuts.shortcuts(for: .pause) == [shortcut("p")])
        #expect(shortcuts.shortcuts(for: .undoAllPauses) == [])
        #expect(shortcuts.isDefault)
    }

    @Test func aShortcutFindsItsCommand() {
        let shortcuts = Shortcuts()
        #expect(shortcuts.command(for: shortcut("u")) == .undoSplit)
        #expect(shortcuts.command(for: shortcut("Shift+u")) == nil)
        #expect(shortcuts.command(for: shortcut("k")) == nil)
    }

    @Test func addingASecondShortcut() {
        var shortcuts = Shortcuts()
        #expect(shortcuts.add(shortcut("Numpad1"), to: .startSplit) == nil)
        #expect(shortcuts.shortcuts(for: .startSplit) == [shortcut("Space"), shortcut("Numpad1")])
        #expect(shortcuts.command(for: shortcut("Numpad1")) == .startSplit)
        #expect(!shortcuts.isDefault)
    }

    @Test func addingOneThatAnotherCommandHasIsRefused() {
        var shortcuts = Shortcuts()
        #expect(shortcuts.add(shortcut("u"), to: .reset) == .usedBy(.undoSplit))
        #expect(shortcuts.shortcuts(for: .reset) == [shortcut("Backspace")])
    }

    @Test func addingOneTheCommandHasChangesNothing() {
        var shortcuts = Shortcuts()
        #expect(shortcuts.add(shortcut("Space"), to: .startSplit) == nil)
        #expect(shortcuts.isDefault)
    }

    @Test(arguments: [
        "Meta+q", "Meta+h", "Alt+Meta+h", "Meta+m", "Meta+,", "Meta+w", "Meta+s", "Shift+Meta+s",
    ])
    func reservedShortcutsAreRefused(_ text: String) {
        var shortcuts = Shortcuts()
        #expect(shortcuts.add(shortcut(text), to: .undoAllPauses) == .reserved)
        #expect(shortcuts.isDefault)
    }

    @Test func removingAndRestoringTheDefaults() {
        var shortcuts = Shortcuts()
        shortcuts.remove(shortcut("Space"), from: .startSplit)
        #expect(shortcuts.shortcuts(for: .startSplit) == [])
        #expect(shortcuts.add(shortcut("Space"), to: .reset) == nil)
        shortcuts.restoreDefaults()
        #expect(shortcuts == Shortcuts())
    }

    @Test func puttingBackTheDefaultsByHandCountsAsDefault() {
        var shortcuts = Shortcuts()
        shortcuts.remove(shortcut("u"), from: .undoSplit)
        #expect(shortcuts.add(shortcut("u"), to: .undoSplit) == nil)
        #expect(shortcuts.isDefault)
    }
}
