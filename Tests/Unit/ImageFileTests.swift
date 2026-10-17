import AppKit
import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct ImageFileTests {
    private let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    private func png() throws -> Data {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test func aPngLoads() throws {
        let data = try png()
        let url = folder.url.appending(path: "Icon.png")
        try data.write(to: url)
        #expect(try ImageFile.load(url) == data)
    }

    @Test func aJpegLoads() throws {
        let bitmap = try #require(NSBitmapImageRep(data: try png()))
        let data = try #require(bitmap.representation(using: .jpeg, properties: [:]))
        let url = folder.url.appending(path: "Icon.jpg")
        try data.write(to: url)
        #expect(try ImageFile.load(url) == data)
    }

    @Test @MainActor func aPdfIsNotAnImage() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let url = folder.url.appending(path: "Icon.png")
        try view.dataWithPDF(inside: view.bounds).write(to: url)
        #expect(throws: FileLoadError.notImage) { try ImageFile.load(url) }
    }

    @Test func aTextFileIsNotAnImage() throws {
        try folder.write("Notes.png", "not an image")
        #expect(throws: FileLoadError.notImage) {
            try ImageFile.load(folder.url.appending(path: "Notes.png"))
        }
    }

    @Test func anEmptyFileIsNotAnImage() throws {
        try folder.write("Empty.png")
        #expect(throws: FileLoadError.notImage) {
            try ImageFile.load(folder.url.appending(path: "Empty.png"))
        }
    }

    @Test func aFileOverTheLimitIsTooLarge() throws {
        let url = folder.url.appending(path: "Huge.png")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ImageFile.sizeLimit) + 1)
        try handle.close()
        #expect(throws: FileLoadError.unreadable("It's too large to be an icon.")) {
            try ImageFile.load(url)
        }
    }

    @Test func aDeviceIsNotRegular() {
        #expect(throws: FileLoadError.unreadable("It isn't a regular file.")) {
            try ImageFile.load(URL(filePath: "/dev/zero"))
        }
    }

    @Test func notImageHasItsTexts() {
        #expect(
            FileLoadError.notImage.message(file: "a.txt")
                == "It isn't an image LiveSplit One for macOS can read.")
        #expect(
            FileLoadError.notImage.reason(file: "a.txt") == "it isn't an image this app can read")
    }
}
