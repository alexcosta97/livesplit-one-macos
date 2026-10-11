import Testing

@testable import LiveSplitOne

@Suite struct ShortcutTests {
    @Test(arguments: [
        "Space", "Backspace", "u", "s", "p", "Numpad1", "F12", "Control+Shift+Space",
        "Control+Alt+Shift+Meta+k", "Meta+,", "+", "Control++", "/", "Shift+/", "é",
    ])
    func textRoundTrips(_ text: String) throws {
        let shortcut = try #require(Shortcut(text))
        #expect(shortcut.description == text)
        #expect(Shortcut(shortcut.description) == shortcut)
    }

    @Test func aCharacterKeyAndItsModifiers() throws {
        let shortcut = try #require(Shortcut("Control+Shift+u"))
        #expect(shortcut.key == .character("u"))
        #expect(shortcut.modifiers == [.control, .shift])
    }

    @Test func aNamedKey() throws {
        #expect(Shortcut("Numpad1")?.key == .named(.numpad1))
        #expect(Shortcut("Space")?.key == .named(.space))
        #expect(Shortcut("Backspace")?.modifiers == [])
    }

    @Test func modifiersAreWrittenInMenuOrderWhateverOrderTheyWereIn() {
        #expect(Shortcut("Meta+Shift+Alt+Control+k")?.description == "Control+Alt+Shift+Meta+k")
    }

    @Test func capitalLettersReadAsLowercase() {
        #expect(Shortcut("U") == Shortcut("u"))
        #expect(Shortcut("Shift+U")?.description == "Shift+u")
    }

    @Test(arguments: [
        "", "Ctrl+u", "Shift+Shift+u", "uu", "Numpad10", " ", "Control+", "Control+Space+u",
        "space", "\t", "Control+ ", "\u{F700}",
    ])
    func textThatIsntAShortcut(_ text: String) {
        #expect(Shortcut(text) == nil)
    }

    @Test func howTheSettingsWindowShowsIt() {
        #expect(Shortcut("Control+Shift+Space")?.displayName == "⌃⇧Space")
        #expect(Shortcut("u")?.displayName == "U")
        #expect(Shortcut("Alt+Meta+h")?.displayName == "⌥⌘H")
        #expect(Shortcut("Backspace")?.displayName == "⌫")
        #expect(Shortcut("Numpad1")?.displayName == "Keypad 1")
    }

    @Test func everyNamedKeyHasItsOwnKeyCode() {
        let codes = Shortcut.NamedKey.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
        for key in Shortcut.NamedKey.allCases {
            #expect(Shortcut.NamedKey.forKeyCode(key.keyCode) == key)
        }
        #expect(Shortcut.NamedKey.forKeyCode(32) == nil)  // kVK_ANSI_U: matched by character
    }
}
