import AppKit

/// Records the next key press as a shortcut (spec §7.3). Esc cancels. It takes key equivalents
/// too, so ⌘-combinations reach it before the menus, and the window can refuse ⌘Q rather than
/// quit.
@MainActor
final class KeyRecorderView: NSView {
    private let onRecord: (Shortcut) -> Void
    private let onCancel: () -> Void

    init(onRecord: @escaping (Shortcut) -> Void, onCancel: @escaping () -> Void) {
        self.onRecord = onRecord
        self.onCancel = onCancel
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: "Press a key…")
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityLabel("Press a key for the shortcut")
        setAccessibilityIdentifier("shortcut-recorder")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("KeyRecorderView is built in code")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        guard let shortcut = Shortcut(event: event) else {
            NSSound.beep()
            return
        }
        // The handlers rebuild the row, which removes this view: keep it alive until they return.
        withExtendedLifetime(self) {
            if shortcut == Shortcut(key: .named(.escape)) {
                onCancel()
            } else {
                onRecord(shortcut)
            }
        }
    }
}
