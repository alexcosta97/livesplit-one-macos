import Foundation
import LiveSplitCore
import Testing

@testable import LiveSplitOne

@Suite struct SplitsFileTests {
    @Test func aLiveSplitFileOpens() throws {
        let run = try SplitsFile.load(Fixtures.url("GameTime.lss"))
        #expect(run.len() > 1)
    }

    @Test func anotherFormatOpens() throws {
        let run = try SplitsFile.load(Fixtures.url("Llanfair.lfs"))
        #expect(run.len() > 0)
    }

    @Test func aFileThatIsntSplitsIsRefused() {
        #expect(throws: FileLoadError.notSplits) {
            try SplitsFile.load(Fixtures.url("NotSplits.txt"))
        }
    }

    @Test func splitsWithNoSegmentsAreRefused() {
        #expect(throws: FileLoadError.notSplits) {
            try SplitsFile.load(Fixtures.url("Empty.lss"))
        }
    }

    @Test func anEmptyFileIsRefused() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "empty.lss")
        try Data().write(to: url)
        #expect(throws: FileLoadError.notSplits) { try SplitsFile.load(url) }
    }

    @Test func aMissingFileGivesMacOSsReason() throws {
        let folder = try TemporaryFolder()
        do {
            _ = try SplitsFile.load(folder.url.appending(path: "gone.lss"))
            Issue.record("it loaded")
        } catch {
            guard case .unreadable(let reason) = error else {
                Issue.record("\(error)")
                return
            }
            #expect(reason.contains("gone.lss"))
        }
    }

    @Test(
        arguments: [
            (nil, true), ("/a/Run.lss", false), ("/a/Run.LSS", false), ("/a/Run.lfs", true),
            ("/a/Run", true),
        ] as [(String?, Bool)])
    func onlyAnLssPathCanBeSavedInPlace(path: String?, needsNewName: Bool) {
        #expect(SplitsFile.needsNewName(path) == needsNewName)
    }

    @Test func aFolderIsUnreadableNotNotSplits() throws {
        let folder = try TemporaryFolder()
        do {
            _ = try SplitsFile.load(folder.url)
            Issue.record("it loaded")
        } catch {
            guard case .unreadable = error else {
                Issue.record("\(error)")
                return
            }
        }
    }

    @Test func theSuggestedNameKeepsTheFileNameWithLss() throws {
        let run = try SplitsFile.load(Fixtures.url("Llanfair.lfs"))
        #expect(SplitsFile.suggestedName(path: "/a/My Run.lfs", run: run) == "My Run.lss")
    }

    @Test @MainActor func aRunWithNoFileIsNamedAfterItsGameAndCategory() {
        let run = TimerContent.defaultRun()
        // LiveSplit One's new run has no game or category.
        #expect(SplitsFile.suggestedName(path: nil, run: run) == "Splits.lss")
    }

    @Test func messagesNameTheFile() {
        #expect(
            FileLoadError.notSplits.message(file: "a.txt")
                == "\"a.txt\" isn't splits LiveSplit One for macOS can read.")
        #expect(
            FileLoadError.notLayout.message(file: "a.txt")
                == "\"a.txt\" isn't a layout LiveSplit One for macOS can read.")
        #expect(FileLoadError.unreadable("No such file.").message(file: "a") == "No such file.")
    }

    @Test func writingReplacesTheFileAndFollowsALink() throws {
        let folder = try TemporaryFolder()
        let target = folder.url.appending(path: "target.lss")
        let link = folder.url.appending(path: "link.lss")
        try "old".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try TextFile.write("new", to: link)
        #expect(try String(contentsOf: target, encoding: .utf8) == "new")
        let type = try FileManager.default.attributesOfItem(atPath: link.path)[.type]
        #expect(type as? FileAttributeType == .typeSymbolicLink)
    }

    @Test func aFailedWriteThrowsAndLeavesTheFileAlone() throws {
        let folder = try TemporaryFolder()
        let locked = folder.url.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        let target = locked.appending(path: "target.lss")
        try "old".write(to: target, atomically: true, encoding: .utf8)
        // An atomic write needs a new file beside the target, which a read-only folder refuses.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        #expect(throws: (any Error).self) { try TextFile.write("new", to: target) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "old")
        #expect(throws: (any Error).self) {
            try TextFile.write("new", to: folder.url.appending(path: "missing/x.lss"))
        }
    }
}
