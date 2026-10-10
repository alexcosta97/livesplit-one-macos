import Foundation
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct LogFolderOpenerTests {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Permission denied" }
    }

    func makeLog(_ folder: TemporaryFolder, _ unified: RecordingUnifiedLog) -> Log {
        Log(directory: folder.url, unified: unified, calendar: TestCalendar.london)
    }

    @Test func theFolderIsCreatedThenOpened() throws {
        let folder = try TemporaryFolder()
        let logs = folder.url.appending(path: "Logs", directoryHint: .isDirectory)
        var opened: [URL] = []
        let opener = LogFolderOpener(
            createDirectory: {
                try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
            },
            openInFinder: {
                opened.append($0)
                return true
            },
            log: makeLog(folder, RecordingUnifiedLog()))
        #expect(opener.open(logs))
        #expect(FileManager.default.fileExists(atPath: logs.path))
        #expect(opened == [logs])
    }

    @Test func aFolderThatCantBeCreatedIsLoggedAndNotOpened() throws {
        let folder = try TemporaryFolder()
        let unified = RecordingUnifiedLog()
        var opened = false
        let opener = LogFolderOpener(
            createDirectory: { _ in throw Failure() },
            openInFinder: { _ in
                opened = true
                return true
            },
            log: makeLog(folder, unified))
        #expect(!opener.open(URL(filePath: "/nowhere/Logs")))
        #expect(!opened)
        #expect(
            unified.entries.map(\.message) == [
                "Couldn't create the log folder /nowhere/Logs: Permission denied"
            ])
    }

    @Test func aFolderFinderCantOpenIsLogged() throws {
        let folder = try TemporaryFolder()
        let unified = RecordingUnifiedLog()
        let opener = LogFolderOpener(
            createDirectory: { _ in }, openInFinder: { _ in false },
            log: makeLog(folder, unified))
        #expect(!opener.open(URL(filePath: "/nowhere/Logs")))
        #expect(
            unified.entries.map(\.message) == [
                "Couldn't open the log folder /nowhere/Logs in Finder"
            ])
        #expect(unified.entries.map(\.category) == [.error])
    }
}
