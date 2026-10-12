import Foundation
import LiveSplitCore
import Testing

@testable import LiveSplitOne

@Suite struct LayoutFileTests {
    @Test(arguments: ["Dark.lsl", "TextShadow.ls1l"])
    func bothLayoutFormatsOpen(_ name: String) throws {
        let layout = try LayoutFile.load(Fixtures.url(name))
        #expect(!layout.settingsAsJson().isEmpty)
    }

    @Test func aRenamedLayoutStillOpens() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "Dark.ls1l")
        try FileManager.default.copyItem(at: Fixtures.url("Dark.lsl"), to: url)
        _ = try LayoutFile.load(url)
    }

    @Test(arguments: ["NotSplits.txt", "GameTime.lss"])
    func aFileThatIsntALayoutIsRefused(_ name: String) {
        #expect(throws: FileLoadError.notLayout) { try LayoutFile.load(Fixtures.url(name)) }
    }

    @Test func aFolderIsUnreadableNotNotLayout() throws {
        let folder = try TemporaryFolder()
        do {
            _ = try LayoutFile.load(folder.url)
            Issue.record("it loaded")
        } catch {
            guard case .unreadable = error else {
                Issue.record("\(error)")
                return
            }
        }
    }

    @Test func aSavedLayoutOpensAgain() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "Saved.ls1l")
        let layout = try LayoutFile.load(Fixtures.url("Dark.lsl"))
        try TextFile.write(layout.settingsAsJson(), to: url)
        #expect(try LayoutFile.load(url).settingsAsJson() == layout.settingsAsJson())
    }

    @Test(
        arguments: [
            (nil, "Layout.ls1l"), ("/a/Main.lsl", "Main.ls1l"), ("/a/Main.ls1l", "Main.ls1l"),
        ] as [(String?, String)])
    func saveLayoutAsSuggestsAnLs1lName(path: String?, name: String) {
        #expect(LayoutFile.suggestedName(path: path) == name)
    }
}
