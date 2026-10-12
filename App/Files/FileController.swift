import Foundation
import LiveSplitCore

/// Opening, saving and closing splits and layouts (spec §7): what the File menu, the
/// right-click menu and launch do with files. It asks for files through `FilePicker` and tells
/// the user through `FileAlerts`, so the tests need no panels.
@MainActor
final class FileController {
    private let content: TimerContent
    private let window: TimerWindowController
    private let settings: SettingsStore
    private let picker: FilePicker
    private let alerts: FileAlerts
    private let lang: UInt8
    private let log: Log

    /// The open splits' path, or `nil` for a run with no file.
    private(set) var splitsPath: String?

    init(
        content: TimerContent, window: TimerWindowController, settings: SettingsStore,
        picker: FilePicker, alerts: FileAlerts, lang: UInt8 = TimerContent.systemLanguage,
        log: Log = .shared
    ) {
        self.content = content
        self.window = window
        self.settings = settings
        self.picker = picker
        self.alerts = alerts
        self.lang = lang
        self.log = log
    }

    /// Whether opening or closing splits is allowed: no attempt is in progress, so none is
    /// dropped (spec §7.1).
    var canReplaceRun: Bool { content.phase == .notRunning }

    var recentSplits: [String] { settings.settings.recentSplits.paths }
    var recentLayouts: [String] { settings.settings.recentLayouts.paths }

    /// The path as `app.toml` and the log hold it.
    private func standard(_ url: URL) -> String { url.standardizedFileURL.path }

    // MARK: Launch

    /// Reopens the splits and layout of the last session. A file that can't be opened leaves
    /// `app.toml` alone, so a file on a drive that comes back reopens next time.
    func reopenAtLaunch() {
        if let path = settings.settings.lastSplitsPath {
            let url = URL(filePath: path)
            do {
                let run = try SplitsFile.load(url)
                if content.setRun(run) {
                    splitsPath = url.standardizedFileURL.path
                    log.record(.app, "Opened splits \(LogText.escaped(standard(url)))")
                } else {
                    failedToReopen(url, error: .notSplits)
                }
            } catch {
                failedToReopen(url, error: error)
            }
        }
        if let path = settings.settings.lastLayoutPath {
            let url = URL(filePath: path)
            do {
                let layout = try LayoutFile.load(url)
                window.showLayout(layout, path: url.standardizedFileURL.path)
                log.record(.app, "Opened layout \(LogText.escaped(standard(url)))")
            } catch {
                failedToReopen(url, error: error)
            }
        }
    }

    private func failedToReopen(_ url: URL, error: FileLoadError) {
        let name = url.lastPathComponent
        window.notices.show("Couldn't reopen \"\(name)\": \(error.reason(file: name))")
        log.record(
            .error,
            "Couldn't open \(LogText.escaped(standard(url))): \(error.reason(file: name))")
    }

    // MARK: Splits

    /// Open Splits…
    func openSplits() {
        guard canReplaceRun, confirmUnsavedChanges() else { return }
        guard let url = picker.fileToOpen(.splits) else { return }
        open(splitsAt: url)
    }

    /// A recent file of Open Recent.
    func openSplits(atPath path: String) {
        guard canReplaceRun, confirmUnsavedChanges() else { return }
        open(splitsAt: URL(filePath: path))
    }

    private func open(splitsAt url: URL) {
        let run: Run
        do {
            run = try SplitsFile.load(url)
        } catch {
            failedToOpen(url, error: error)
            return
        }
        guard content.setRun(run) else {
            failedToOpen(url, error: .notSplits)
            return
        }
        let path = url.standardizedFileURL.path
        splitsPath = path
        settings.update {
            $0.lastSplitsPath = path
            $0.recentSplits.add(path)
        }
        log.record(.app, "Opened splits \(LogText.escaped(path))")
        openLinkedLayout()
    }

    /// The layout the splits just opened link to (spec §7.1). The app never writes the link.
    private func openLinkedLayout() {
        switch content.linkedLayout {
        case .none:
            break
        case .defaultLayout:
            window.showLayout(Layout.defaultLayout(lang), path: nil)
            settings.update { $0.lastLayoutPath = nil }
        case .path(let linked):
            // A relative link resolves against the working directory, so it fails with a notice.
            let url = URL(filePath: linked)
            let name = url.lastPathComponent
            do {
                try show(layoutAt: url)
            } catch {
                window.notices.show(
                    "Couldn't open the layout \"\(name)\" these splits use: "
                        + error.reason(file: name))
                log.record(
                    .error,
                    "Couldn't open \(LogText.escaped(standard(url))): \(error.reason(file: name))")
            }
        }
    }

    @discardableResult
    func saveSplits() -> Bool {
        if SplitsFile.needsNewName(splitsPath) { return saveSplitsAs() }
        guard let splitsPath else { return false }
        return write(splitsTo: URL(filePath: splitsPath))
    }

    @discardableResult
    func saveSplitsAs() -> Bool {
        let name = content.withRun { SplitsFile.suggestedName(path: splitsPath, run: $0) }
        let directory = splitsPath.map { URL(filePath: $0).deletingLastPathComponent() }
        guard let url = picker.fileToSave(.splits, name: name, directory: directory) else {
            return false
        }
        guard write(splitsTo: url) else { return false }
        let path = url.standardizedFileURL.path
        splitsPath = path
        settings.update {
            $0.lastSplitsPath = path
            $0.recentSplits.add(path)
        }
        return true
    }

    /// Writes the run, and marks it saved only if it didn't change meanwhile (spec §7.1).
    private func write(splitsTo url: URL) -> Bool {
        let text = content.lssText()
        do {
            try TextFile.write(text, to: url)
        } catch {
            failedToSave(url, reason: error.localizedDescription)
            return false
        }
        content.markSaved(text)
        log.record(.app, "Saved splits to \(LogText.escaped(standard(url)))")
        return true
    }

    /// Close Splits: back to the new run, keeping the layout.
    func closeSplits() {
        guard canReplaceRun, confirmUnsavedChanges() else { return }
        guard content.setRun(TimerContent.defaultRun()) else { return }
        splitsPath = nil
        settings.update { $0.lastSplitsPath = nil }
        log.record(.app, "Closed splits")
    }

    /// Asks about unsaved changes if there are any. `true` if it's fine to go on.
    func confirmUnsavedChanges() -> Bool {
        guard content.hasUnsavedChanges else { return true }
        let name = splitsPath.map { URL(filePath: $0).lastPathComponent }
        switch alerts.askToSave(name: name) {
        case .save: return saveSplits()
        case .dontSave: return true
        case .cancel: return false
        }
    }

    // MARK: Layouts

    func openLayout() {
        guard let url = picker.fileToOpen(.layout) else { return }
        open(layoutAt: url)
    }

    func openLayout(atPath path: String) {
        open(layoutAt: URL(filePath: path))
    }

    private func open(layoutAt url: URL) {
        do {
            try show(layoutAt: url)
        } catch {
            failedToOpen(url, error: error)
        }
    }

    /// Loads the layout, shows it, and records it. Nothing changes if it doesn't load.
    private func show(layoutAt url: URL) throws(FileLoadError) {
        let layout = try LayoutFile.load(url)
        let path = url.standardizedFileURL.path
        window.showLayout(layout, path: path)
        settings.update {
            $0.lastLayoutPath = path
            $0.recentLayouts.add(path)
        }
        log.record(.app, "Opened layout \(LogText.escaped(path))")
    }

    func saveLayoutAs() {
        let name = LayoutFile.suggestedName(path: window.layoutPath)
        let directory = window.layoutPath.map { URL(filePath: $0).deletingLastPathComponent() }
        guard let url = picker.fileToSave(.layout, name: name, directory: directory) else {
            return
        }
        do {
            try TextFile.write(content.layout.settingsAsJson(), to: url)
        } catch {
            failedToSave(url, reason: error.localizedDescription)
            return
        }
        let path = url.standardizedFileURL.path
        window.adoptLayoutPath(path)
        settings.update {
            $0.lastLayoutPath = path
            $0.recentLayouts.add(path)
        }
        log.record(.app, "Saved layout to \(LogText.escaped(path))")
    }

    // MARK: Recent files

    func clearRecentSplits() {
        settings.update { $0.recentSplits.clear() }
    }

    func clearRecentLayouts() {
        settings.update { $0.recentLayouts.clear() }
    }

    // MARK: Failures

    private func failedToOpen(_ url: URL, error: FileLoadError) {
        let name = url.lastPathComponent
        alerts.showLoadFailed(error, file: name)
        log.record(
            .error,
            "Couldn't open \(LogText.escaped(standard(url))): \(error.reason(file: name))")
    }

    private func failedToSave(_ url: URL, reason: String) {
        alerts.showSaveFailed(reason: reason, file: url.lastPathComponent)
        log.record(.error, "Couldn't save \(LogText.escaped(standard(url))): \(reason)")
    }
}
