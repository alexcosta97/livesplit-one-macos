import Foundation

/// Why a splits, layout or image file didn't open (spec §7.1, §10). livesplit-core's parsers
/// don't say why a file didn't parse, so only macOS's reasons for not reading it are passed on.
enum FileLoadError: Error, Equatable, Sendable {
    /// macOS couldn't read the file: its reason, such as a missing file or no permission.
    case unreadable(String)
    case notSplits
    case notLayout
    case notImage

    /// The alert's text for the file named `file`.
    func message(file: String) -> String {
        switch self {
        case .unreadable(let reason): reason
        case .notSplits: "\"\(file)\" isn't splits LiveSplit One for macOS can read."
        case .notLayout: "\"\(file)\" isn't a layout LiveSplit One for macOS can read."
        case .notImage: "It isn't an image LiveSplit One for macOS can read."
        }
    }

    /// The reason, for an overlay notice or the log, which name the file themselves.
    func reason(file: String) -> String {
        switch self {
        case .unreadable(let reason): reason
        case .notSplits: "it isn't splits this app can read"
        case .notLayout: "it isn't a layout this app can read"
        case .notImage: "it isn't an image this app can read"
        }
    }

    /// The most a splits or layout file may hold. Real files are kilobytes; the cap keeps a
    /// link to an enormous file from filling memory on the main thread.
    static let sizeLimit = 64 * 1024 * 1024

    /// Reads `url`, turning macOS's error into `.unreadable`. Only a regular file under
    /// `sizeLimit` is read, symlinks resolved: a link to a device or a pipe would never end,
    /// and splits name their layout, so the path can't be trusted.
    ///
    /// `limit` and `tooLarge` (the text for a file over it) default to the splits and layout
    /// ones; other kinds of file, such as icons, give their own.
    static func read(
        _ url: URL, limit: Int = sizeLimit, tooLarge: String = splitsTooLarge
    ) throws(FileLoadError) -> Data {
        do {
            return try readBounded(url, limit: limit, tooLarge: tooLarge)
        } catch let error as FileLoadError {
            throw error
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }

    private static let splitsTooLarge = "It's too large to be a splits or layout file."
    private static let notRegular = "It isn't a regular file."

    /// macOS's words for a file that couldn't be opened, such as "The file “x” couldn't be
    /// opened because there is no such file.", built from `errno` as Foundation words its own
    /// read errors, without a second open of the path (which could block on a pipe).
    private static func reason(forOpenError code: Int32, path: String) -> String {
        let cocoa: CocoaError.Code =
            switch code {
            case ENOENT, ENOTDIR: .fileReadNoSuchFile
            case EACCES, EPERM: .fileReadNoPermission
            default: .fileReadUnknown
            }
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        return NSError(
            domain: NSCocoaErrorDomain, code: cocoa.rawValue,
            userInfo: [NSFilePathErrorKey: path, NSUnderlyingErrorKey: underlying]
        ).localizedDescription
    }

    /// The contents of the regular file `url` (symlinks resolved), read no further than `limit`
    /// bytes: a file that grows after the size check can't take more memory than that.
    ///
    /// The file is opened without blocking and then checked through the descriptor, so a file
    /// swapped for a pipe between a check and the open can't hold the app up: a pipe is refused
    /// by its type before anything is read.
    static func readBounded(
        _ url: URL, limit: Int, tooLarge: String = splitsTooLarge
    ) throws -> Data {
        let resolved = url.resolvingSymlinksInPath()
        let descriptor = open(resolved.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw FileLoadError.unreadable(reason(forOpenError: errno, path: resolved.path))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw FileLoadError.unreadable(
                NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw FileLoadError.unreadable(notRegular)
        }
        guard Int64(info.st_size) <= Int64(limit) else { throw FileLoadError.unreadable(tooLarge) }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw FileLoadError.unreadable(tooLarge) }
        return data
    }
}
