import Foundation
import LiveSplitCore
import Synchronization
import Testing

@testable import LiveSplitOne

/// With the real livesplit-core. In the unit target because the integration target doesn't
/// compile the app's sources.
@Suite struct CommandRunnerTests {
    private let unified = RecordingUnifiedLog()
    private let folder: TemporaryFolder
    private let log: Log

    init() throws {
        folder = try TemporaryFolder()
        log = Log(directory: folder.url, unified: unified)
    }

    private func makeTimer(segments: Int) -> SharedTimer {
        let run = Run()
        for index in 1...segments { run.pushSegment(Segment("Segment \(index)")) }
        return LiveSplitCore.Timer(run)!.intoShared()
    }

    private func makeRunner(
        _ timer: SharedTimer, resetSavesBestTimes: Bool? = nil,
        changed: @escaping @MainActor @Sendable () -> Void = {},
        ask: @escaping @MainActor @Sendable () -> ResetAnswer = { .yes },
        remember: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) -> CommandRunner {
        CommandRunner(
            timer: timer, resetSavesBestTimes: resetSavesBestTimes, log: log, changed: changed,
            ask: ask, remember: remember)
    }

    /// Runs `command` from the menu and returns the reply once it has run, or nil if it was
    /// dropped.
    private func run(_ runner: CommandRunner, _ command: TimerCommand) async -> String? {
        await withCheckedContinuation { continuation in
            runner.run(command, from: .menu) { continuation.resume(returning: $0) }
        }
    }

    private func phase(_ timer: SharedTimer) -> TimerPhase? {
        TimerMenuState.read(from: timer).phase
    }

    @Test func aCommandMovesTheTimerAndIsLoggedWithItsSource() async {
        let timer = makeTimer(segments: 1)
        let reply = await run(makeRunner(timer), .splitOrStart)
        #expect(reply == #"{"success":null}"#)
        #expect(phase(timer) == .running)
        #expect(
            unified.entries.contains {
                $0.category == .timer
                    && $0.message == #"Start/Split from the menu: {"success":null}"#
            })
    }

    /// `changed` is `@MainActor`, so the compiler already makes it run there: this checks that
    /// it is called at all.
    @Test(.timeLimit(.minutes(1))) func theWindowIsToldOnTheMainActor() async {
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self)
        let runner = makeRunner(makeTimer(segments: 1)) {
            continuation.yield()
        }
        runner.run(.splitOrStart, from: .keyboard)
        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }

    @Test func aRejectedCommandIsLoggedAndChangesNothing() async {
        let timer = makeTimer(segments: 1)
        let reply = await run(makeRunner(timer), .pause)
        #expect(reply == #"{"error":{"code":"NoRunInProgress"}}"#)
        #expect(phase(timer) == .notRunning)
        #expect(
            unified.entries.contains {
                $0.message == #"Pause from the menu: {"error":{"code":"NoRunInProgress"}}"#
            })
    }

    /// Starts, waits and splits the first of two segments, which gives the attempt a new best
    /// segment, then resets. Returns whether the run kept that best segment.
    private func resetWithANewBestSegment(_ runner: CommandRunner, _ timer: SharedTimer) async
        -> Bool
    {
        _ = await run(runner, .splitOrStart)
        try? await Task.sleep(for: .milliseconds(10))
        _ = await run(runner, .splitOrStart)
        #expect(await run(runner, .reset) == #"{"success":null}"#)
        #expect(phase(timer) == .notRunning)
        var kept = false
        timer.readWith { kept = $0.getRun().segment(0).bestSegmentTime().realTime() != nil }
        return kept
    }

    @Test(arguments: zip([nil, true, false] as [Bool?], [true, true, false]))
    func aResetWithNewBestTimesFollowsTheSetting(setting: Bool?, keeps: Bool) async {
        let timer = makeTimer(segments: 2)
        let runner = makeRunner(timer, resetSavesBestTimes: setting)
        #expect(await resetWithANewBestSegment(runner, timer) == keeps)
    }

    @Test(
        arguments: [
            (from: true, to: false, keeps: false),
            (from: false, to: nil, keeps: true),
            (from: nil, to: false, keeps: false),
        ] as [(from: Bool?, to: Bool?, keeps: Bool)])
    func aChangedSettingAppliesToTheNextReset(from: Bool?, to: Bool?, keeps: Bool) async {
        let timer = makeTimer(segments: 2)
        let runner = makeRunner(timer, resetSavesBestTimes: from)
        runner.setResetSavesBestTimes(to)
        #expect(await resetWithANewBestSegment(runner, timer) == keeps)
    }

    // MARK: The reset question

    /// What the test's `ask` and `remember` saw, safe to read from any thread.
    private final class Answers: Sendable {
        private struct State {
            var asked = 0
            var remembered: [Bool] = []
            var onMain: [Bool] = []
            var left: [ResetAnswer] = []
        }

        private let state = Mutex(State())

        init(_ answers: [ResetAnswer]) { state.withLock { $0.left = answers } }

        var asked: Int { state.withLock { $0.asked } }
        var remembered: [Bool] { state.withLock { $0.remembered } }
        var askedOnMain: [Bool] { state.withLock { $0.onMain } }

        func next() -> ResetAnswer {
            state.withLock {
                $0.asked += 1
                $0.onMain.append(Thread.isMainThread)
                return $0.left.isEmpty ? .dontReset : $0.left.removeFirst()
            }
        }

        func remember(_ value: Bool) { state.withLock { $0.remembered.append(value) } }
    }

    private func makeRunner(
        _ timer: SharedTimer, resetSavesBestTimes: Bool? = nil, answers: Answers,
        ask: (@MainActor @Sendable () -> ResetAnswer)? = nil
    ) -> CommandRunner {
        makeRunner(
            timer, resetSavesBestTimes: resetSavesBestTimes,
            ask: ask ?? { answers.next() }, remember: { answers.remember($0) })
    }

    /// Starts and splits the default run, which has one segment and no times, so finishing it
    /// beats every best time, then resets without saving the attempt: the reset asks.
    private func finishThenReset(_ runner: CommandRunner, afterMilliseconds: Int = 10) async
        -> String?
    {
        _ = await run(runner, .splitOrStart)
        try? await Task.sleep(for: .milliseconds(afterMilliseconds))
        _ = await run(runner, .splitOrStart)
        return await run(runner, .reset)
    }

    /// Whether the attempt in progress has new best times, which is when a reset asks.
    private func hasNewBestTimes(_ timer: SharedTimer) -> Bool {
        var has = false
        timer.readWith { has = $0.currentAttemptHasNewBestTimes() }
        return has
    }

    /// Finishes a second, quicker attempt, which beats the first's times, and checks that a
    /// reset now would ask, before resetting it.
    private func resetASecondAttemptThatBeatsTheFirst(
        _ runner: CommandRunner, _ timer: SharedTimer
    ) async throws -> String? {
        _ = await run(runner, .splitOrStart)
        try await Task.sleep(for: .milliseconds(1))
        _ = await run(runner, .splitOrStart)
        try #require(hasNewBestTimes(timer))
        return await run(runner, .reset)
    }

    private func hasBestTime(_ timer: SharedTimer) -> Bool {
        var has = false
        timer.readWith { has = $0.getRun().segment(0).personalBestSplitTime().realTime() != nil }
        return has
    }

    @Test func askingAndYesKeepsTheAttemptAndRemembersIt() async throws {
        let timer = makeTimer(segments: 1)
        let answers = Answers([.yes])
        let runner = makeRunner(timer, answers: answers)
        // A slow first attempt, so the second one clearly beats it.
        #expect(await finishThenReset(runner, afterMilliseconds: 50) == #"{"success":null}"#)
        #expect(hasBestTime(timer))
        await MainActor.run {}
        #expect(answers.remembered == [true])
        // The answer is in force at once: this reset would ask, if it weren't.
        let second = try await resetASecondAttemptThatBeatsTheFirst(runner, timer)
        #expect(second == #"{"success":null}"#)
        #expect(answers.asked == 1)
    }

    @Test func askingAndNoDiscardsTheAttemptAndRemembersIt() async throws {
        let timer = makeTimer(segments: 1)
        let answers = Answers([.no])
        let runner = makeRunner(timer, answers: answers)
        #expect(await finishThenReset(runner) == #"{"success":null}"#)
        #expect(!hasBestTime(timer))
        await MainActor.run {}
        #expect(answers.remembered == [false])
        // The default run has no times, so the second attempt beats the first only if the
        // first's were kept: a discarded one leaves it with new best times again.
        let second = try await resetASecondAttemptThatBeatsTheFirst(runner, timer)
        #expect(second == #"{"success":null}"#)
        #expect(answers.asked == 1)
    }

    @Test func askingAndDontResetLeavesTheTimerRunningAndAsksAgain() async {
        let timer = makeTimer(segments: 2)
        let answers = Answers([.dontReset, .dontReset])
        let runner = makeRunner(timer, answers: answers)
        _ = await run(runner, .splitOrStart)
        try? await Task.sleep(for: .milliseconds(10))
        // The first of two segments is split: the attempt has a new best segment.
        _ = await run(runner, .splitOrStart)
        let reply = await run(runner, .reset)
        #expect(reply == #"{"error":{"code":"RunnerDecidedAgainstReset"}}"#)
        #expect(phase(timer) == .running)
        await MainActor.run {}
        #expect(answers.remembered.isEmpty)
        _ = await run(runner, .reset)
        #expect(answers.asked == 2)
    }

    @Test(arguments: [true, false])
    func aSettingMeansNoQuestion(setting: Bool) async {
        let timer = makeTimer(segments: 1)
        let answers = Answers([])
        let runner = makeRunner(timer, resetSavesBestTimes: setting, answers: answers)
        #expect(await finishThenReset(runner) == #"{"success":null}"#)
        #expect(answers.asked == 0)
        #expect(hasBestTime(timer) == setting)
    }

    @Test func theQuestionIsAskedOnTheMainThread() async {
        let answers = Answers([.yes])
        let runner = makeRunner(makeTimer(segments: 1), answers: answers)
        _ = await finishThenReset(runner)
        #expect(answers.askedOnMain == [true])
    }

    @Test(.timeLimit(.minutes(1))) func commandsQueuedWhileItIsOpenAreDropped()
        async
    {
        let timer = makeTimer(segments: 2)
        let open = DispatchSemaphore(value: 0)
        let answers = Answers([.dontReset])
        let runner = makeRunner(
            timer, answers: answers,
            ask: {
                open.wait()
                return answers.next()
            })
        _ = await run(runner, .splitOrStart)
        try? await Task.sleep(for: .milliseconds(10))
        _ = await run(runner, .splitOrStart)
        _ = await run(runner, .splitOrStart)
        #expect(phase(timer) == .ended)

        // The reset waits in `ask`; the split is queued behind it, then the question is answered.
        // The sleeps only make it likely that `ask` is blocking when the split is sent;
        // correctness doesn't depend on them: the split is behind the reset either way.
        let (resets, resetDone) = AsyncStream.makeStream(of: String?.self)
        let (splits, splitDone) = AsyncStream.makeStream(of: String?.self)
        runner.run(.reset, from: .menu) { resetDone.yield($0) }
        try? await Task.sleep(for: .milliseconds(100))
        runner.run(.splitOrStart, from: .menu) { splitDone.yield($0) }
        try? await Task.sleep(for: .milliseconds(100))
        open.signal()
        var resetReplies = resets.makeAsyncIterator()
        var splitReplies = splits.makeAsyncIterator()
        let resetReply = await resetReplies.next()
        #expect(resetReply == #"{"error":{"code":"RunnerDecidedAgainstReset"}}"#)
        let splitReply = await splitReplies.next()
        #expect(splitReply == .some(nil))
        #expect(
            unified.entries.contains {
                $0.category == .timer
                    && $0.message
                        == "Start/Split from the menu dropped: it waited behind the reset question"
            })
        #expect(phase(timer) == .ended)

        // A command queued after the answer runs.
        #expect(await run(runner, .undoSplit) != nil)
        #expect(phase(timer) == .running)
    }

    /// The epoch moves as soon as the question is answered, on the main actor, not later on the
    /// command's thread: a command sent right after the answer, such as a shortcut handled when
    /// the alert closes, isn't dropped. The command's thread is held once the answer is back, so
    /// the command is queued before it could have moved the epoch itself.
    @Test(.timeLimit(.minutes(1))) func aCommandSentRightAfterTheAnswerRuns() async {
        let timer = makeTimer(segments: 2)
        let (reached, reachedSignal) = AsyncStream.makeStream(of: Void.self)
        let gate = DispatchSemaphore(value: 0)
        let runner = CommandRunner(
            timer: timer, resetSavesBestTimes: nil, log: log, changed: {},
            ask: { .dontReset }, remember: { _ in },
            answered: {
                reachedSignal.yield()
                gate.wait()
            })
        _ = await run(runner, .splitOrStart)
        try? await Task.sleep(for: .milliseconds(10))
        _ = await run(runner, .splitOrStart)
        let (replies, replied) = AsyncStream.makeStream(of: String?.self)
        runner.run(.reset, from: .menu) { _ in }
        var arrived = reached.makeAsyncIterator()
        await arrived.next()
        runner.run(.undoSplit, from: .keyboard) { replied.yield($0) }
        gate.signal()
        var iterator = replies.makeAsyncIterator()
        let reply = await iterator.next()
        #expect(reply != .some(nil))
    }
}

/// The sink's events, as the server client is told of them (spec §8.2).
@Suite struct CommandRunnerEventTests {
    private let folder: TemporaryFolder
    private let log: Log

    init() throws {
        folder = try TemporaryFolder()
        log = Log(directory: folder.url, unified: RecordingUnifiedLog())
    }

    /// Collects events from whatever thread reports them.
    private final class Events: Sendable {
        private let stored = Mutex<[TimerEvent]>([])
        var all: [TimerEvent] { stored.withLock { $0 } }
        func append(_ event: TimerEvent) { stored.withLock { $0.append(event) } }
    }

    private func makeRunner(_ events: Events) -> (CommandRunner, SharedTimer) {
        let run = Run()
        run.pushSegment(Segment("Time"))
        let timer = LiveSplitCore.Timer(run)!.intoShared()
        let runner = CommandRunner(
            timer: timer, resetSavesBestTimes: nil, log: log, changed: {}, remember: { _ in })
        runner.observeEvents { events.append($0) }
        return (runner, timer)
    }

    private func run(_ runner: CommandRunner, _ command: TimerCommand) async -> String? {
        await withCheckedContinuation { continuation in
            runner.run(command, from: .menu) { continuation.resume(returning: $0) }
        }
    }

    @Test func aMenuCommandsEventIsReportedOnce() async {
        let events = Events()
        let (runner, _) = makeRunner(events)
        _ = await run(runner, .splitOrStart)
        #expect(events.all == [.started])
    }

    @Test func aRejectedCommandReportsNothing() async {
        let events = Events()
        let (runner, _) = makeRunner(events)
        #expect(await run(runner, .pause) == #"{"error":{"code":"NoRunInProgress"}}"#)
        #expect(events.all.isEmpty)
    }

    @Test func aCommandSentStraightToTheSinkFromAnotherThreadIsReportedToo() async {
        let events = Events()
        let (runner, _) = makeRunner(events)
        let reply = await withCheckedContinuation { continuation in
            DispatchQueue(label: "test.server").async {
                continuation.resume(returning: runner.sink.handleCommand(#"{"command":"start"}"#))
            }
        }
        #expect(reply == #"{"success":null}"#)
        #expect(events.all == [.started])
    }
}
