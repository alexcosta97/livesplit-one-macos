import AppKit

/// Runs the Control commands' shortcuts while the timer window is key (spec §7.2), from a local
/// monitor, before the menus see the key. The menus only show the shortcuts.
@MainActor
final class ShortcutKeys {
    private let window: NSWindow
    private let shortcuts: @MainActor () -> Shortcuts
    private let perform: @MainActor (ControlCommand) -> Void
    private var monitor: Any?

    init(
        window: NSWindow, shortcuts: @escaping @MainActor () -> Shortcuts,
        perform: @escaping @MainActor (ControlCommand) -> Void
    ) {
        self.window = window
        self.shortcuts = shortcuts
        self.perform = perform
    }

    /// Starts watching key presses, for the rest of the app's life.
    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // AppKit calls this on the main thread.
            let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// Runs the shortcut's command, if `event` is one for the timer window. Returns whether the
    /// event was a shortcut, in which case nothing else should see it. A key repeat runs nothing,
    /// so holding a key down runs its command once.
    func consumes(_ event: NSEvent) -> Bool {
        guard event.windowNumber == window.windowNumber,
            let shortcut = Shortcut(event: event),
            let command = shortcuts().command(for: shortcut)
        else { return false }
        if !event.isARepeat { perform(command) }
        return true
    }
}
