import AppKit

/// The destructive actions the editor confirms first (spec §9).
enum Confirmation: Sendable { case clearHistory, clearTimes }

/// The questions the editor asks, so tests can answer them (spec §9).
@MainActor
protocol SplitsEditorPrompts: AnyObject {
    /// Asks for a name until `accept` returns true or the user cancels. When `accept` returns
    /// false the question is asked again with the refused-name text. Returns whether a name was
    /// accepted.
    func askName(title: String, prefill: String, accept: (String) -> Bool) -> Bool
    /// Whether the user confirmed the destructive action.
    func confirm(_ question: Confirmation) -> Bool
    /// An image file to use, or `nil`.
    func chooseImage() -> URL?
    func showIconFailed(_ error: FileLoadError, file: String)
}

/// The questions as `NSAlert`s, built by the static factories for the headless tests and run
/// app-modal: the editor's window is modal already, so they are not sheets (spec §9).
@MainActor
final class SystemSplitsEditorPrompts: SplitsEditorPrompts {
    private let picker: FilePicker

    init(picker: FilePicker) {
        self.picker = picker
    }

    func askName(title: String, prefill: String, accept: (String) -> Bool) -> Bool {
        Self.askName(title: title, prefill: prefill, accept: accept) { alert in
            let response = alert.runModal()
            return (response, (alert.accessoryView as? NSTextField)?.stringValue ?? "")
        }
    }

    func confirm(_ question: Confirmation) -> Bool {
        Self.isConfirmed(Self.confirmation(question).runModal())
    }

    func chooseImage() -> URL? {
        picker.fileToOpen(.image)
    }

    func showIconFailed(_ error: FileLoadError, file: String) {
        _ = Self.iconFailed(error, file: file).runModal()
    }

    /// The name loop. `present` shows an alert and returns the response and the text in its
    /// field; tests script it. Cancel returns false; OK with a refused name asks again with the
    /// typed text kept.
    static func askName(
        title: String, prefill: String, accept: (String) -> Bool,
        present: (NSAlert) -> (NSApplication.ModalResponse, String)
    ) -> Bool {
        var text = prefill
        var refused = false
        while true {
            let (response, typed) = present(
                nameAlert(title: title, prefill: text, refused: refused))
            guard response == .alertFirstButtonReturn else { return false }
            if accept(typed) { return true }
            text = typed
            refused = true
        }
    }

    /// A name question: a text field, **OK** and **Cancel**. `refused` adds the refused-name
    /// text.
    static func nameAlert(title: String, prefill: String, refused: Bool = false) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        if refused {
            alert.informativeText = "That name is already used, or starts with [Race]."
        }
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let field = NSTextField(string: prefill)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        field.setAccessibilityIdentifier("editor-name-field")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.setAccessibilityIdentifier("editor-alert-name")
        return alert
    }

    /// The destructive action first, **Cancel** second and on Escape.
    static func confirmation(_ question: Confirmation) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let action: String
        let identifier: String
        switch question {
        case .clearHistory:
            alert.messageText = "Clear the history?"
            alert.informativeText =
                "This removes every attempt and every segment's history. The personal best and the best segments stay."
            action = "Clear History"
            identifier = "editor-alert-clear-history"
        case .clearTimes:
            alert.messageText = "Clear the times?"
            alert.informativeText =
                "This removes the history, every time, the attempt count and the custom comparisons."
            action = "Clear Times"
            identifier = "editor-alert-clear-times"
        }
        alert.addButton(withTitle: action).hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.window.setAccessibilityIdentifier(identifier)
        return alert
    }

    /// Only the first button (the destructive action) confirms.
    static func isConfirmed(_ response: NSApplication.ModalResponse) -> Bool {
        response == .alertFirstButtonReturn
    }

    static func iconFailed(_ error: FileLoadError, file: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't use \"\(file)\" as an icon."
        alert.informativeText = error.message(file: file)
        alert.addButton(withTitle: "OK")
        alert.window.setAccessibilityIdentifier("editor-alert-icon-failed")
        return alert
    }
}
