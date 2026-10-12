import AppKit

/// What the user chose in the reset question.
enum ResetAnswer: Sendable {
    case yes, no, dontReset
}

/// The *Yes / No / Don't Reset* alert for a reset with new best times, when the setting is
/// *Ask* (spec §7.1).
@MainActor
enum ResetQuestion {
    static func alert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Do you want to update your best times?"
        alert.informativeText = "This attempt has beaten some of your best times."
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        alert.addButton(withTitle: "Don't Reset")
        return alert
    }

    /// Runs the alert app-modal and returns the answer.
    static func ask() -> ResetAnswer {
        switch alert().runModal() {
        case .alertFirstButtonReturn: .yes
        case .alertSecondButtonReturn: .no
        default: .dontReset
        }
    }
}
