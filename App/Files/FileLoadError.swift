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

    /// Reads `url`, turning macOS's error into `.unreadable`.
    static func read(_ url: URL) throws(FileLoadError) -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }
}
