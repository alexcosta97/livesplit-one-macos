import AppKit
import UniformTypeIdentifiers

/// What kind of file the app asks for.
enum FileKind: Sendable {
    case splits
    case layout

    /// How the kind reads in the log, as in "open splits".
    fileprivate var logName: String {
        switch self {
        case .splits: "splits"
        case .layout: "layout"
        }
    }
}

/// The one way the app asks for a file (spec §7.1, §14.2).
@MainActor
protocol FilePicker: AnyObject {
    /// A file to open, or `nil` if the user cancelled.
    func fileToOpen(_ kind: FileKind) -> URL?
    /// Where to save, or `nil` if the user cancelled. `name` is the suggested file name and
    /// `directory` the folder to start in.
    func fileToSave(_ kind: FileKind, name: String, directory: URL?) -> URL?
}

/// `NSOpenPanel` and `NSSavePanel`, shown as app-modal panels.
final class SystemFilePicker: FilePicker {
    /// The picker the app uses: the scripted answers a test chose at launch (Debug builds
    /// only, spec §14.2), or the system's panels.
    @MainActor
    static func make(scriptedAnswers: [String?]? = LaunchOverrides.pickedFiles) -> FilePicker {
        if let scriptedAnswers { return ScriptedFilePicker(answers: scriptedAnswers) }
        return SystemFilePicker()
    }

    func fileToOpen(_ kind: FileKind) -> URL? {
        let panel = Self.openPanel(kind)
        return panel.runModal() == .OK ? panel.url : nil
    }

    func fileToSave(_ kind: FileKind, name: String, directory: URL?) -> URL? {
        let panel = Self.savePanel(kind, name: name, directory: directory)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The panel for opening a file of `kind`. Splits can be any file, because livesplit-core
    /// reads many formats whatever their extension; layouts are `.lsl` or `.ls1l`.
    static func openPanel(_ kind: FileKind) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        switch kind {
        case .splits:
            break
        case .layout:
            panel.allowedContentTypes = ["lsl", "ls1l"].compactMap {
                UTType(filenameExtension: $0, conformingTo: .data)
            }
        }
        return panel
    }

    /// The panel for saving a file of `kind` as `name`, starting in `directory`.
    static func savePanel(_ kind: FileKind, name: String, directory: URL?) -> NSSavePanel {
        let panel = NSSavePanel()
        let fileExtension =
            switch kind {
            case .splits: "lss"
            case .layout: "ls1l"
            }
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension, conformingTo: .data)]
            .compactMap { $0 }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = name
        // With no folder, the panel starts where AppKit last had it.
        if let directory { panel.directoryURL = directory }
        return panel
    }
}

/// Answers from a list, in order, as a user would (spec §14.2). Each answer is a path, or
/// `nil` for a cancel. With no answers left it cancels and logs it.
final class ScriptedFilePicker: FilePicker {
    /// What was asked, in order, as in "open splits" or "save layout Layout.ls1l".
    private(set) var asked: [String] = []
    private var answers: [String?]
    private let log: Log

    init(answers: [String?], log: Log = .shared) {
        self.answers = answers
        self.log = log
    }

    func fileToOpen(_ kind: FileKind) -> URL? {
        answer("open \(kind.logName)")
    }

    func fileToSave(_ kind: FileKind, name: String, directory: URL?) -> URL? {
        answer("save \(kind.logName) \(name)")
    }

    private func answer(_ question: String) -> URL? {
        asked.append(question)
        guard !answers.isEmpty else {
            log.record(
                .error,
                "No scripted file answer left for \"\(LogText.escaped(question))\"; cancelling")
            return nil
        }
        guard let path = answers.removeFirst() else { return nil }
        // Answers are absolute paths (spec §14.2); a relative one would depend on the cwd.
        guard path.hasPrefix("/") else {
            log.record(
                .error,
                "Scripted file answer \"\(LogText.escaped(path))\" isn't absolute; cancelling")
            return nil
        }
        return URL(filePath: path)
    }
}
