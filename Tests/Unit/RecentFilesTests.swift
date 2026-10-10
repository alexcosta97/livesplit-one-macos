import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct RecentFilesTests {
    @Test func theNewestIsFirst() {
        var recent = RecentFiles()
        recent.add("/a.lss")
        recent.add("/b.lss")
        #expect(recent.paths == ["/b.lss", "/a.lss"])
    }

    @Test func addingAgainMovesItToTheFront() {
        var recent = RecentFiles(["/a.lss", "/b.lss", "/c.lss"])
        recent.add("/c.lss")
        #expect(recent.paths == ["/c.lss", "/a.lss", "/b.lss"])
    }

    @Test func onlyTenAreKept() {
        var recent = RecentFiles()
        for number in 1...12 {
            recent.add("/\(number).lss")
        }
        #expect(recent.paths.count == RecentFiles.limit)
        #expect(recent.paths.first == "/12.lss")
        #expect(recent.paths.last == "/3.lss")
    }

    @Test func aPathCanBeRemovedAndTheListCleared() {
        var recent = RecentFiles(["/a.lss", "/b.lss"])
        recent.remove("/a.lss")
        #expect(recent.paths == ["/b.lss"])
        recent.clear()
        #expect(recent.paths.isEmpty)
    }

    @Test func aListFromTheFileIsTrimmedAndDeduplicated() {
        let paths = ["/a.lss", "", "/b.lss", "/a.lss"] + (1...12).map { "/\($0).lss" }
        let recent = RecentFiles(paths)
        #expect(recent.paths.prefix(3) == ["/a.lss", "/b.lss", "/1.lss"])
        #expect(recent.paths.count == 10)
        #expect(!recent.paths.contains(""))
    }

    @Test func itIsAPlainListInTheFile() throws {
        let settings = try Settings.decode(Data("recent_splits = [\"/a\", \"/b\"]\n".utf8))
        #expect(settings.recentSplits.paths == ["/a", "/b"])
        var changed = Settings()
        changed.recentSplits = RecentFiles(["/a", "/b"])
        #expect(try changed.tomlText().contains(#"recent_splits = ["/a", "/b"]"#))
    }
}
