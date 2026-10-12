import Foundation
import Testing

@testable import LiveSplitOne

/// Reading untrusted paths: a splits file's `<LayoutPath>` and a hand-edited `app.toml` can name
/// anything (spec §7, §10).
@Suite struct FileLoadErrorTests {
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    private func fifo() throws -> URL {
        let url = folder.url.appending(path: "pipe")
        #expect(mkfifo(url.path, 0o600) == 0)
        return url
    }

    @Test(.timeLimit(.minutes(1))) func aDeviceIsntRead() {
        let url = URL(filePath: "/dev/zero")
        #expect(throws: FileLoadError.unreadable("It isn't a regular file.")) {
            try SplitsFile.load(url)
        }
        #expect(throws: FileLoadError.unreadable("It isn't a regular file.")) {
            try LayoutFile.load(url)
        }
    }

    @Test(.timeLimit(.minutes(1))) func aPipeIsntReadAndDoesntHang() throws {
        let url = try fifo()
        #expect(throws: FileLoadError.unreadable("It isn't a regular file.")) {
            try SplitsFile.load(url)
        }
        #expect(throws: FileLoadError.unreadable("It isn't a regular file.")) {
            try LayoutFile.load(url)
        }
    }

    @Test(.timeLimit(.minutes(1))) func aLinkToAPipeIsntRead() throws {
        let link = folder.url.appending(path: "link.lss")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: try fifo())
        #expect(throws: FileLoadError.unreadable("It isn't a regular file.")) {
            try SplitsFile.load(link)
        }
    }

    /// The file is checked through the descriptor it was opened as, with no check of the path
    /// before: a pipe put there after any such check is refused and doesn't block.
    @Test(.timeLimit(.minutes(1))) func aPipeIsRefusedByTheReadItself() throws {
        #expect(throws: FileLoadError.unreadable("It isn't a regular file.")) {
            try FileLoadError.readBounded(try fifo(), limit: 100)
        }
    }

    @Test func aFolderIsntRead() {
        #expect(throws: FileLoadError.unreadable("It isn't a regular file.")) {
            try LayoutFile.load(folder.url)
        }
    }

    @Test func aFileOverTheCapIsntRead() throws {
        let url = folder.url.appending(path: "Huge.lss")
        let handle = try { () throws -> FileHandle in
            FileManager.default.createFile(atPath: url.path, contents: nil)
            return try FileHandle(forWritingTo: url)
        }()
        try handle.truncate(atOffset: UInt64(FileLoadError.sizeLimit) + 1)
        try handle.close()
        #expect(throws: FileLoadError.unreadable("It's too large to be a splits or layout file.")) {
            try SplitsFile.load(url)
        }
    }

    @Test func theReadItselfIsBounded() throws {
        let url = folder.url.appending(path: "Grown.lss")
        try Data(count: 11).write(to: url)
        #expect(try FileLoadError.readBounded(url, limit: 11).count == 11)
        #expect(throws: FileLoadError.unreadable("It's too large to be a splits or layout file.")) {
            try FileLoadError.readBounded(url, limit: 10)
        }
    }

    /// WSplit splits name their icons by path and livesplit-core reads them without a limit,
    /// when it is given a path to load files from (it isn't: see `SplitsFile.load`).
    @Test(.timeLimit(.minutes(1))) func anIconPathInOtherSplitsIsntRead() throws {
        let url = folder.url.appending(path: "Run.wsplit")
        let text = """
            Title=Any%
            Attempts=1
            Offset=0
            Size=374,61
            Icons="/dev/zero","\(try fifo().path)"
            Introduction,0,85.48,85.48
            Jimmy,0,219.68,134.2

            """
        try text.write(to: url, atomically: true, encoding: .utf8)
        let run = try SplitsFile.load(url)
        #expect(run.len() == 2)
    }

    @Test func aFixtureStillLoads() throws {
        _ = try SplitsFile.load(Fixtures.url("GameTime.lss"))
        _ = try LayoutFile.load(Fixtures.url("TextShadow.ls1l"))
    }

    @Test func aMissingFileKeepsMacOSsReason() {
        let url = folder.url.appending(path: "Gone.lss")
        #expect(throws: FileLoadError.self) { try SplitsFile.load(url) }
    }
}
