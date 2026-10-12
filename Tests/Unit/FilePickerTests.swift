import Foundation
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct FilePickerTests {
    private func makePicker(
        _ answers: [String?]
    ) throws -> (ScriptedFilePicker, RecordingUnifiedLog, TemporaryFolder) {
        let folder = try TemporaryFolder()
        let unified = RecordingUnifiedLog()
        let log = Log(directory: folder.url, unified: unified)
        return (ScriptedFilePicker(answers: answers, log: log), unified, folder)
    }

    @Test func itAnswersInOrderWhateverIsAsked() throws {
        let (picker, _, _) = try makePicker(["/a.lss", "/b.ls1l", "/c.ls1l"])
        #expect(picker.fileToOpen(.splits)?.path == "/a.lss")
        #expect(picker.fileToSave(.layout, name: "Layout.ls1l", directory: nil)?.path == "/b.ls1l")
        #expect(picker.fileToOpen(.layout)?.path == "/c.ls1l")
    }

    @Test func aNullCancels() throws {
        let (picker, _, _) = try makePicker([nil, "/a.lss"])
        #expect(picker.fileToOpen(.splits) == nil)
        #expect(picker.fileToOpen(.splits)?.path == "/a.lss")
    }

    @Test func aRelativePathCancelsAndLogsIt() throws {
        let (picker, unified, _) = try makePicker(["relative/a.lss", "/b.lss"])
        #expect(picker.fileToOpen(.splits) == nil)
        #expect(unified.entries.map(\.category) == [.error])
        #expect(unified.entries.first?.message.contains("relative/a.lss") == true)
        #expect(picker.fileToOpen(.splits)?.path == "/b.lss")
    }

    @Test func itRemembersWhatItWasAsked() throws {
        let (picker, _, _) = try makePicker([nil, nil, nil])
        _ = picker.fileToOpen(.splits)
        _ = picker.fileToOpen(.layout)
        _ = picker.fileToSave(.layout, name: "Layout.ls1l", directory: nil)
        #expect(picker.asked == ["open splits", "open layout", "save layout Layout.ls1l"])
    }

    @Test func runningOutCancelsAndLogsIt() throws {
        let (picker, unified, _) = try makePicker([])
        #expect(picker.fileToOpen(.layout) == nil)
        #expect(picker.asked == ["open layout"])
        #expect(unified.entries.map(\.category) == [.error])
        #expect(unified.entries.first?.message.contains("open layout") == true)
    }

    @Test func aLaunchArgumentListsTheAnswers() throws {
        let arguments = ["/Applications/LiveSplit One.app", "-LSOPickedFiles", #"["/a", null]"#]
        let log = Log(directory: try TemporaryFolder().url, unified: RecordingUnifiedLog())
        let answers = try #require(LaunchOverrides.pickedFiles(in: arguments, log: log))
        #expect(answers == ["/a", nil])
    }

    @Test func aMissingOrInvalidListIsIgnored() throws {
        let unified = RecordingUnifiedLog()
        let log = Log(directory: try TemporaryFolder().url, unified: unified)
        #expect(LaunchOverrides.pickedFiles(in: ["app"], log: log) == nil)
        #expect(LaunchOverrides.pickedFiles(in: ["app", "-LSOPickedFiles"], log: log) == nil)
        #expect(unified.entries.isEmpty)
        #expect(
            LaunchOverrides.pickedFiles(in: ["app", "-LSOPickedFiles", "not json"], log: log)
                == nil)
        #expect(unified.entries.map(\.category) == [.error])
    }
}
