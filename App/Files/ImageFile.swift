import AppKit
import Foundation

/// Icon images read from files (spec §9).
enum ImageFile {
    /// The most an image file may hold. Icons are shrunk by livesplit-core; the cap keeps a
    /// link to an enormous file from filling memory on the main thread.
    static let sizeLimit = 16 * 1024 * 1024

    /// The bytes of an image file the editor can use as an icon (spec §9): a regular file
    /// under `sizeLimit` that macOS can decode as an image.
    static func load(_ url: URL) throws(FileLoadError) -> Data {
        let data = try FileLoadError.read(
            url, limit: sizeLimit, tooLarge: "It's too large to be an icon.")
        guard NSImage(data: data) != nil else { throw .notImage }
        return data
    }
}
