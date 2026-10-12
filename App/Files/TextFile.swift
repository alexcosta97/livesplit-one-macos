import Foundation

enum TextFile {
    /// Writes `text` atomically, so a crash or a full disk leaves the old file whole. Written
    /// to a link's target, since an atomic write would replace a symlink with a regular file.
    static func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }
}
