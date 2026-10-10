import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct LogFolderTests {
    @Test func theStandardFolderIsInLibraryLogs() {
        let home = URL(filePath: "/Users/runner", directoryHint: .isDirectory)
        #expect(
            LogFolder.standard(home: home).path == "/Users/runner/Library/Logs/livesplit-one-macos"
        )
    }

    @Test func aLaunchArgumentNamesTheFolder() {
        let arguments = ["/Applications/LiveSplit One.app", "-LSOLogDirectory", "/private/tmp/x"]
        #expect(
            LaunchOverrides.directory(after: "-LSOLogDirectory", in: arguments)?.path
                == "/private/tmp/x")
    }

    @Test func aMissingOrRelativeFolderIsIgnored() {
        #expect(LaunchOverrides.directory(after: "-LSOLogDirectory", in: ["app"]) == nil)
        #expect(
            LaunchOverrides.directory(after: "-LSOLogDirectory", in: ["app", "-LSOLogDirectory"])
                == nil)
        #expect(
            LaunchOverrides.directory(
                after: "-LSOLogDirectory", in: ["app", "-LSOLogDirectory", "relative/path"])
                == nil)
    }

    @Test func aTestHostLogsToATemporaryFolder() {
        let folder = LaunchOverrides.testHostDirectory(
            "Logs", environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"])
        #expect(folder?.path.hasPrefix(FileManager.default.temporaryDirectory.path) == true)
        #expect(LaunchOverrides.testHostDirectory("Logs", environment: [:]) == nil)
    }

    @Test func theseTestsDoNotLogToTheUsersFolder() {
        // The unit tests run inside the app, as a test host.
        #expect(Log.shared.directory != LogFolder.standard())
    }
}
