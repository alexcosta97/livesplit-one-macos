import AppKit
import Foundation
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct ConfigFolderTests {
    @Test func theStandardFolderIsInApplicationSupport() {
        let home = URL(filePath: "/Users/runner", directoryHint: .isDirectory)
        #expect(
            ConfigFolder.standard(home: home).path
                == "/Users/runner/Library/Application Support/livesplit-one-macos")
    }

    @Test func aLaunchArgumentNamesTheFolder() {
        let arguments = ["app", "-LSOLogDirectory", "/tmp/logs", "-LSOConfigDirectory", "/tmp/c"]
        #expect(
            LaunchOverrides.directory(
                after: LaunchOverrides.configDirectoryArgument, in: arguments)?
                .path == "/tmp/c")
    }

    @Test func theseTestsDoNotUseTheUsersSettings() throws {
        // The unit tests run inside the app, as a test host.
        #expect(ConfigFolder.current != ConfigFolder.standard())
        let delegate = try #require(NSApplication.shared.delegate as? AppDelegate)
        #expect(delegate.settings?.directory == ConfigFolder.current)
    }
}
