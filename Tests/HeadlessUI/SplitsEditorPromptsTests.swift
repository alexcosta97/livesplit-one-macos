import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct SplitsEditorPromptsTests {
    @Test func nameAlertHasTheTitleAndAPrefilledField() throws {
        let alert = SystemSplitsEditorPrompts.nameAlert(
            title: "Rename Comparison", prefill: "Old")
        #expect(alert.messageText == "Rename Comparison")
        #expect(alert.informativeText == "")
        #expect(alert.buttons.map(\.title) == ["OK", "Cancel"])
        let field = try #require(alert.accessoryView as? NSTextField)
        #expect(field.stringValue == "Old")
        #expect(alert.window.initialFirstResponder === field)
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
    }

    @Test func nameAlertCanShowTheRefusedNameText() {
        let alert = SystemSplitsEditorPrompts.nameAlert(
            title: "Add Comparison", prefill: "[Race]", refused: true)
        #expect(alert.informativeText == "That name is already used, or starts with [Race].")
    }

    @Test func clearHistoryConfirmation() {
        let alert = SystemSplitsEditorPrompts.confirmation(.clearHistory)
        #expect(alert.messageText == "Clear the history?")
        #expect(
            alert.informativeText
                == "This removes every attempt and every segment's history. The personal best and the best segments stay."
        )
        #expect(alert.buttons.map(\.title) == ["Clear History", "Cancel"])
        #expect(alert.buttons[0].hasDestructiveAction)
        #expect(!alert.buttons[1].hasDestructiveAction)
        #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
    }

    @Test func clearTimesConfirmation() {
        let alert = SystemSplitsEditorPrompts.confirmation(.clearTimes)
        #expect(alert.messageText == "Clear the times?")
        #expect(
            alert.informativeText
                == "This removes the history, every time, the attempt count and the custom comparisons."
        )
        #expect(alert.buttons.map(\.title) == ["Clear Times", "Cancel"])
        #expect(alert.buttons[0].hasDestructiveAction)
        #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
    }

    @Test func onlyTheFirstButtonConfirms() {
        #expect(SystemSplitsEditorPrompts.isConfirmed(.alertFirstButtonReturn))
        #expect(!SystemSplitsEditorPrompts.isConfirmed(.alertSecondButtonReturn))
        #expect(!SystemSplitsEditorPrompts.isConfirmed(.cancel))
    }

    @Test func iconFailedNamesTheFileAndTheReason() {
        let alert = SystemSplitsEditorPrompts.iconFailed(.notImage, file: "a.txt")
        #expect(alert.messageText == "Couldn't use \"a.txt\" as an icon.")
        #expect(alert.informativeText == "It isn't an image LiveSplit One for macOS can read.")
        #expect(alert.alertStyle == .warning)
        #expect(alert.buttons.map(\.title) == ["OK"])

        let other = SystemSplitsEditorPrompts.iconFailed(.unreadable("No access."), file: "b.png")
        #expect(other.informativeText == "No access.")
    }

    @Test func askNameReturnsTrueOnceAccepted() {
        var script: [(NSApplication.ModalResponse, String)] = [(.alertFirstButtonReturn, "Mine")]
        var accepted: [String] = []
        let result = SystemSplitsEditorPrompts.askName(
            title: "Add Comparison", prefill: "",
            accept: {
                accepted.append($0)
                return true
            },
            present: { _ in script.removeFirst() })
        #expect(result)
        #expect(accepted == ["Mine"])
    }

    @Test func askNameAsksAgainWithTheTypedTextWhenRefused() {
        var script: [(NSApplication.ModalResponse, String)] = [
            (.alertFirstButtonReturn, "[Race]"), (.alertFirstButtonReturn, "Fine"),
        ]
        var shown: [(String, Bool)] = []
        let result = SystemSplitsEditorPrompts.askName(
            title: "Add Comparison", prefill: "",
            accept: { $0 == "Fine" },
            present: { alert in
                let field = alert.accessoryView as? NSTextField
                shown.append((field?.stringValue ?? "?", !alert.informativeText.isEmpty))
                return script.removeFirst()
            })
        #expect(result)
        #expect(shown.map(\.0) == ["", "[Race]"])
        #expect(shown.map(\.1) == [false, true])
    }

    @Test func askNameReturnsFalseOnCancel() {
        var accepted = false
        let result = SystemSplitsEditorPrompts.askName(
            title: "Add Comparison", prefill: "x",
            accept: { _ in
                accepted = true
                return true
            },
            present: { _ in (.alertSecondButtonReturn, "x") })
        #expect(!result)
        #expect(!accepted)
    }

    @Test func askNameCanBeCancelledAfterARefusal() {
        var script: [(NSApplication.ModalResponse, String)] = [
            (.alertFirstButtonReturn, "bad"), (.alertSecondButtonReturn, "bad"),
        ]
        let result = SystemSplitsEditorPrompts.askName(
            title: "t", prefill: "", accept: { _ in false }, present: { _ in script.removeFirst() })
        #expect(!result)
    }
}
