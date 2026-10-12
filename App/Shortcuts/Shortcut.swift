import Carbon.HIToolbox

/// A keyboard shortcut: one key and the modifiers held with it (spec §7.2). Written as
/// `Control+Alt+Shift+Meta+key`, the modifiers in the order macOS menus show them.
struct Shortcut: Hashable, Sendable, CustomStringConvertible {
    var key: Key
    var modifiers: Modifiers

    enum Key: Hashable, Sendable {
        /// A key matched by the character it types with no modifiers on the current keyboard
        /// layout, as most Mac apps match their shortcuts. Always lowercase.
        case character(Character)
        /// A key that types nothing visible, or is on the numeric keypad: matched by its key code.
        case named(NamedKey)
    }

    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: UInt8
        static let control = Modifiers(rawValue: 1 << 0)
        static let alt = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let meta = Modifiers(rawValue: 1 << 3)

        /// Each modifier with its name in the text form and its symbol, in the order macOS menus
        /// show them: ⌃⌥⇧⌘. The names are livesplit-core's hotkey modifiers' names.
        static let ordered: [(modifier: Modifiers, name: String, symbol: String)] = [
            (.control, "Control", "⌃"), (.alt, "Alt", "⌥"), (.shift, "Shift", "⇧"),
            (.meta, "Meta", "⌘"),
        ]
    }

    init(key: Key, modifiers: Modifiers = []) {
        if case .character(let character) = key {
            assert(
                Self.keyCharacter(String(character)) == character,
                "A character key is one visible lowercase character")
        }
        self.key = key
        self.modifiers = modifiers
    }

    /// Reads the text form, such as `"u"`, `"Numpad1"` or `"Control+Shift+Space"`. `nil` if it
    /// isn't one: an unknown modifier, a modifier twice, or a key that isn't a name or a single
    /// visible character.
    init?(_ text: String) {
        let keyText: Substring
        let modifierText: Substring
        // "+" is the separator and also a key: "+" alone, or "…++" at the end, is the key "+".
        if text == "+" {
            (modifierText, keyText) = ("", "+")
        } else if text.hasSuffix("++") {
            // "++" alone has a separator and no modifier before it.
            guard text.count > 2 else { return nil }
            (modifierText, keyText) = (text.dropLast(2), "+")
        } else if let plus = text.lastIndex(of: "+") {
            (modifierText, keyText) = (text[..<plus], text[text.index(after: plus)...])
        } else {
            (modifierText, keyText) = ("", Substring(text))
        }

        var modifiers: Modifiers = []
        if !modifierText.isEmpty {
            for name in modifierText.split(separator: "+", omittingEmptySubsequences: false) {
                guard let entry = Modifiers.ordered.first(where: { $0.name == name }),
                    !modifiers.contains(entry.modifier)
                else { return nil }
                modifiers.insert(entry.modifier)
            }
        }

        if let named = NamedKey(rawValue: String(keyText)) {
            self.init(key: .named(named), modifiers: modifiers)
        } else if let character = Self.keyCharacter(keyText) {
            self.init(key: .character(character), modifiers: modifiers)
        } else {
            return nil
        }
    }

    /// The single visible character a key types, lowercased, or `nil` if `text` isn't one.
    static func keyCharacter(_ text: some StringProtocol) -> Character? {
        guard text.count == 1, let character = text.first,
            !character.isWhitespace,
            !character.unicodeScalars.contains(where: {
                $0.properties.generalCategory == .control
                    || $0.properties.generalCategory == .privateUse
            })
        else { return nil }
        let lower = character.lowercased()
        guard lower.count == 1 else { return nil }
        return lower.first
    }

    var description: String {
        let names = Modifiers.ordered.filter { modifiers.contains($0.modifier) }.map(\.name)
        let keyText =
            switch key {
            case .character(let character): String(character)
            case .named(let named): named.rawValue
            }
        return (names + [keyText]).joined(separator: "+")
    }

    /// How the Settings window shows it: the modifiers' symbols, then the key, such as `⌃⇧Space`.
    var displayName: String {
        let symbols = Modifiers.ordered.filter { modifiers.contains($0.modifier) }.map(\.symbol)
        let keyText =
            switch key {
            // Capitalised as menus show letters, unless that makes more than one: ß stays ß.
            case .character(let character):
                String(character).uppercased().count == 1
                    ? String(character).uppercased() : String(character)
            case .named(let named): named.symbol
            }
        return symbols.joined() + keyText
    }
}

extension Shortcut {
    /// Keys that type nothing visible, or that are also on the numeric keypad, so `1` and
    /// `Numpad1` are different shortcuts (spec §7.2). The raw value is the name in `app.toml`.
    enum NamedKey: String, CaseIterable, Sendable {
        case space = "Space"
        case backspace = "Backspace"
        case delete = "Delete"
        case enter = "Enter"
        case tab = "Tab"
        case escape = "Escape"
        case up = "Up"
        case down = "Down"
        case left = "Left"
        case right = "Right"
        case home = "Home"
        case end = "End"
        case pageUp = "PageUp"
        case pageDown = "PageDown"
        case f1 = "F1"
        case f2 = "F2"
        case f3 = "F3"
        case f4 = "F4"
        case f5 = "F5"
        case f6 = "F6"
        case f7 = "F7"
        case f8 = "F8"
        case f9 = "F9"
        case f10 = "F10"
        case f11 = "F11"
        case f12 = "F12"
        case f13 = "F13"
        case f14 = "F14"
        case f15 = "F15"
        case f16 = "F16"
        case f17 = "F17"
        case f18 = "F18"
        case f19 = "F19"
        case f20 = "F20"
        case numpad0 = "Numpad0"
        case numpad1 = "Numpad1"
        case numpad2 = "Numpad2"
        case numpad3 = "Numpad3"
        case numpad4 = "Numpad4"
        case numpad5 = "Numpad5"
        case numpad6 = "Numpad6"
        case numpad7 = "Numpad7"
        case numpad8 = "Numpad8"
        case numpad9 = "Numpad9"
        case numpadDecimal = "NumpadDecimal"
        case numpadAdd = "NumpadAdd"
        case numpadSubtract = "NumpadSubtract"
        case numpadMultiply = "NumpadMultiply"
        case numpadDivide = "NumpadDivide"
        case numpadEnter = "NumpadEnter"
        case numpadEqual = "NumpadEqual"
        case numpadClear = "NumpadClear"

        /// The key's code, which is the same on every Mac keyboard layout for these keys.
        var keyCode: UInt16 {
            let code =
                switch self {
                case .space: kVK_Space
                case .backspace: kVK_Delete
                case .delete: kVK_ForwardDelete
                case .enter: kVK_Return
                case .tab: kVK_Tab
                case .escape: kVK_Escape
                case .up: kVK_UpArrow
                case .down: kVK_DownArrow
                case .left: kVK_LeftArrow
                case .right: kVK_RightArrow
                case .home: kVK_Home
                case .end: kVK_End
                case .pageUp: kVK_PageUp
                case .pageDown: kVK_PageDown
                case .f1: kVK_F1
                case .f2: kVK_F2
                case .f3: kVK_F3
                case .f4: kVK_F4
                case .f5: kVK_F5
                case .f6: kVK_F6
                case .f7: kVK_F7
                case .f8: kVK_F8
                case .f9: kVK_F9
                case .f10: kVK_F10
                case .f11: kVK_F11
                case .f12: kVK_F12
                case .f13: kVK_F13
                case .f14: kVK_F14
                case .f15: kVK_F15
                case .f16: kVK_F16
                case .f17: kVK_F17
                case .f18: kVK_F18
                case .f19: kVK_F19
                case .f20: kVK_F20
                case .numpad0: kVK_ANSI_Keypad0
                case .numpad1: kVK_ANSI_Keypad1
                case .numpad2: kVK_ANSI_Keypad2
                case .numpad3: kVK_ANSI_Keypad3
                case .numpad4: kVK_ANSI_Keypad4
                case .numpad5: kVK_ANSI_Keypad5
                case .numpad6: kVK_ANSI_Keypad6
                case .numpad7: kVK_ANSI_Keypad7
                case .numpad8: kVK_ANSI_Keypad8
                case .numpad9: kVK_ANSI_Keypad9
                case .numpadDecimal: kVK_ANSI_KeypadDecimal
                case .numpadAdd: kVK_ANSI_KeypadPlus
                case .numpadSubtract: kVK_ANSI_KeypadMinus
                case .numpadMultiply: kVK_ANSI_KeypadMultiply
                case .numpadDivide: kVK_ANSI_KeypadDivide
                case .numpadEnter: kVK_ANSI_KeypadEnter
                case .numpadEqual: kVK_ANSI_KeypadEquals
                case .numpadClear: kVK_ANSI_KeypadClear
                }
            return UInt16(code)
        }

        /// How the Settings window shows it, as macOS shows these keys in menus.
        var symbol: String {
            switch self {
            case .space: "Space"
            case .backspace: "⌫"
            case .delete: "⌦"
            case .enter: "↩"
            case .tab: "⇥"
            case .escape: "⎋"
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            case .home: "↖"
            case .end: "↘"
            case .pageUp: "⇞"
            case .pageDown: "⇟"
            case .numpadDecimal: "Keypad ."
            case .numpadAdd: "Keypad +"
            case .numpadSubtract: "Keypad −"
            case .numpadMultiply: "Keypad ×"
            case .numpadDivide: "Keypad ÷"
            case .numpadEnter: "Keypad Enter"
            case .numpadEqual: "Keypad ="
            case .numpadClear: "Keypad Clear"
            default:
                // F1–F20 as they are; Numpad0–Numpad9 as "Keypad 0"–"Keypad 9".
                rawValue.hasPrefix("Numpad")
                    ? "Keypad " + rawValue.dropFirst("Numpad".count) : rawValue
            }
        }

        private static let byKeyCode = Dictionary(
            uniqueKeysWithValues: allCases.map { ($0.keyCode, $0) })

        /// The named key with this code, or `nil` for a key matched by its character.
        static func forKeyCode(_ code: UInt16) -> NamedKey? { byKeyCode[code] }
    }
}
