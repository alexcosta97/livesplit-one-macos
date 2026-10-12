import AppKit
import Foundation
import LiveSplitCore
import Synchronization
import Testing

@testable import LiveSplitOne

/// Quit's decision (spec §7.1), with the real timer and command runner and fake panels and
/// alerts, so nothing quits and nothing is shown.
/// Counts the times the reset question is asked.
private final class QuestionCount: Sendable {
    private let stored = Mutex(0)
    var value: Int { stored.withLock { $0 } }
    func add() { stored.withLock { $0 += 1 } }
}

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
            content: content, settings: settings, screens: [screen], mainScreen: screen,
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
    private func makeFlow(answering answer: ResetAnswer = .no) -> QuitFlow {
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
            content: content, window: window, settings: settings, picker: picker, alerts: alerts,
            lang: 0, log: makeLog("logs"))
        return QuitFlow(content: content, runner: runner, files: files)
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

    /// The reply of `shouldTerminate`: the immediate one, and the replies given later.
    private func quit(_ flow: QuitFlow) async -> (NSApplication.TerminateReply, [Bool]) {
        var replies: [Bool] = []
        let immediate = flow.shouldTerminate { replies.append($0) }
        if immediate == .terminateLater {
            for _ in 0..<200 where replies.isEmpty {
                try? await Task.sleep(for: .milliseconds(50))
            }
            // Time for a second reply to show.
            try? await Task.sleep(for: .milliseconds(100))
        }
        return (immediate, replies)
    }

    @Test func withNoChangesItQuitsWithoutAsking() async {
        let (immediate, replies) = await quit(makeFlow())
        #expect(immediate == .terminateNow)
        #expect(replies.isEmpty)
        #expect(alerts.asked.isEmpty)
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
        var replies: [Bool] = []
        let immediate = flow.shouldTerminate { replies.append($0) }
        #expect(immediate == .terminateLater)
        for _ in 0..<100 where replies.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(replies == [false])
        #expect(questions.value == 1)
        #expect(alerts.asked.isEmpty)
    }

    // MARK: Launch

    @Test func theScriptedPickerIsChosenWhenAnswersAreGiven() {
        #expect(SystemFilePicker.make(scriptedAnswers: ["/tmp/a.lss", nil]) is ScriptedFilePicker)
        #expect(SystemFilePicker.make(scriptedAnswers: nil) is SystemFilePicker)
    }
}
