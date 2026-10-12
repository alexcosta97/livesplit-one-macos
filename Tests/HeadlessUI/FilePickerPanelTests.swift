import AppKit
import Testing
import UniformTypeIdentifiers

@testable import LiveSplitOne

@MainActor
@Suite struct FilePickerPanelTests {
    @Test func openSplitsAcceptsAnyFile() {
        let panel = SystemFilePicker.openPanel(.splits)
        #expect(panel.allowedContentTypes.isEmpty)
        #expect(panel.canChooseFiles)
        #expect(!panel.canChooseDirectories)
        #expect(!panel.allowsMultipleSelection)
    }

    @Test func openLayoutAcceptsLslAndLs1l() {
        let panel = SystemFilePicker.openPanel(.layout)
        let extensions = panel.allowedContentTypes.compactMap(\.preferredFilenameExtension)
        #expect(extensions.sorted() == ["ls1l", "lsl"])
        #expect(panel.allowedContentTypes.allSatisfy { $0.conforms(to: .data) })
        #expect(!panel.canChooseDirectories)
        #expect(!panel.allowsMultipleSelection)
    }

    @Test func saveSplitsSuggestsTheNameAndFolder() {
        let folder = URL(filePath: "/private/tmp/runs", directoryHint: .isDirectory)
        let panel = SystemFilePicker.savePanel(.splits, name: "Run.lss", directory: folder)
        #expect(panel.allowedContentTypes.compactMap(\.preferredFilenameExtension) == ["lss"])
        #expect(panel.nameFieldStringValue == "Run.lss")
        #expect(panel.directoryURL?.path == "/private/tmp/runs")
        #expect(panel.canCreateDirectories)
        #expect(!panel.isExtensionHidden)
    }

    @Test func saveLayoutWritesLs1l() {
        let panel = SystemFilePicker.savePanel(.layout, name: "Layout.ls1l", directory: nil)
        #expect(panel.allowedContentTypes.compactMap(\.preferredFilenameExtension) == ["ls1l"])
        #expect(panel.nameFieldStringValue == "Layout.ls1l")
        #expect(panel.canCreateDirectories)
        #expect(!panel.isExtensionHidden)
    }
}
