import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct LogFolderAlertTests {
    @Test func theAlertNamesTheFolder() {
        let alert = LogFolderAlert.make(
            folder: URL(filePath: "/Users/me/Library/Logs/livesplit-one-macos"))
        #expect(alert.messageText == "Couldn't open the log folder")
        #expect(
            alert.informativeText
                == "The log files belong in /Users/me/Library/Logs/livesplit-one-macos.")
        #expect(alert.buttons.map(\.title) == ["OK"])
    }
}
