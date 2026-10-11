import AppKit

/// A key-down event as AppKit makes one, for tests. `characters` is what the key types with
/// `flags` held; `characters(byApplyingModifiers:)` works it out again from the key code, on
/// the current layout (ABC on CI).
func keyDown(
    _ code: Int, _ characters: String, flags: NSEvent.ModifierFlags = [], isRepeat: Bool = false,
    windowNumber: Int = 0
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: isRepeat, keyCode: UInt16(code))!
}
