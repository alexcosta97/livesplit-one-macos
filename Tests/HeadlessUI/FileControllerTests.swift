import Foundation
import LiveSplitCore
import Testing

@testable import LiveSplitOne

/// Answers from a list and records what it was asked.
@MainActor
final class FakeFilePicker: FilePicker {
    struct SaveRequest: Equatable {
        var kind: String
        var name: String
        var directory: URL?
    }

    var openAnswers: [URL?]
    var saveAnswers: [URL?]
    private(set) var opens: [String] = []
    private(set) var saves: [SaveRequest] = []

    init(open: [URL?] = [], save: [URL?] = []) {
        openAnswers = open
        saveAnswers = save
    }

    private func kindName(_ kind: FileKind) -> String {
        switch kind {
        case .splits: "splits"
        case .layout: "layout"
        }
    }

    func fileToOpen(_ kind: FileKind) -> URL? {
        opens.append(kindName(kind))
        return openAnswers.isEmpty ? nil : openAnswers.removeFirst()
    }

    func fileToSave(_ kind: FileKind, name: String, directory: URL?) -> URL? {
        saves.append(SaveRequest(kind: kindName(kind), name: name, directory: directory))
        return saveAnswers.isEmpty ? nil : saveAnswers.removeFirst()
    }
}

@MainActor
final class FakeFileAlerts: FileAlerts {
    var choices: [SaveChoice]
    private(set) var asked: [String?] = []
    private(set) var loadFailures: [(error: FileLoadError, file: String)] = []
    private(set) var saveFailures: [(reason: String, file: String)] = []

    init(choices: [SaveChoice] = []) {
        self.choices = choices
    }

    func askToSave(name: String?) -> SaveChoice {
        asked.append(name)
        return choices.isEmpty ? .cancel : choices.removeFirst()
    }

    func showLoadFailed(_ error: FileLoadError, file: String) {
        loadFailures.append((error, file))
    }

    func showSaveFailed(reason: String, file: String) {
        saveFailures.append((reason, file))
    }
}

@MainActor
@Suite final class FileControllerTests {
    let folder: TemporaryFolder
    let settings: SettingsStore
    let content = TimerContent(lang: 0)
    let window: TimerWindowController
    let unified = RecordingUnifiedLog()
    let log: Log

    init() throws {
        folder = try TemporaryFolder()
        settings = SettingsStore(
            directory: folder.url.appending(path: "config", directoryHint: .isDirectory))
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        window = TimerWindowController(
            content: content, settings: settings, screens: [screen], mainScreen: screen,
            notices: NoticeQueue(schedule: { _, _ in }))
        log = Log(
            directory: folder.url.appending(path: "logs", directoryHint: .isDirectory),
            unified: unified)
    }

    // Ends the window's display link, so they don't pile up across tests.
    isolated deinit {
        window.window.contentView = nil
    }

    private func makeController(
        picker: FilePicker = FakeFilePicker(), alerts: FileAlerts = FakeFileAlerts()
    ) -> FileController {
        FileController(
            content: content, window: window, settings: settings, picker: picker, alerts: alerts,
            lang: 0, log: log)
    }

    /// Copies a fixture into the folder as `name` and returns its URL.
    @discardableResult
    private func copy(_ fixture: String, as name: String) throws -> URL {
        let url = folder.url.appending(path: name)
        try FileManager.default.copyItem(at: Fixtures.url(fixture), to: url)
        return url
    }

    private func standard(_ url: URL) -> String { url.standardizedFileURL.path }

    private func logged(_ category: LogCategory) -> [String] {
        unified.entries.filter { $0.category == category }.map(\.message)
    }

    private func runLength() -> Int { content.withRun { Int($0.len()) } }

    /// A reset attempt, which makes the run modified.
    private func makeUnsaved() {
        let sink = EventSink(timer: content.timer, report: { _ in }, decideReset: { .save })
        _ = sink.handleCommand(#"{"command":"splitOrStart"}"#)
        _ = sink.handleCommand(#"{"command":"reset","saveAttempt":true}"#)
    }

    private func startTimer() {
        let sink = EventSink(timer: content.timer, report: { _ in }, decideReset: { .cancel })
        _ = sink.handleCommand(#"{"command":"start"}"#)
    }

    private func settingsFileBytes() -> Data? { try? Data(contentsOf: settings.file) }

    // MARK: 1. Open splits

    @Test func openingSplitsLoadsThemAndRecordsThePath() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let picker = FakeFilePicker(open: [url])
        let controller = makeController(picker: picker)
        controller.openSplits()
        #expect(picker.opens == ["splits"])
        #expect(runLength() > 1)
        #expect(controller.splitsPath == standard(url))
        #expect(settings.settings.lastSplitsPath == standard(url))
        #expect(controller.recentSplits == [standard(url)])
        #expect(!content.hasUnsavedChanges)
        #expect(logged(.app).contains("Opened splits \(standard(url))"))
    }

    @Test func aCancelledOpenChangesNothing() {
        let picker = FakeFilePicker(open: [nil])
        let controller = makeController(picker: picker)
        controller.openSplits()
        #expect(picker.opens == ["splits"])
        #expect(runLength() == 1)
        #expect(controller.splitsPath == nil)
        #expect(settings.settings.lastSplitsPath == nil)
    }

    @Test func splitsThatDontOpenChangeNothingAndAreReported() throws {
        let good = try copy("GameTime.lss", as: "Splits.lss")
        let bad = try copy("NotSplits.txt", as: "NotSplits.txt")
        let alerts = FakeFileAlerts()
        let controller = makeController(
            picker: FakeFilePicker(open: [good, bad]), alerts: alerts)
        controller.openSplits()
        let length = runLength()
        let before = settings.settings
        let bytes = settingsFileBytes()

        controller.openSplits()
        #expect(alerts.loadFailures.map(\.file) == ["NotSplits.txt"])
        #expect(alerts.loadFailures.map(\.error) == [.notSplits])
        #expect(runLength() == length)
        #expect(controller.splitsPath == standard(good))
        #expect(settings.settings == before)
        #expect(settingsFileBytes() == bytes)
        #expect(logged(.error).contains { $0.hasPrefix("Couldn't open \(standard(bad)): ") })
    }

    @Test func openingSplitsAsksAboutUnsavedChangesFirst() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        makeUnsaved()
        let picker = FakeFilePicker(open: [url])
        let alerts = FakeFileAlerts(choices: [.cancel])
        let controller = makeController(picker: picker, alerts: alerts)
        controller.openSplits()
        #expect(alerts.asked.count == 1)
        #expect(picker.opens.isEmpty)
        #expect(runLength() == 1)

        alerts.choices = [.dontSave]
        controller.openSplits()
        #expect(picker.opens == ["splits"])
        #expect(runLength() > 1)
    }

    @Test func splitsCantBeOpenedWhileAnAttemptRuns() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        startTimer()
        let picker = FakeFilePicker(open: [url])
        let controller = makeController(picker: picker)
        #expect(!controller.canReplaceRun)
        controller.openSplits()
        controller.openSplits(atPath: url.path)
        controller.closeSplits()
        #expect(picker.opens.isEmpty)
        #expect(runLength() == 1)
        #expect(content.phase == .running)
    }

    // MARK: 2. Linked layout

    @Test func aLinkedLayoutOpensWithTheSplits() throws {
        let layout = Fixtures.url("TextShadow.ls1l")
        let url = try LinkedSplits.write(linking: layout.path, in: folder)
        let controller = makeController(picker: FakeFilePicker(open: [url]))
        controller.openSplits()
        #expect(window.layoutPath == standard(layout))
        #expect(settings.settings.lastLayoutPath == standard(layout))
        #expect(controller.recentLayouts == [standard(layout)])
        #expect(window.notices.current == nil)
    }

    @Test func aLinkToTheDefaultLayoutShowsTheDefaultLayout() throws {
        let layout = Fixtures.url("TextShadow.ls1l")
        let controller = makeController(
            picker: FakeFilePicker(open: [try LinkedSplits.write(linking: "?default", in: folder)]))
        controller.openLayout(atPath: layout.path)
        #expect(window.layoutPath == standard(layout))
        controller.openSplits()
        #expect(window.layoutPath == nil)
        #expect(settings.settings.lastLayoutPath == nil)
        #expect(runLength() > 1)
    }

    @Test func aLinkToAMissingLayoutKeepsTheLayoutAndShowsANotice() throws {
        let layout = Fixtures.url("TextShadow.ls1l")
        let missing = folder.url.appending(path: "Gone.ls1l")
        let url = try LinkedSplits.write(linking: missing.path, in: folder)
        let alerts = FakeFileAlerts()
        let controller = makeController(picker: FakeFilePicker(open: [url]), alerts: alerts)
        controller.openLayout(atPath: layout.path)
        controller.openSplits()
        #expect(runLength() > 1)
        #expect(window.layoutPath == standard(layout))
        #expect(settings.settings.lastLayoutPath == standard(layout))
        let notice = try #require(window.notices.current)
        #expect(notice.hasPrefix("Couldn't open the layout \"Gone.ls1l\" these splits use: "))
        #expect(alerts.loadFailures.isEmpty)
        #expect(logged(.error).contains { $0.hasPrefix("Couldn't open \(missing.path): ") })
    }

    @Test func splitsWithNoLinkLeaveTheLayoutAlone() throws {
        let layout = Fixtures.url("TextShadow.ls1l")
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let controller = makeController(picker: FakeFilePicker(open: [url]))
        controller.openLayout(atPath: layout.path)
        controller.openSplits()
        #expect(window.layoutPath == standard(layout))
        #expect(settings.settings.lastLayoutPath == standard(layout))
    }

    @Test func aLinkToANonRegularFileShowsANoticeAndKeepsTheLayout() throws {
        let layout = Fixtures.url("TextShadow.ls1l")
        let url = try LinkedSplits.write(linking: "/dev/zero", in: folder)
        let alerts = FakeFileAlerts()
        let controller = makeController(picker: FakeFilePicker(open: [url]), alerts: alerts)
        controller.openLayout(atPath: layout.path)
        controller.openSplits()
        #expect(runLength() > 1)
        #expect(window.layoutPath == standard(layout))
        #expect(settings.settings.lastLayoutPath == standard(layout))
        #expect(
            window.notices.current
                == "Couldn't open the layout \"zero\" these splits use: It isn't a regular file.")
        #expect(alerts.loadFailures.isEmpty)
    }

    @Test func aLinkWithNewlinesCantForgeLogLines() throws {
        let link = "/tmp/x\n12:00:00.000  APP  Opened splits /forged"
        let url = try LinkedSplits.write(linking: link, in: folder)
        let controller = makeController(picker: FakeFilePicker(open: [url]))
        controller.openSplits()
        let errors = logged(.error)
        #expect(errors.count == 1)
        #expect(!errors[0].contains("\n"))
        #expect(errors[0].contains("\\n12:00:00.000"))
    }

    // MARK: 3. Save splits

    @Test func savingWritesTheFileAndMarksTheRunSaved() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let controller = makeController(picker: FakeFilePicker(open: [url]))
        controller.openSplits()
        makeUnsaved()
        #expect(content.hasUnsavedChanges)
        #expect(controller.saveSplits())
        #expect(!content.hasUnsavedChanges)
        #expect(try folder.read("Splits.lss") == content.lssText())
        #expect(logged(.app).contains("Saved splits to \(standard(url))"))
    }

    @Test func savingARunWithNoFileAsksForAName() throws {
        let target = folder.url.appending(path: "New.lss")
        let picker = FakeFilePicker(save: [target])
        let controller = makeController(picker: picker)
        makeUnsaved()
        #expect(controller.saveSplits())
        #expect(picker.saves.count == 1)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test func savingSplitsFromAnotherFormatAsksForAnLssName() throws {
        let url = try copy("Llanfair.lfs", as: "Old.lfs")
        let target = folder.url.appending(path: "Old.lss")
        let picker = FakeFilePicker(open: [url], save: [target])
        let controller = makeController(picker: picker)
        controller.openSplits()
        #expect(controller.saveSplits())
        #expect(picker.saves.map(\.name) == ["Old.lss"])
        #expect(try Data(contentsOf: url) == Data(contentsOf: Fixtures.url("Llanfair.lfs")))
    }

    @Test func aFailedSaveReportsAndLeavesTheRunUnsaved() throws {
        let subfolder = folder.url.appending(path: "sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let url = subfolder.appending(path: "Splits.lss")
        try FileManager.default.copyItem(at: Fixtures.url("GameTime.lss"), to: url)
        let alerts = FakeFileAlerts()
        let controller = makeController(picker: FakeFilePicker(open: [url]), alerts: alerts)
        controller.openSplits()
        makeUnsaved()
        // Only the file's folder goes, so the settings and the log stay.
        try FileManager.default.removeItem(at: subfolder)
        #expect(!controller.saveSplits())
        #expect(content.hasUnsavedChanges)
        #expect(alerts.saveFailures.map(\.file) == ["Splits.lss"])
        #expect(logged(.error).contains { $0.hasPrefix("Couldn't save \(standard(url)): ") })
    }

    // MARK: 4. Save splits as

    @Test func savingAsAdoptsTheNewPathAndSuggestsTheOldName() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let copyURL = folder.url.appending(path: "Copy.lss")
        let picker = FakeFilePicker(open: [url], save: [copyURL])
        let controller = makeController(picker: picker)
        controller.openSplits()
        #expect(controller.saveSplitsAs())
        #expect(picker.saves.count == 1)
        #expect(picker.saves[0].kind == "splits")
        #expect(picker.saves[0].name == "Splits.lss")
        #expect(picker.saves[0].directory.map(standard) == standard(folder.url))
        #expect(controller.splitsPath == standard(copyURL))
        #expect(settings.settings.lastSplitsPath == standard(copyURL))
        #expect(controller.recentSplits == [standard(copyURL), standard(url)])
        #expect(FileManager.default.fileExists(atPath: copyURL.path))
    }

    @Test func aCancelledSaveAsChangesNothing() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let picker = FakeFilePicker(open: [url], save: [nil])
        let controller = makeController(picker: picker)
        controller.openSplits()
        #expect(!controller.saveSplitsAs())
        #expect(controller.splitsPath == standard(url))
        #expect(settings.settings.lastSplitsPath == standard(url))
    }

    @Test func aRunWithNoFileIsSuggestedItsGameAndCategory() {
        let picker = FakeFilePicker(save: [nil])
        let controller = makeController(picker: picker)
        _ = controller.saveSplitsAs()
        // The default run has no game or category.
        #expect(picker.saves.map(\.name) == ["Splits.lss"])
        #expect(picker.saves[0].directory == nil)
    }

    // MARK: 5. Close splits

    @Test func closingSplitsGoesBackToTheNewRunAndKeepsTheLayout() throws {
        let layout = Fixtures.url("TextShadow.ls1l")
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let controller = makeController(picker: FakeFilePicker(open: [url]))
        controller.openLayout(atPath: layout.path)
        controller.openSplits()
        controller.closeSplits()
        #expect(runLength() == 1)
        #expect(controller.splitsPath == nil)
        #expect(settings.settings.lastSplitsPath == nil)
        #expect(window.layoutPath == standard(layout))
        #expect(settings.settings.lastLayoutPath == standard(layout))
        #expect(controller.recentSplits == [standard(url)])
        #expect(logged(.app).contains("Closed splits"))
    }

    @Test func closingSplitsAsksAboutUnsavedChanges() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let alerts = FakeFileAlerts(choices: [.cancel])
        let controller = makeController(picker: FakeFilePicker(open: [url]), alerts: alerts)
        controller.openSplits()
        makeUnsaved()
        controller.closeSplits()
        #expect(alerts.asked == ["Splits.lss"])
        #expect(controller.splitsPath == standard(url))
        #expect(runLength() > 1)
    }

    // MARK: 6. Unsaved changes

    @Test func noChangesMeansNoQuestion() {
        let alerts = FakeFileAlerts()
        #expect(makeController(alerts: alerts).confirmUnsavedChanges())
        #expect(alerts.asked.isEmpty)
    }

    @Test func choosingSaveSavesThenGoesOn() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let alerts = FakeFileAlerts(choices: [.save])
        let controller = makeController(picker: FakeFilePicker(open: [url]), alerts: alerts)
        controller.openSplits()
        makeUnsaved()
        #expect(controller.confirmUnsavedChanges())
        #expect(!content.hasUnsavedChanges)
        #expect(alerts.asked == ["Splits.lss"])
    }

    @Test func choosingSaveThenCancellingTheSaveDialogStops() {
        let alerts = FakeFileAlerts(choices: [.save])
        let controller = makeController(picker: FakeFilePicker(save: [nil]), alerts: alerts)
        makeUnsaved()
        #expect(!controller.confirmUnsavedChanges())
        #expect(alerts.asked == [nil])
        #expect(content.hasUnsavedChanges)
    }

    @Test func choosingSaveWhenTheSaveFailsStops() throws {
        let missing = folder.url.appending(path: "no-such-folder/Splits.lss")
        let alerts = FakeFileAlerts(choices: [.save])
        let controller = makeController(
            picker: FakeFilePicker(save: [missing]), alerts: alerts)
        makeUnsaved()
        #expect(!controller.confirmUnsavedChanges())
        #expect(alerts.saveFailures.count == 1)
        #expect(controller.splitsPath == nil)
        #expect(settings.settings.lastSplitsPath == nil)
        #expect(controller.recentSplits.isEmpty)
        #expect(content.hasUnsavedChanges)
    }

    @Test func choosingDontSaveGoesOnAndCancelStops() {
        let alerts = FakeFileAlerts(choices: [.dontSave, .cancel])
        let controller = makeController(alerts: alerts)
        makeUnsaved()
        #expect(controller.confirmUnsavedChanges())
        #expect(!controller.confirmUnsavedChanges())
        #expect(content.hasUnsavedChanges)
    }

    // MARK: 7. Open layout

    @Test func openingALayoutShowsItAndRecordsIt() throws {
        let layout = Fixtures.url("TextShadow.ls1l")
        let picker = FakeFilePicker(open: [layout])
        let alerts = FakeFileAlerts()
        let controller = makeController(picker: picker, alerts: alerts)
        makeUnsaved()
        controller.openLayout()
        #expect(picker.opens == ["layout"])
        #expect(alerts.asked.isEmpty)
        #expect(window.layoutPath == standard(layout))
        #expect(settings.settings.lastLayoutPath == standard(layout))
        #expect(controller.recentLayouts == [standard(layout)])
        #expect(logged(.app).contains("Opened layout \(standard(layout))"))
    }

    @Test func aLayoutThatDoesntOpenChangesNothing() throws {
        let layout = Fixtures.url("TextShadow.ls1l")
        let bad = try copy("NotSplits.txt", as: "Bad.ls1l")
        let alerts = FakeFileAlerts()
        let controller = makeController(
            picker: FakeFilePicker(open: [layout, bad]), alerts: alerts)
        controller.openLayout()
        let before = settings.settings
        let bytes = settingsFileBytes()
        controller.openLayout()
        #expect(alerts.loadFailures.map(\.file) == ["Bad.ls1l"])
        #expect(alerts.loadFailures.map(\.error) == [.notLayout])
        #expect(window.layoutPath == standard(layout))
        #expect(settings.settings == before)
        #expect(settingsFileBytes() == bytes)
    }

    // MARK: 8. Save layout as

    @Test func savingALayoutAsWritesJsonAndMovesTheWindowFrame() throws {
        let original = try copy("Dark.lsl", as: "Dark.lsl")
        let target = folder.url.appending(path: "Dark.ls1l")
        let picker = FakeFilePicker(save: [target])
        let controller = makeController(picker: picker)
        controller.openLayout(atPath: original.path)
        controller.saveLayoutAs()
        // An .lsl is never the suggested target.
        #expect(picker.saves.map(\.name) == ["Dark.ls1l"])
        #expect(picker.saves[0].kind == "layout")
        #expect(picker.saves[0].directory.map(standard) == standard(folder.url))
        #expect(try LayoutFile.load(target).settingsAsJson() == content.layout.settingsAsJson())
        #expect(window.layoutPath == standard(target))
        #expect(settings.settings.frame(forLayout: standard(target)) != nil)
        #expect(settings.settings.lastLayoutPath == standard(target))
        #expect(controller.recentLayouts == [standard(target), standard(original)])
        #expect(logged(.app).contains("Saved layout to \(standard(target))"))
    }

    @Test func aFailedLayoutSaveReportsAndKeepsTheLayoutPath() throws {
        let layout = Fixtures.url("TextShadow.ls1l")
        let missing = folder.url.appending(path: "no-such-folder/L.ls1l")
        let alerts = FakeFileAlerts()
        let controller = makeController(picker: FakeFilePicker(save: [missing]), alerts: alerts)
        controller.openLayout(atPath: layout.path)
        controller.saveLayoutAs()
        #expect(alerts.saveFailures.map(\.file) == ["L.ls1l"])
        #expect(window.layoutPath == standard(layout))
        #expect(settings.settings.lastLayoutPath == standard(layout))
    }

    @Test func theDefaultLayoutIsSuggestedLayoutDotLs1l() {
        let picker = FakeFilePicker(save: [nil])
        makeController(picker: picker).saveLayoutAs()
        #expect(picker.saves.map(\.name) == ["Layout.ls1l"])
        #expect(picker.saves[0].directory == nil)
    }

    // MARK: 9. Recent files

    @Test func aRecentFileOpensWithoutThePicker() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let picker = FakeFilePicker()
        let controller = makeController(picker: picker)
        controller.openSplits(atPath: url.path)
        #expect(picker.opens.isEmpty)
        #expect(controller.splitsPath == standard(url))
        #expect(runLength() > 1)
    }

    @Test func aRecentFileThatFailsKeepsItsPlace() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let layout = try copy("TextShadow.ls1l", as: "L.ls1l")
        let alerts = FakeFileAlerts()
        let controller = makeController(alerts: alerts)
        controller.openSplits(atPath: url.path)
        controller.openLayout(atPath: layout.path)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.removeItem(at: layout)
        controller.openSplits(atPath: url.path)
        controller.openLayout(atPath: layout.path)
        #expect(alerts.loadFailures.count == 2)
        #expect(controller.recentSplits == [standard(url)])
        #expect(controller.recentLayouts == [standard(layout)])
    }

    @Test func clearMenuEmptiesTheList() throws {
        let url = try copy("GameTime.lss", as: "Splits.lss")
        let layout = Fixtures.url("TextShadow.ls1l")
        let controller = makeController()
        controller.openSplits(atPath: url.path)
        controller.openLayout(atPath: layout.path)
        #expect(!controller.recentSplits.isEmpty)
        #expect(!controller.recentLayouts.isEmpty)
        controller.clearRecentSplits()
        #expect(controller.recentSplits.isEmpty)
        #expect(!controller.recentLayouts.isEmpty)
        controller.clearRecentLayouts()
        #expect(controller.recentLayouts.isEmpty)
        // The last files stay: Clear Menu only forgets the list.
        #expect(settings.settings.lastSplitsPath == standard(url))
    }

    // MARK: 10. Reopen at launch

    @Test func launchReopensTheLastSplitsAndLayout() throws {
        // The splits link to another layout, which launch ignores: last_layout wins.
        let url = try LinkedSplits.write(linking: Fixtures.url("Dark.lsl").path, in: folder)
        let layout = Fixtures.url("TextShadow.ls1l")
        settings.update {
            $0.lastSplitsPath = url.path
            $0.lastLayoutPath = layout.path
        }
        let controller = makeController()
        controller.reopenAtLaunch()
        #expect(runLength() > 1)
        #expect(controller.splitsPath == standard(url))
        #expect(window.layoutPath == standard(layout))
        #expect(!content.hasUnsavedChanges)
        #expect(window.notices.current == nil)
    }

    @Test func launchIgnoresTheLinkedLayout() throws {
        let linked = try LinkedSplits.write(
            linking: Fixtures.url("Dark.lsl").path, in: folder)
        settings.update { $0.lastSplitsPath = linked.path }
        let controller = makeController()
        controller.reopenAtLaunch()
        #expect(runLength() > 1)
        #expect(window.layoutPath == nil)
        #expect(settings.settings.lastLayoutPath == nil)
    }

    @Test func missingKeysReopenNothing() {
        let controller = makeController()
        controller.reopenAtLaunch()
        #expect(runLength() == 1)
        #expect(controller.splitsPath == nil)
        #expect(window.layoutPath == nil)
        #expect(window.notices.current == nil)
    }

    @Test func missingLastFilesGiveNoticesThatQueueAndChangeNothing() throws {
        let splits = folder.url.appending(path: "Gone.lss").path
        let layout = folder.url.appending(path: "Gone.ls1l").path
        settings.update {
            $0.lastSplitsPath = splits
            $0.lastLayoutPath = layout
            $0.recentSplits.add(splits)
            $0.recentLayouts.add(layout)
        }
        let before = settings.settings
        let bytes = settingsFileBytes()
        let controller = makeController()
        controller.reopenAtLaunch()
        #expect(runLength() == 1)
        #expect(controller.splitsPath == nil)
        #expect(window.layoutPath == nil)
        #expect(settings.settings == before)
        #expect(settingsFileBytes() == bytes)
        let first = try #require(window.notices.current)
        #expect(first.hasPrefix("Couldn't reopen \"Gone.lss\": "))
        #expect(window.notices.waiting.count == 1)
        #expect(window.notices.waiting[0].hasPrefix("Couldn't reopen \"Gone.ls1l\": "))
        #expect(logged(.error).filter { $0.hasPrefix("Couldn't open ") }.count == 2)
    }

    @Test func aLastFileThatIsntSplitsGivesAReasonedNotice() throws {
        let bad = try copy("NotSplits.txt", as: "NotSplits.txt")
        settings.update { $0.lastSplitsPath = bad.path }
        makeController().reopenAtLaunch()
        #expect(
            window.notices.current
                == "Couldn't reopen \"NotSplits.txt\": it isn't splits this app can read")
    }
}
