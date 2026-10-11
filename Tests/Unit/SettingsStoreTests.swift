import Foundation
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct SettingsStoreTests {
    let unified = RecordingUnifiedLog()

    func makeStore(_ folder: TemporaryFolder) -> SettingsStore {
        let logs = folder.url.appending(path: "Logs", directoryHint: .isDirectory)
        let log = Log(directory: logs, unified: unified, calendar: TestCalendar.london)
        return SettingsStore(
            directory: folder.url.appending(path: "Config", directoryHint: .isDirectory),
            log: log)
    }

    func configNames(_ folder: TemporaryFolder) throws -> [String] {
        let config = folder.url.appending(path: "Config").path
        guard FileManager.default.fileExists(atPath: config) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: config).sorted()
    }

    func writeConfig(_ folder: TemporaryFolder, _ name: String, _ text: String) throws {
        let config = folder.url.appending(path: "Config", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try text.write(to: config.appending(path: name), atomically: true, encoding: .utf8)
    }

    func readConfig(_ folder: TemporaryFolder, _ name: String) throws -> String {
        try String(contentsOf: folder.url.appending(path: "Config/\(name)"), encoding: .utf8)
    }

    var errors: [String] { unified.entries.filter { $0.category == .error }.map(\.message) }

    @Test func droppedShortcutsAreLogged() throws {
        let folder = try TemporaryFolder()
        try writeConfig(folder, "app.toml", "[shortcuts]\nreset = [\"Ctrl+u\"]\n")
        let store = makeStore(folder)
        #expect(store.loadOutcome == .loaded)
        #expect(
            unified.entries.contains {
                $0.category == .error
                    && $0.message == "Ignored a shortcut in \(store.file.path): "
                        + #""Ctrl+u" for reset: it isn't a shortcut"#
            })
    }

    @Test func withNoFileTheDefaultsAreUsedAndNothingIsWritten() throws {
        let folder = try TemporaryFolder()
        let store = makeStore(folder)
        #expect(store.settings == Settings())
        #expect(store.loadOutcome == .missing)
        #expect(try configNames(folder).isEmpty)
        #expect(errors.isEmpty)
    }

    @Test func everySettingSurvivesARelaunch() throws {
        let folder = try TemporaryFolder()
        let first = makeStore(folder)
        first.update { $0 = SettingsTests.everySetting }
        let second = makeStore(folder)
        #expect(second.loadOutcome == .loaded)
        #expect(second.settings == SettingsTests.everySetting)
    }

    @Test func savingLeavesOnlyTheFileWithAHeader() throws {
        let folder = try TemporaryFolder()
        let store = makeStore(folder)
        store.update { $0.alwaysOnTop = true }
        #expect(try configNames(folder) == ["app.toml"])
        #expect(try readConfig(folder, "app.toml").hasPrefix("# LiveSplit One for macOS settings."))
    }

    @Test func anUpdateThatChangesNothingDoesNotWrite() throws {
        let folder = try TemporaryFolder()
        let store = makeStore(folder)
        store.update { $0.alwaysOnTop = false }
        #expect(try configNames(folder).isEmpty)
        store.update { $0.alwaysOnTop = true }
        let saved =
            try FileManager.default.attributesOfItem(
                atPath: store.file.path)[.modificationDate] as? Date
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: store.file.path)
        store.update { $0.alwaysOnTop = true }
        let after =
            try FileManager.default.attributesOfItem(
                atPath: store.file.path)[.modificationDate] as? Date
        #expect(saved != nil)
        #expect(after == Date(timeIntervalSince1970: 0))
    }

    @Test func aBrokenFileIsKeptAsBadAndTheDefaultsAreUsed() throws {
        let folder = try TemporaryFolder()
        try writeConfig(folder, "app.toml", "always_on_top = \n")
        let store = makeStore(folder)
        #expect(store.settings == Settings())
        guard case .recovered(let reason) = store.loadOutcome else {
            Issue.record("expected .recovered, got \(store.loadOutcome)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(try configNames(folder) == ["app.toml.bad"])
        #expect(try readConfig(folder, "app.toml.bad") == "always_on_top = \n")
        #expect(errors.count == 1)
        #expect(errors.first?.hasPrefix("Couldn't read the settings in ") == true)
        #expect(errors.first?.contains("kept as app.toml.bad") == true)
    }

    @Test func afterABrokenFileTheNextChangeWritesANewOne() throws {
        let folder = try TemporaryFolder()
        try writeConfig(folder, "app.toml", "not toml at all [")
        let store = makeStore(folder)
        store.update { $0.alwaysOnTop = true }
        #expect(try configNames(folder) == ["app.toml", "app.toml.bad"])
        #expect(makeStore(folder).settings.alwaysOnTop)
    }

    @Test func aKeyWithTheWrongTypeMakesTheFileBroken() throws {
        let folder = try TemporaryFolder()
        try writeConfig(folder, "app.toml", "always_on_top = \"yes\"\n")
        let store = makeStore(folder)
        guard case .recovered = store.loadOutcome else {
            Issue.record("expected .recovered, got \(store.loadOutcome)")
            return
        }
        #expect(try configNames(folder) == ["app.toml.bad"])
    }

    @Test func anOlderBadFileIsReplaced() throws {
        let folder = try TemporaryFolder()
        try writeConfig(folder, "app.toml.bad", "older")
        try writeConfig(folder, "app.toml", "newer [")
        _ = makeStore(folder)
        #expect(try readConfig(folder, "app.toml.bad") == "newer [")
    }

    @Test func anUnreadableFileIsMovedAside() throws {
        let folder = try TemporaryFolder()
        try writeConfig(folder, "app.toml", "always_on_top = true\n")
        let file = folder.url.appending(path: "Config/app.toml")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        let store = makeStore(folder)
        guard case .recovered = store.loadOutcome else {
            Issue.record("expected .recovered, got \(store.loadOutcome)")
            return
        }
        #expect(try configNames(folder) == ["app.toml.bad"])
        let bad = folder.url.appending(path: "Config/app.toml.bad")
        #expect(FileManager.default.isReadableFile(atPath: bad.path))
    }

    @Test func aFileThatCantBeMovedAsideIsNeverOverwritten() throws {
        let folder = try TemporaryFolder()
        try writeConfig(folder, "app.toml", "broken [")
        let config = folder.url.appending(path: "Config")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: config.path)
        defer {
            // Built from `folder`, so it stays alive until the folder is writable again.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: folder.url.appending(path: "Config").path)
        }
        let store = makeStore(folder)
        guard case .unrecoverable = store.loadOutcome else {
            Issue.record("expected .unrecoverable, got \(store.loadOutcome)")
            return
        }
        store.update { $0.alwaysOnTop = true }
        #expect(store.settings.alwaysOnTop)
        #expect(try readConfig(folder, "app.toml") == "broken [")
        #expect(errors.count == 1)
        #expect(errors.first?.contains("aren't saved until the app restarts") == true)
    }

    @Test func aSymlinkedBrokenFileLeavesItsTargetsPermissionsAlone() throws {
        let folder = try TemporaryFolder()
        let target = folder.url.appending(path: "target.toml")
        try "broken [".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let config = folder.url.appending(path: "Config", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: config.appending(path: "app.toml"), withDestinationURL: target)
        let store = makeStore(folder)
        guard case .recovered = store.loadOutcome else {
            Issue.record("expected .recovered, got \(store.loadOutcome)")
            return
        }
        let bad = config.appending(path: "app.toml.bad").path
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: bad)) != nil)
        let mode =
            try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions]
            as? Int
        #expect(mode == 0o600)
    }

    @Test func savingThroughASymlinkKeepsTheLink() throws {
        let folder = try TemporaryFolder()
        let target = folder.url.appending(path: "target.toml")
        try "always_on_top = false\n".write(to: target, atomically: true, encoding: .utf8)
        let config = folder.url.appending(path: "Config", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        let link = config.appending(path: "app.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = makeStore(folder)
        store.update { $0.alwaysOnTop = true }
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(makeStore(folder).settings.alwaysOnTop)
    }

    @Test func aFailedSaveIsLoggedAndTheChangeStillApplies() throws {
        let folder = try TemporaryFolder()
        // A file where the settings folder should be.
        try "".write(to: folder.url.appending(path: "Config"), atomically: true, encoding: .utf8)
        let store = makeStore(folder)
        store.update { $0.alwaysOnTop = true }
        store.update { $0.lastServerURL = "ws://pc:16834" }
        #expect(store.settings.alwaysOnTop)
        #expect(store.settings.lastServerURL == "ws://pc:16834")
        #expect(errors.count == 2)
        #expect(errors.allSatisfy { $0.hasPrefix("Couldn't save the settings to ") })
    }

    @Test func readingAndSavingAreLogged() throws {
        let folder = try TemporaryFolder()
        let store = makeStore(folder)
        store.update { $0.alwaysOnTop = true }
        _ = makeStore(folder)
        let app = unified.entries.filter { $0.category == .app }.map(\.message)
        #expect(app.contains { $0.hasPrefix("No settings file yet at ") })
        #expect(app.contains { $0.hasPrefix("Saved the settings to ") })
        #expect(app.contains { $0.hasPrefix("Read the settings from ") })
    }
}
