import AppKit
import Carbon.HIToolbox
import Testing

@testable import LiveSplitOne

@MainActor
@Suite final class ShortcutKeysTests {
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless],
        backing: .buffered, defer: false)
    let other = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
        backing: .buffered, defer: false)
    var shortcuts = Shortcuts()
    var performed: [ControlCommand] = []

    private func makeKeys() -> ShortcutKeys {
        ShortcutKeys(
            window: window, shortcuts: { [unowned self] in shortcuts },
            perform: { [unowned self] in performed.append($0) })
    }

    private func press(
        _ code: Int, _ characters: String, flags: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false, in window: NSWindow? = nil
    ) -> NSEvent {
        keyDown(
            code, characters, flags: flags, isRepeat: isRepeat,
            windowNumber: (window ?? self.window).windowNumber)
    }

    @Test func theWindowsHaveNumbers() {
        #expect(window.windowNumber > 0 && other.windowNumber > 0)
        #expect(window.windowNumber != other.windowNumber)
    }

    @Test(.onABCOrUSLayout) func aShortcutRunsItsCommandAndGoesNoFurther() {
        let keys = makeKeys()
        #expect(keys.consumes(press(kVK_Space, " ")))
        #expect(keys.consumes(press(kVK_ANSI_U, "U", flags: .capsLock)))
        #expect(performed == [.startSplit, .undoSplit])
    }

    @Test func holdingAKeyDownRunsItOnce() {
        let keys = makeKeys()
        #expect(keys.consumes(press(kVK_Space, " ")))
        #expect(keys.consumes(press(kVK_Space, " ", isRepeat: true)))
        #expect(keys.consumes(press(kVK_Space, " ", isRepeat: true)))
        #expect(performed == [.startSplit])
    }

    @Test func keysForAnotherWindowGoOn() {
        let keys = makeKeys()
        #expect(!keys.consumes(press(kVK_Space, " ", in: other)))
        #expect(!keys.consumes(press(kVK_ANSI_U, "u", in: other)))
        #expect(performed.isEmpty)
    }

    @Test(.onABCOrUSLayout) func keysThatArentShortcutsGoOn() {
        let keys = makeKeys()
        #expect(!keys.consumes(press(kVK_ANSI_K, "k")))
        #expect(!keys.consumes(press(kVK_ANSI_Q, "q", flags: .command)))
        #expect(!keys.consumes(press(kVK_ANSI_U, "U", flags: .shift)))
        #expect(performed.isEmpty)
    }

    @Test(.onABCOrUSLayout) func changedShortcutsApplyAtOnce() {
        let keys = makeKeys()
        _ = shortcuts.add(Shortcut("k")!, to: .skipSplit)
        #expect(keys.consumes(press(kVK_ANSI_K, "k")))
        #expect(performed == [.skipSplit])
    }

    /// The Edit menu's keys can be shortcuts: in the timer window the shortcut runs, and
    /// elsewhere the key goes on to the Edit menu (spec §7).
    @Test(.onABCOrUSLayout) func anEditMenuKeyCanBeAShortcutInTheTimerWindowOnly() {
        let keys = makeKeys()
        _ = shortcuts.add(Shortcut(key: .character("z"), modifiers: .meta), to: .undoSplit)
        #expect(keys.consumes(press(kVK_ANSI_Z, "z", flags: .command)))
        #expect(!keys.consumes(press(kVK_ANSI_Z, "z", flags: .command, in: other)))
        #expect(performed == [.undoSplit])
    }
}
