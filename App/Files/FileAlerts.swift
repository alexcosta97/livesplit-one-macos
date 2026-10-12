import AppKit

/// What the user chose when asked about unsaved changes (spec §7.3).
enum SaveChoice: Sendable { case save, dontSave, cancel }

/// The alerts files raise (spec §7, §10). A protocol so the model can be tested without
/// putting anything on screen.
@MainActor
protocol FileAlerts: AnyObject {
    /// Asks before unsaved splits are lost. `name` is the file name, or `nil` for a run with
    /// no file.
    func askToSave(name: String?) -> SaveChoice
    func showLoadFailed(_ error: FileLoadError, file: String)
    func showSaveFailed(reason: String, file: String)
}

/// The alerts as `NSAlert`s, built by the static factories for the headless tests and run
/// app-modal.
@MainActor
final class SystemFileAlerts: FileAlerts {
    func askToSave(name: String?) -> SaveChoice {
        Self.choice(for: Self.saveChanges(name: name).runModal())
    }

    func showLoadFailed(_ error: FileLoadError, file: String) {
        _ = Self.loadFailed(error, file: file).runModal()
    }

    func showSaveFailed(reason: String, file: String) {
        _ = Self.saveFailed(reason: reason, file: file).runModal()
    }

    /// Save, Don't Save and Cancel, in the order the buttons were added.
    static func choice(for response: NSApplication.ModalResponse) -> SaveChoice {
        switch response {
        case .alertFirstButtonReturn: .save
        case .alertSecondButtonReturn: .dontSave
        default: .cancel
        }
    }

    static func saveChanges(name: String?) -> NSAlert {
        let alert = NSAlert()
        alert.messageText =
            name.map { "Do you want to save the changes to \"\($0)\"?" }
            ?? "Do you want to save the changes to your splits?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        alert.window.setAccessibilityIdentifier("file-alert-save-changes")
        return alert
    }

    static func loadFailed(_ error: FileLoadError, file: String) -> NSAlert {
        warning(
            message: "Couldn't open \"\(file)\"", detail: error.message(file: file),
            identifier: "file-alert-load-failed")
    }

    static func saveFailed(reason: String, file: String) -> NSAlert {
        warning(
            message: "Couldn't save \"\(file)\"", detail: reason,
            identifier: "file-alert-save-failed")
    }

    private static func warning(message: String, detail: String, identifier: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.window.setAccessibilityIdentifier(identifier)
        return alert
    }
}
