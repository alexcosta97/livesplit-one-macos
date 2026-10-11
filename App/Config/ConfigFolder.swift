import Foundation

/// Where `app.toml` is (spec §11): the folder livesplit-asr-bridge uses for its own settings,
/// `dirs::config_dir()`, which on macOS is Application Support.
enum ConfigFolder {
    static let name = "livesplit-one-macos"

    /// `~/Library/Application Support/livesplit-one-macos`.
    static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Application Support/\(name)", directoryHint: .isDirectory)
    }

    /// The folder this run uses: the standard one, unless a test chose another.
    static var current: URL { LaunchOverrides.configDirectory ?? standard() }
}
