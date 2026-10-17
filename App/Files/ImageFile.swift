import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Icon images read from files (spec §9).
enum ImageFile {
    /// The most an image file may hold. Icons are shrunk by livesplit-core; the cap keeps a
    /// link to an enormous file from filling memory on the main thread.
    static let sizeLimit = 16 * 1024 * 1024

    /// The formats livesplit-core draws (spec §9), which the open panel allows too.
    static let formats: [UTType] = [.png, .jpeg, .gif, .bmp, .tiff, .webP, .ico]

    /// The bytes of an image file the editor can use as an icon (spec §9): a regular file
    /// under `sizeLimit` whose data is one of `formats`, whatever its extension.
    static func load(_ url: URL) throws(FileLoadError) -> Data {
        let data = try FileLoadError.read(
            url, limit: sizeLimit, tooLarge: "It's too large to be an icon.")
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) }),
            formats.contains(type), CGImageSourceGetCount(source) > 0
        else { throw .notImage }
        return data
    }
}
