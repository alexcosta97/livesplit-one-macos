import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct FileAlertsTests {
    @Test func saveChangesNamesTheFile() {
        let alert = SystemFileAlerts.saveChanges(name: "Celeste.lss")
        #expect(alert.messageText == "Do you want to save the changes to \"Celeste.lss\"?")
        #expect(alert.informativeText == "Your changes will be lost if you don't save them.")
        #expect(alert.buttons.map(\.title) == ["Save", "Don't Save", "Cancel"])
    }

    @Test func saveChangesWithoutAFileSaysYourSplits() {
        let alert = SystemFileAlerts.saveChanges(name: nil)
        #expect(alert.messageText == "Do you want to save the changes to your splits?")
        #expect(alert.informativeText == "Your changes will be lost if you don't save them.")
    }

    @Test func saveIsTheDefaultAndEscapeCancels() {
        let alert = SystemFileAlerts.saveChanges(name: "A.lss")
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[2].keyEquivalent == "\u{1b}")
    }

    @Test func choicesMapFromTheButtonsInOrder() {
        #expect(SystemFileAlerts.choice(for: .alertFirstButtonReturn) == .save)
        #expect(SystemFileAlerts.choice(for: .alertSecondButtonReturn) == .dontSave)
        #expect(SystemFileAlerts.choice(for: .alertThirdButtonReturn) == .cancel)
    }

    @Test func anyOtherResponseCancels() {
        #expect(SystemFileAlerts.choice(for: .cancel) == .cancel)
        #expect(SystemFileAlerts.choice(for: .abort) == .cancel)
        #expect(SystemFileAlerts.choice(for: .stop) == .cancel)
        #expect(SystemFileAlerts.choice(for: .OK) == .cancel)
    }

    @Test func loadFailedShowsTheErrorsMessage() {
        let alert = SystemFileAlerts.loadFailed(.notSplits, file: "Notes.txt")
        #expect(alert.messageText == "Couldn't open \"Notes.txt\"")
        #expect(
            alert.informativeText
                == "\"Notes.txt\" isn't splits LiveSplit One for macOS can read.")
        #expect(alert.alertStyle == .warning)
        #expect(alert.buttons.map(\.title) == ["OK"])
    }

    @Test func loadFailedShowsMacOSsReasonForAnUnreadableFile() {
        let alert = SystemFileAlerts.loadFailed(
            .unreadable("The file doesn't exist."), file: "Gone.lss")
        #expect(alert.informativeText == "The file doesn't exist.")
    }

    @Test func saveFailedShowsTheReason() {
        let alert = SystemFileAlerts.saveFailed(reason: "The disk is full.", file: "A.lss")
        #expect(alert.messageText == "Couldn't save \"A.lss\"")
        #expect(alert.informativeText == "The disk is full.")
        #expect(alert.alertStyle == .warning)
        #expect(alert.buttons.map(\.title) == ["OK"])
    }

    @Test func eachAlertWindowHasAnIdentifier() {
        #expect(
            SystemFileAlerts.saveChanges(name: nil).window.accessibilityIdentifier()
                == "file-alert-save-changes")
        #expect(
            SystemFileAlerts.loadFailed(.notLayout, file: "a").window.accessibilityIdentifier()
                == "file-alert-load-failed")
        #expect(
            SystemFileAlerts.saveFailed(reason: "r", file: "a").window.accessibilityIdentifier()
                == "file-alert-save-failed")
    }
}
