import AppKit

extension Shortcut {
    /// The shortcut a key press is, or `nil` for one that is neither a named key nor a key that
    /// types one visible character (a dead key alone, say). Only ⇧ ⌃ ⌥ ⌘ count: Caps Lock and the
    /// function and numeric-pad flags AppKit adds by itself don't (spec §7.2).
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.alt) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.meta) }

        if let named = NamedKey.forKeyCode(event.keyCode) {
            self.init(key: .named(named), modifiers: modifiers)
        } else if let typed = event.characters(byApplyingModifiers: []),
            let character = Self.keyCharacter(typed)
        {
            self.init(key: .character(character), modifiers: modifiers)
        } else {
            return nil
        }
    }

    /// What a menu item shows for it, or `nil` for a keypad key, which a menu can't tell from the
    /// main key. Menus only show it: `TimerMenus` stops them from running it (spec §7.2).
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        let keyText: String
        switch key {
        case .character(let character):
            keyText = String(character)
        case .named(let named):
            guard let equivalent = named.menuKeyEquivalent else { return nil }
            keyText = equivalent
        }
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.alt) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.meta) { flags.insert(.command) }
        return (keyText, flags)
    }
}

extension Shortcut.NamedKey {
    /// The key equivalent an `NSMenuItem` shows for this key, or `nil` for keypad keys.
    var menuKeyEquivalent: String? {
        switch self {
        case .space: " "
        case .backspace: Self.scalar(NSBackspaceCharacter)
        case .delete: Self.scalar(NSDeleteFunctionKey)
        case .enter: "\r"
        case .tab: "\t"
        case .escape: "\u{1B}"
        case .up: Self.scalar(NSUpArrowFunctionKey)
        case .down: Self.scalar(NSDownArrowFunctionKey)
        case .left: Self.scalar(NSLeftArrowFunctionKey)
        case .right: Self.scalar(NSRightArrowFunctionKey)
        case .home: Self.scalar(NSHomeFunctionKey)
        case .end: Self.scalar(NSEndFunctionKey)
        case .pageUp: Self.scalar(NSPageUpFunctionKey)
        case .pageDown: Self.scalar(NSPageDownFunctionKey)
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .f13, .f14, .f15,
            .f16, .f17, .f18, .f19, .f20:
            // "F5" is NSF1FunctionKey + 4; the function keys' characters are consecutive.
            Self.scalar(NSF1FunctionKey + Int(rawValue.dropFirst())! - 1)
        case .numpad0, .numpad1, .numpad2, .numpad3, .numpad4, .numpad5, .numpad6, .numpad7,
            .numpad8, .numpad9, .numpadDecimal, .numpadAdd, .numpadSubtract, .numpadMultiply,
            .numpadDivide, .numpadEnter, .numpadEqual, .numpadClear:
            nil
        }
    }

    private static func scalar(_ value: Int) -> String {
        String(Character(UnicodeScalar(UInt32(value))!))
    }
}
