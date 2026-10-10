import AppKit

/// Open Log Folder (spec §12.2): opens the log folder in Finder.
@MainActor
struct LogFolderOpener {
    var createDirectory: (URL) throws -> Void
    var openInFinder: (URL) -> Bool
    var log: Log

    static var system: LogFolderOpener {
        LogFolderOpener(
            createDirectory: {
                try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
            },
            openInFinder: { NSWorkspace.shared.open($0) },
            log: .shared)
    }

    /// Opens `folder`, creating it first in case no line could be written yet. Returns false,
    /// after logging why, if it couldn't.
    func open(_ folder: URL) -> Bool {
        do {
            try createDirectory(folder)
        } catch {
            log.record(
                .error,
                "Couldn't create the log folder \(folder.path): \(error.localizedDescription)")
            return false
        }
        guard openInFinder(folder) else {
            log.record(.error, "Couldn't open the log folder \(folder.path) in Finder")
            return false
        }
        return true
    }
}

/// Shown when Open Log Folder couldn't open the folder (spec §10), so the user can still find it.
enum LogFolderAlert {
    @MainActor
    static func make(folder: URL) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't open the log folder"
        alert.informativeText = "The log files belong in \(folder.path)."
        alert.addButton(withTitle: "OK")
        return alert
    }
}
