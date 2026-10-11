import AppKit
import Carbon.HIToolbox
import Testing

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

/// Whether the current keyboard layout is ABC or U.S., where a letter's key code types that
/// letter. Text Input Sources wants the main thread.
@MainActor
func keyboardLayoutIsABCOrUS() -> Bool {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
        let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
    else { return false }
    let identifier = Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    return ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains(identifier)
}

extension Trait where Self == ConditionTrait {
    /// For a test that turns a key code into the character it types, such as `kVK_ANSI_U` into
    /// `u`: only true on ABC and U.S., so it is skipped on AZERTY, Dvorak and other layouts
    /// rather than failing there. CI uses ABC.
    static var onABCOrUSLayout: Self {
        .enabled("needs the ABC or U.S. keyboard layout") {
            await keyboardLayoutIsABCOrUS()
        }
    }
}
