import AppKit
import Carbon.HIToolbox
import Testing

@testable import LiveSplitOne

@Suite struct ShortcutEventTests {
    @Test(.onABCOrUSLayout) func aLetterIsItsLowercaseCharacter() {
        #expect(Shortcut(event: keyDown(kVK_ANSI_U, "u")) == Shortcut("u"))
        #expect(Shortcut(event: keyDown(kVK_ANSI_U, "U", flags: .shift)) == Shortcut("Shift+u"))
    }

    @Test(.onABCOrUSLayout) func optionDoesntChangeTheCharacter() {
        // Option+U types a dead key on ABC.
        #expect(Shortcut(event: keyDown(kVK_ANSI_U, "", flags: .option)) == Shortcut("Alt+u"))
    }

    @Test(.onABCOrUSLayout) func shiftedPunctuationIsTheUnshiftedKeyWithShift() {
        #expect(
            Shortcut(event: keyDown(kVK_ANSI_Slash, "?", flags: .shift)) == Shortcut("Shift+/"))
    }

    @Test(.onABCOrUSLayout) func capsLockAndTheFlagsAppKitAddsArentModifiers() {
        #expect(Shortcut(event: keyDown(kVK_ANSI_U, "U", flags: .capsLock)) == Shortcut("u"))
        #expect(
            Shortcut(event: keyDown(kVK_UpArrow, "\u{F700}", flags: [.numericPad, .function]))
                == Shortcut("Up"))
    }

    @Test func namedKeysAndTheirModifiers() {
        #expect(
            Shortcut(event: keyDown(kVK_Space, " ", flags: [.control, .shift]))
                == Shortcut("Control+Shift+Space"))
        #expect(Shortcut(event: keyDown(kVK_Delete, "\u{7F}")) == Shortcut("Backspace"))
        #expect(Shortcut(event: keyDown(kVK_F5, "\u{F708}", flags: .function)) == Shortcut("F5"))
    }

    @Test(.onABCOrUSLayout) func aKeypadDigitIsNotTheMainRowDigit() {
        #expect(
            Shortcut(event: keyDown(kVK_ANSI_Keypad1, "1", flags: .numericPad))
                == Shortcut("Numpad1"))
        #expect(Shortcut(event: keyDown(kVK_ANSI_1, "1")) == Shortcut("1"))
    }

    @Test func aKeyUpIsNoShortcut() {
        let up = NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "u", charactersIgnoringModifiers: "u", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_U))!
        #expect(Shortcut(event: up) == nil)
    }

    @Test func whatAMenuShows() throws {
        let u = try #require(Shortcut("u")?.menuKeyEquivalent)
        #expect(u.key == "u" && u.modifiers == [])
        let space = try #require(Shortcut("Control+Shift+Space")?.menuKeyEquivalent)
        #expect(space.key == " " && space.modifiers == [.control, .shift])
        #expect(Shortcut("Backspace")?.menuKeyEquivalent?.key == "\u{8}")
        #expect(
            Shortcut("F5")?.menuKeyEquivalent?.key
                == String(Character(UnicodeScalar(UInt32(NSF5FunctionKey))!)))
        #expect(Shortcut("Numpad1")?.menuKeyEquivalent == nil)
    }

    /// F1 to F20's characters are consecutive from `NSF1FunctionKey`, which is what
    /// `menuKeyEquivalent` counts on.
    @Test(arguments: 1...20)
    func aFunctionKeyShowsItsFunctionKeyCharacter(_ number: Int) throws {
        let key = try #require(Shortcut.NamedKey(rawValue: "F\(number)"))
        let scalar = try #require(UnicodeScalar(UInt32(NSF1FunctionKey + number - 1)))
        #expect(key.menuKeyEquivalent == String(Character(scalar)))
    }
}
