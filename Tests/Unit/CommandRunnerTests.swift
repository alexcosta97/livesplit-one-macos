import Foundation
import LiveSplitCore
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
        changed: @escaping @MainActor @Sendable () -> Void = {}
    ) -> CommandRunner {
        CommandRunner(
            timer: timer, resetSavesBestTimes: resetSavesBestTimes, log: log, changed: changed)
    }

    /// Runs `command` from the menu and returns the reply once it has run.
    private func run(_ runner: CommandRunner, _ command: TimerCommand) async -> String {
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
}
