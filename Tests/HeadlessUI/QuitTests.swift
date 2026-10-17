import AppKit
import Foundation
import LiveSplitCore
import Synchronization
import Testing

@testable import LiveSplitOne

/// Counts the times the reset question is asked.
private final class QuestionCount: Sendable {
    private let stored = Mutex(0)
    var value: Int { stored.withLock { $0 } }
    func add() { stored.withLock { $0 += 1 } }
}

/// Quit's decision (spec §7.1), with the real timer and command runner and fake panels and
/// alerts, so nothing quits and nothing is shown.
@MainActor
@Suite final class QuitTests {
    let folder: TemporaryFolder
    let settings: SettingsStore
    let content = TimerContent(lang: 0)
    let window: TimerWindowController
    let picker = FakeFilePicker()
    let alerts = FakeFileAlerts()
    private let questions = QuestionCount()
    private var runnerInUse: CommandRunner?

    init() throws {
        folder = try TemporaryFolder()
        settings = SettingsStore(
            directory: folder.url.appending(path: "config", directoryHint: .isDirectory))
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        window = TimerWindowController(
            content: content, settings: settings, screens: { [screen] }, mainScreen: { screen },
            notices: NoticeQueue(schedule: { _, _ in }))
    }

    // Ends the window's display link, so they don't pile up across tests.
    isolated deinit {
        window.window.contentView = nil
    }

    private func makeLog(_ name: String) -> Log {
        Log(
            directory: folder.url.appending(path: name, directoryHint: .isDirectory),
            unified: RecordingUnifiedLog())
    }

    /// A quit flow whose reset question, if asked, is answered with `answer`.
    private func makeFlow(
        answering answer: ResetAnswer = .no, alerts alertsOverride: FileAlerts? = nil,
        splitsEditor: SplitsEditorPresenter? = nil
    ) -> QuitFlow {
        let counter = questions
        let runner = CommandRunner(
            timer: content.timer, resetSavesBestTimes: nil, log: makeLog("runner-logs"),
            changed: {},
            ask: {
                counter.add()
                return answer
            },
            remember: { _ in })
        runnerInUse = runner
        let files = FileController(
            content: content, window: window, settings: settings, picker: picker,
            alerts: alertsOverride ?? alerts, lang: 0, log: makeLog("logs"))
        return QuitFlow(
            content: content, runner: runner, files: files, splitsEditor: splitsEditor)
    }

    private func run(_ command: TimerCommand, on runner: CommandRunner) async -> String? {
        await withCheckedContinuation { continuation in
            runner.run(command, from: .menu) { continuation.resume(returning: $0) }
        }
    }

    /// A finished attempt, which has new best times, so resetting it asks.
    private func finishAnAttempt(on runner: CommandRunner) async {
        _ = await run(.splitOrStart, on: runner)
        try? await Task.sleep(for: .milliseconds(10))
        _ = await run(.splitOrStart, on: runner)
    }

    private func makeUnsaved() {
        let sink = EventSink(timer: content.timer, report: { _ in }, decideReset: { .save })
        _ = sink.handleCommand(#"{"command":"splitOrStart"}"#)
        _ = sink.handleCommand(#"{"command":"reset","saveAttempt":true}"#)
    }

    /// The replies of a quit request: the immediate answer, and the replies given later. Waits
    /// for the first later reply, up to a deadline, when the answer is `.terminateLater`.
    private func quit(_ flow: QuitFlow) async -> (NSApplication.TerminateReply, [Bool]) {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        let immediate = flow.shouldTerminate { continuation.yield($0) }
        return (immediate, await replies(stream, continuation, expecting: immediate))
    }

    private func replies(
        _ stream: AsyncStream<Bool>, _ continuation: AsyncStream<Bool>.Continuation,
        expecting immediate: NSApplication.TerminateReply
    ) async -> [Bool] {
        guard immediate == .terminateLater else { return [] }
        let deadline = Task {
            try await Task.sleep(for: .seconds(20))
            continuation.finish()
        }
        var replies: [Bool] = []
        for await reply in stream {
            replies.append(reply)
            break
        }
        deadline.cancel()
        // A second reply, were there one, comes from the same block as the first.
        continuation.finish()
        for await reply in stream { replies.append(reply) }
        return replies
    }

    @Test func withNoChangesItQuitsWithoutAsking() async {
        let (immediate, replies) = await quit(makeFlow())
        #expect(immediate == .terminateNow)
        #expect(replies.isEmpty)
        #expect(alerts.asked.isEmpty)
    }

    /// The editor's OK would replace the run after the questions were answered (spec §9), so
    /// Quit is refused while it is open, without resetting or asking anything.
    @Test func quitIsRefusedWhileTheSplitsEditorIsOpen() async {
        makeUnsaved()
        let editor = SplitsEditorPresenter(
            content: content, window: window, prompts: ScriptedPrompts(), log: makeLog("logs"),
            lang: 0, runModal: { _ in }, stopModal: {})
        editor.open()
        defer { editor.editorWindow?.close() }
        #expect(editor.isOpen)
        let flow = makeFlow(splitsEditor: editor)
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateCancel)
        #expect(replies.isEmpty)
        #expect(alerts.asked.isEmpty)

        editor.applyOK()
        alerts.choices = [.dontSave]
        let (after, _) = await quit(flow)
        #expect(after == .terminateNow)
        #expect(alerts.asked.count == 1)
    }

    @Test func cancelStays() async {
        makeUnsaved()
        alerts.choices = [.cancel]
        let (immediate, replies) = await quit(makeFlow())
        #expect(immediate == .terminateCancel)
        #expect(replies.isEmpty)
        #expect(alerts.asked.count == 1)
        #expect(content.hasUnsavedChanges)
    }

    @Test func dontSaveQuitsAndLeavesTheFileAlone() async {
        makeUnsaved()
        alerts.choices = [.dontSave]
        let (immediate, _) = await quit(makeFlow())
        #expect(immediate == .terminateNow)
        #expect(alerts.asked.count == 1)
        #expect(picker.saves.isEmpty)
    }

    @Test func saveWritesThenQuits() async throws {
        makeUnsaved()
        let url = folder.url.appending(path: "Splits.lss")
        picker.saveAnswers = [url]
        alerts.choices = [.save]
        let (immediate, _) = await quit(makeFlow())
        #expect(immediate == .terminateNow)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!content.hasUnsavedChanges)
    }

    @Test func aCancelledSavePanelStays() async {
        makeUnsaved()
        picker.saveAnswers = [nil]
        alerts.choices = [.save]
        let (immediate, _) = await quit(makeFlow())
        #expect(immediate == .terminateCancel)
        #expect(content.hasUnsavedChanges)
    }

    @Test func aFailedSaveStays() async throws {
        makeUnsaved()
        // A folder can't be written as a file.
        picker.saveAnswers = [folder.url]
        alerts.choices = [.save]
        let (immediate, _) = await quit(makeFlow())
        #expect(immediate == .terminateCancel)
        #expect(alerts.saveFailures.count == 1)
        #expect(content.hasUnsavedChanges)
    }

    @Test(.timeLimit(.minutes(1))) func anAttemptInProgressIsResetFirstThenAskedAbout() async {
        let flow = makeFlow(answering: .no)
        let runner = runnerInUse!
        _ = await run(.splitOrStart, on: runner)
        #expect(content.phase == .running)
        // The default run has one segment; a started attempt reset has no new best times.
        alerts.choices = [.dontSave]
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateLater)
        #expect(replies == [true])
        #expect(content.phase == .notRunning)
        // The reset made the run modified, so it asked about it.
        #expect(alerts.asked.count == 1)
    }

    /// The log names what sent the reset: quitting, not a menu the user never used.
    @Test(.timeLimit(.minutes(1))) func theResetQuitSendsIsLoggedAsFromQuitting() async throws {
        let flow = makeFlow(answering: .no)
        _ = await run(.splitOrStart, on: runnerInUse!)
        alerts.choices = [.dontSave]
        _ = await quit(flow)
        let logs = folder.url.appending(path: "runner-logs", directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(atPath: logs.path)
            .filter { $0.hasSuffix(".log") }
        let text = try String(
            contentsOf: logs.appending(path: try #require(names.first)), encoding: .utf8)
        #expect(text.contains("Reset from quitting"))
        #expect(!text.contains("Reset from the menu"))
    }

    @Test(.timeLimit(.minutes(1))) func theResetQuestionIsAskedForNewBestTimes() async {
        let flow = makeFlow(answering: .yes)
        await finishAnAttempt(on: runnerInUse!)
        #expect(content.phase == .ended)
        alerts.choices = [.dontSave]
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateLater)
        #expect(questions.value == 1)
        #expect(replies == [true])
        #expect(content.phase == .notRunning)
    }

    @Test(.timeLimit(.minutes(1))) func dontResetKeepsTheAppOpenAndTheAttempt() async {
        let flow = makeFlow(answering: .dontReset)
        await finishAnAttempt(on: runnerInUse!)
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateLater)
        #expect(questions.value == 1)
        #expect(replies == [false])
        #expect(content.phase == .ended)
        // It didn't go on to ask about unsaved changes.
        #expect(alerts.asked.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func cancellingTheSaveQuestionAfterTheResetKeepsTheAppOpen()
        async
    {
        let flow = makeFlow(answering: .no)
        _ = await run(.splitOrStart, on: runnerInUse!)
        alerts.choices = [.cancel]
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateLater)
        #expect(replies == [false])
        #expect(alerts.asked.count == 1)
    }

    @Test(.timeLimit(.minutes(1))) func aResetDroppedBehindTheResetQuestionKeepsTheAppOpen()
        async
    {
        let flow = makeFlow(answering: .no)
        let runner = runnerInUse!
        await finishAnAttempt(on: runner)
        alerts.choices = [.dontSave]
        // This reset waits on the main actor for the answer, which can't run until this test
        // awaits, so quitting queues its reset behind it and the answer drops that one.
        runner.run(.reset, from: .keyboard)
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateLater)
        #expect(replies == [false])
        #expect(questions.value == 1)
        #expect(alerts.asked.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func aPausedAttemptIsResetFirstToo() async {
        let flow = makeFlow(answering: .no)
        _ = await run(.splitOrStart, on: runnerInUse!)
        _ = await run(.pause, on: runnerInUse!)
        #expect(content.phase == .paused)
        alerts.choices = [.dontSave]
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateLater)
        #expect(replies == [true])
        #expect(content.phase == .notRunning)
    }

    @Test(.timeLimit(.minutes(1))) func aCancelledSavePanelAfterTheResetKeepsTheAppOpen()
        async
    {
        let flow = makeFlow(answering: .no)
        _ = await run(.splitOrStart, on: runnerInUse!)
        picker.saveAnswers = [nil]
        alerts.choices = [.save]
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateLater)
        #expect(replies == [false])
        #expect(picker.saves.count == 1)
        #expect(content.hasUnsavedChanges)
    }

    @Test(.timeLimit(.minutes(1))) func aFailedSaveAfterTheResetKeepsTheAppOpen() async {
        let flow = makeFlow(answering: .no)
        _ = await run(.splitOrStart, on: runnerInUse!)
        // A folder can't be written as a file.
        picker.saveAnswers = [folder.url]
        alerts.choices = [.save]
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateLater)
        #expect(replies == [false])
        #expect(alerts.saveFailures.count == 1)
        #expect(content.hasUnsavedChanges)
    }

    /// A reset that finds no attempt, because one queued before it ran first, has nothing left
    /// to ask about, so quitting goes on to the save question.
    @Test(.timeLimit(.minutes(1))) func aResetThatFindsNoAttemptGoesOnToTheSaveQuestion()
        async
    {
        let flow = makeFlow(answering: .no)
        let runner = runnerInUse!
        _ = await run(.splitOrStart, on: runner)
        // Holds the command queue, so the resets below wait in order behind it.
        let gate = DispatchSemaphore(value: 0)
        runner.run(.undoAllPauses, from: .keyboard) { _ in gate.wait() }
        runner.run(.reset, from: .keyboard)
        alerts.choices = [.dontSave]
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        let immediate = flow.shouldTerminate { continuation.yield($0) }
        #expect(immediate == .terminateLater)
        gate.signal()
        let replies = await replies(stream, continuation, expecting: immediate)
        #expect(replies == [true])
        #expect(alerts.asked.count == 1)
    }

    @Test func onlyNoRunInProgressLetsAFailedResetQuit() {
        #expect(QuitFlow.resetAllowsQuitting(#"{"success":null}"#))
        #expect(QuitFlow.resetAllowsQuitting(#"{"error":{"code":"NoRunInProgress"}}"#))
        #expect(!QuitFlow.resetAllowsQuitting(#"{"error":{"code":"RunnerDecidedAgainstReset"}}"#))
        #expect(!QuitFlow.resetAllowsQuitting(nil))
    }

    @Test(.timeLimit(.minutes(1))) func aSecondQuitWhileTheFirstIsPendingIsCancelled() async {
        let flow = makeFlow(answering: .yes)
        await finishAnAttempt(on: runnerInUse!)
        alerts.choices = [.dontSave]
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        var secondReplies = 0
        let first = flow.shouldTerminate { continuation.yield($0) }
        // The first is waiting on the reset question, which can't run until this test awaits.
        let second = flow.shouldTerminate { _ in secondReplies += 1 }
        #expect(first == .terminateLater)
        #expect(second == .terminateCancel)
        let replies = await replies(stream, continuation, expecting: first)
        #expect(replies == [true])
        #expect(secondReplies == 0)
        #expect(questions.value == 1)
        #expect(alerts.asked.count == 1)
        // Once decided, a later request is decided afresh.
        alerts.choices = [.dontSave]
        #expect(flow.shouldTerminate { _ in } == .terminateNow)
    }

    /// The save question is a modal alert, which holds up main queue jobs, so the flow asks it
    /// from a run loop block, as the reset question is: a job queued while it's open runs.
    @Test(.timeLimit(.minutes(1))) func otherMainActorWorkRunsWhileTheSaveQuestionIsOpen()
        async
    {
        let modal = ModalAlerts()
        let flow = makeFlow(answering: .no, alerts: modal)
        _ = await run(.splitOrStart, on: runnerInUse!)
        let (immediate, replies) = await quit(flow)
        #expect(immediate == .terminateLater)
        #expect(replies == [true])
        #expect(modal.questions == 1)
        #expect(modal.jobRanWhileOpen)
    }

    // MARK: Launch

    @Test func launchShowsTheSettingsNoticeThenTheReopenNoticesThenTheWindow() {
        let files = FileController(
            content: content, window: window, settings: settings, picker: picker, alerts: alerts,
            lang: 0, log: makeLog("logs"))
        settings.update {
            $0.lastSplitsPath = folder.url.appending(path: "Gone.lss").path
            $0.lastLayoutPath = folder.url.appending(path: "Gone.ls1l").path
        }
        var shown: (current: String?, waiting: [String])?
        files.launch(settingsOutcome: .recovered(reason: "bad")) {
            shown = (window.notices.current, window.notices.waiting)
        }
        #expect(shown?.current == LaunchNotices.settings(.recovered(reason: "bad")))
        #expect(shown?.waiting.count == 2)
        #expect(shown?.waiting.first?.contains("Gone.lss") == true)
        #expect(shown?.waiting.last?.contains("Gone.ls1l") == true)
    }

    @Test func theScriptedPickerIsChosenWhenAnswersAreGiven() {
        #expect(SystemFilePicker.make(scriptedAnswers: ["/tmp/a.lss", nil]) is ScriptedFilePicker)
        #expect(SystemFilePicker.make(scriptedAnswers: nil) is SystemFilePicker)
    }
}

private final class Flag: Sendable {
    private let stored = Mutex(false)
    var value: Bool {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }
}

/// Asks the save question with a real modal alert that a timer closes, and records whether a
/// main actor job queued as it opened ran meanwhile.
@MainActor
private final class ModalAlerts: FileAlerts {
    private(set) var questions = 0
    private let ran = Flag()
    private let ranWhileOpen = Flag()
    var jobRanWhileOpen: Bool { ranWhileOpen.value }

    func askToSave(name: String?) -> SaveChoice {
        questions += 1
        let ran = ran
        let ranWhileOpen = ranWhileOpen
        Task { @MainActor in ran.value = true }
        let alert = NSAlert()
        alert.messageText = "Save?"
        let start = Date()
        let closing = Timer(timeInterval: 0.05, repeats: true) { timer in
            let jobRan = ran.value
            if jobRan || Date().timeIntervalSince(start) > 5 {
                ranWhileOpen.value = jobRan
                timer.invalidate()
                MainActor.assumeIsolated { NSApp.abortModal() }
            }
        }
        RunLoop.main.add(closing, forMode: .common)
        _ = alert.runModal()
        closing.invalidate()
        return .dontSave
    }

    func showLoadFailed(_ error: FileLoadError, file: String) {}
    func showSaveFailed(reason: String, file: String) {}
}
