import Foundation

/// Where the log files are (spec §12.2).
enum LogFolder {
    static let name = "livesplit-one-macos"

    /// `~/Library/Logs/livesplit-one-macos`, where Console.app lists apps' log files.
    static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Logs/\(name)", directoryHint: .isDirectory)
    }

    /// The folder this run logs to: the standard one, unless a test chose another.
    static var current: URL { LaunchOverrides.logDirectory ?? standard() }
}
