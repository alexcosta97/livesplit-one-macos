import Foundation

/// Reads `app.toml` at launch and writes it when a setting changes (spec §11, §10).
@MainActor
final class SettingsStore {
    static let fileName = "app.toml"
    static let badFileName = "app.toml.bad"
    /// The first line of the file, so someone opening it knows what it is.
    static let header =
        "# LiveSplit One for macOS settings. The app rewrites this file when a setting changes.\n\n"

    /// What reading the file at launch found.
    enum LoadOutcome: Equatable {
        /// No file yet: the defaults.
        case missing
        case loaded
        /// The file couldn't be read or parsed. It was kept as `app.toml.bad`, and the defaults
        /// are used.
        case recovered(reason: String)
        /// The file couldn't be read or parsed, nor moved aside. The defaults are used, and
        /// nothing is saved this session, so the file isn't overwritten.
        case unrecoverable(reason: String)
    }

    let directory: URL
    var file: URL { directory.appending(path: Self.fileName) }
    private(set) var settings: Settings
    let loadOutcome: LoadOutcome

    private let log: Log

    init(directory: URL, log: Log = .shared) {
        self.directory = directory
        self.log = log
        (settings, loadOutcome) = Self.load(from: directory, log: log)
    }

    /// Changes the settings and saves them, if `change` changed anything.
    func update(_ change: (inout Settings) -> Void) {
        var changed = settings
        change(&changed)
        guard changed != settings else { return }
        settings = changed
        save()
    }

    private func save() {
        // Never write over a file that couldn't be read or moved aside.
        if case .unrecoverable = loadOutcome { return }
        do {
            let text = Self.header + (try settings.tomlText())
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            // Atomic: a crash or a full disk mid-write leaves the old file whole. Written to the
            // link's target, since an atomic write would replace a symlink with a regular file.
            try Data(text.utf8).write(to: file.resolvingSymlinksInPath(), options: .atomic)
            log.record(.app, "Saved the settings to \(file.path)")
        } catch {
            log.record(
                .error, "Couldn't save the settings to \(file.path): \(Settings.reason(for: error))"
            )
        }
    }

    /// Reads the settings in `directory`, moving a broken file aside.
    private static func load(from directory: URL, log: Log) -> (Settings, LoadOutcome) {
        let file = directory.appending(path: fileName)
        let bad = directory.appending(path: badFileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            log.record(.app, "No settings file yet at \(file.path), so the defaults are used")
            return (Settings(), .missing)
        }

        let reason: String
        do {
            let settings = try Settings.decode(Data(contentsOf: file))
            log.record(.app, "Read the settings from \(file.path)")
            for problem in settings.shortcuts.dropped {
                log.record(.error, "Ignored a shortcut in \(file.path): \(problem)")
            }
            return (settings, .loaded)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // The file went away between the check and the read.
            log.record(.app, "No settings file yet at \(file.path), so the defaults are used")
            return (Settings(), .missing)
        } catch {
            reason = Settings.reason(for: error)
        }

        do {
            // One rename replaces an older copy atomically, so a failed move never loses it.
            guard rename(file.path, bad.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            // So the owner can open the copy kept for them, even if the file was mode 000. Only
            // for a regular file: setAttributes follows a symlink and would change its target.
            if let attributes = try? FileManager.default.attributesOfItem(atPath: bad.path),
                attributes[.type] as? FileAttributeType == .typeRegular,
                let mode = attributes[.posixPermissions] as? Int
            {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: mode | 0o600], ofItemAtPath: bad.path)
            }
            log.record(
                .error,
                "Couldn't read the settings in \(file.path), so the defaults are used and the "
                    + "file is kept as \(badFileName): \(reason)")
            return (Settings(), .recovered(reason: reason))
        } catch {
            log.record(
                .error,
                "Couldn't read the settings in \(file.path) (\(reason)), nor keep it as "
                    + "\(badFileName) (\(Settings.reason(for: error))), so the defaults are "
                    + "used and changes aren't saved until the app restarts")
            return (Settings(), .unrecoverable(reason: reason))
        }
    }
}
