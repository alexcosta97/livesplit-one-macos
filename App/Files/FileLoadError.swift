import Foundation

/// Why a splits or layout file didn't open (spec §7.1, §10). livesplit-core's parsers don't
/// say why a file didn't parse, so only macOS's reasons for not reading it are passed on.
enum FileLoadError: Error, Equatable, Sendable {
    /// macOS couldn't read the file: its reason, such as a missing file or no permission.
    case unreadable(String)
    case notSplits
    case notLayout

    /// The alert's text for the file named `file`.
    func message(file: String) -> String {
        switch self {
        case .unreadable(let reason): reason
        case .notSplits: "\"\(file)\" isn't splits LiveSplit One for macOS can read."
        case .notLayout: "\"\(file)\" isn't a layout LiveSplit One for macOS can read."
        }
    }

    /// The reason, for an overlay notice or the log, which name the file themselves.
    func reason(file: String) -> String {
        switch self {
        case .unreadable(let reason): reason
        case .notSplits: "it isn't splits this app can read"
        case .notLayout: "it isn't a layout this app can read"
        }
    }

    /// The most a splits or layout file may hold. Real files are kilobytes; the cap keeps a
    /// link to an enormous file from filling memory on the main thread.
    static let sizeLimit = 64 * 1024 * 1024

    /// Reads `url`, turning macOS's error into `.unreadable`. Only a regular file under
    /// `sizeLimit` is read, symlinks resolved: a link to a device or a pipe would never end,
    /// and splits name their layout, so the path can't be trusted.
    static func read(_ url: URL) throws(FileLoadError) -> Data {
        do {
            let resolved = url.resolvingSymlinksInPath()
            let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw FileLoadError.unreadable("It isn't a regular file.")
            }
            if let size = values.fileSize, size > sizeLimit {
                throw FileLoadError.unreadable(tooLarge)
            }
            return try readBounded(resolved, limit: sizeLimit)
        } catch let error as FileLoadError {
            throw error
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }

    private static let tooLarge = "It's too large to be a splits or layout file."

    /// The contents of `url`, read no further than `limit` bytes: a file that grows after the
    /// size check can't take more memory than that.
    static func readBounded(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw FileLoadError.unreadable(tooLarge) }
        return data
    }
}
