import Foundation
import LiveSplitCore
import Synchronization
import Testing

@testable import LiveSplitOne

/// The server client with fake sockets, a schedule the test runs, and the real livesplit-core
/// (spec §8).
@MainActor
@Suite(.timeLimit(.minutes(1))) final class ServerClientTests {
    let unified = RecordingUnifiedLog()
    let folder: TemporaryFolder
    let log: Log
    let sockets = FakeSockets()
    var notices: [String] = []
    /// Retries waiting to run, with their delays.
    var scheduled: [(delay: TimeInterval, action: @MainActor @Sendable () -> Void)] = []
    let server = try! ServerURL.parse("192.168.1.20:9087").get()
    let timer: SharedTimer
    var runner: CommandRunner!
    var client: ServerClient!

    init() throws {
        folder = try TemporaryFolder()
        log = Log(directory: folder.url, unified: unified)
        let run = Run()
        run.pushSegment(Segment("One"))
        run.pushSegment(Segment("Two"))
        timer = LiveSplitCore.Timer(run)!.intoShared()
        makeClient()
    }

    /// A new runner and client. `ask` and `answered` are the runner's reset question hooks.
    func makeClient(
        ask: @escaping @MainActor @Sendable () -> ResetAnswer = { .no },
        answered: @escaping @Sendable () -> Void = {}
    ) {
        let runner = CommandRunner(
            timer: timer, resetSavesBestTimes: nil, log: log, changed: {}, ask: ask,
            remember: { _ in }, answered: answered)
        let client = ServerClient(
            sink: runner.sink, notices: { [unowned self] in notices.append($0) }, log: log,
            makeSocket: sockets.factory,
            schedule: { [unowned self] in scheduled.append(($0, $1)) })
        runner.observeEvents { client.send($0) }
        self.runner = runner
        self.client = client
    }

    /// Lets the main queue run what the sockets' callbacks handed to it.
    func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Runs the retry waiting first.
    func runRetry() {
        let (_, action) = scheduled.removeFirst()
        action()
    }

    func connected() async throws -> FakeSocket {
        client.connect(to: server)
        let socket = try #require(sockets.last)
        socket.open()
        await settle()
        #expect(client.status == .connected(server))
        return socket
    }

    func connectionLines() -> [String] {
        unified.entries.filter { $0.category == .connection }.map(\.message)
    }

    func run(_ command: TimerCommand) async -> String? {
        await withCheckedContinuation { continuation in
            runner.run(command, from: .menu) { continuation.resume(returning: $0) }
        }
    }

    // MARK: Status and notices

    @Test func connectingThenOpenShowsConnected() async throws {
        client.connect(to: server)
        #expect(client.status == .connecting(server))
        #expect(sockets.last?.url.absoluteString == "ws://192.168.1.20:9087")
        #expect(sockets.last?.started == true)
        #expect(notices.isEmpty)
        sockets.last?.open()
        await settle()
        #expect(client.status == .connected(server))
        #expect(notices == ["Connected to 192.168.1.20:9087"])
        #expect(
            connectionLines() == [
                "Connecting to ws://192.168.1.20:9087", "Connected to 192.168.1.20:9087",
            ])
    }

    @Test func aFailedFirstAttemptDoesntRetry() async throws {
        client.connect(to: server)
        sockets.last?.end("Could not connect to the server.")
        await settle()
        #expect(client.status == .notConnected)
        #expect(
            notices == ["Couldn't connect to 192.168.1.20:9087: Could not connect to the server."])
        #expect(scheduled.isEmpty)
        #expect(
            unified.entries.contains {
                $0.category == .error
                    && $0.message
                        == "Couldn't connect to 192.168.1.20:9087: Could not connect to the server."
            })
    }

    @Test func aLostConnectionRetriesWithGrowingWaitsAndOneNotice() async throws {
        let first = try await connected()
        first.end("The server stopped answering.")
        await settle()
        #expect(client.status == .retrying(server, attempt: 0))
        var waits: [TimeInterval] = []
        for _ in 0..<7 {
            let (delay, _) = try #require(scheduled.first)
            waits.append(delay)
            runRetry()
            sockets.last?.end("Could not connect to the server.")
            await settle()
        }
        #expect(waits == [1, 2, 4, 8, 16, 30, 30])
        #expect(
            notices == [
                "Connected to 192.168.1.20:9087", "Lost connection to 192.168.1.20:9087, retrying…",
            ])
        #expect(connectionLines().contains("Retrying 192.168.1.20:9087 in 30 s"))
        #expect(connectionLines().contains("Retry failed: Could not connect to the server."))
        #expect(
            connectionLines().contains(
                "Lost connection to 192.168.1.20:9087: The server stopped answering."))

        runRetry()
        sockets.last?.open()
        await settle()
        #expect(client.status == .connected(server))
        #expect(notices.last == "Connected to 192.168.1.20:9087")

        // The next loss starts again from 1 s.
        sockets.last?.end("The server closed the connection.")
        await settle()
        #expect(scheduled.map { $0.delay } == [1])
    }

    @Test func disconnectWhileConnectingLeavesNothingRunning() async throws {
        client.connect(to: server)
        let socket = try #require(sockets.last)
        client.disconnect()
        #expect(socket.closed)
        #expect(client.status == .notConnected)
        socket.open()
        socket.end("late")
        await settle()
        #expect(client.status == .notConnected)
        #expect(notices.isEmpty)
        #expect(connectionLines().last == "Disconnected from 192.168.1.20:9087")
    }

    @Test func disconnectWhileConnectedClosesTheSocketWithoutANotice() async throws {
        let socket = try await connected()
        client.disconnect()
        #expect(socket.closed)
        #expect(client.status == .notConnected)
        socket.end("late")
        await settle()
        #expect(client.status == .notConnected)
        #expect(scheduled.isEmpty)
        #expect(notices == ["Connected to 192.168.1.20:9087"])
    }

    @Test func disconnectWhileWaitingForARetryCancelsIt() async throws {
        let socket = try await connected()
        socket.end("The server closed the connection.")
        await settle()
        client.disconnect()
        #expect(client.status == .notConnected)
        let made = sockets.all.count
        runRetry()
        #expect(sockets.all.count == made)
        #expect(client.status == .notConnected)
    }

    @Test func aStaleRetryDoesNothingAfterReconnecting() async throws {
        let socket = try await connected()
        socket.end("The server closed the connection.")
        await settle()
        client.disconnect()
        _ = try await connected()
        let made = sockets.all.count
        runRetry()
        #expect(sockets.all.count == made)
        #expect(client.status == .connected(server))
    }

    @Test func theMenuTitleFollowsTheStatus() async throws {
        var titles: [String] = []
        client.onStatusChange = { titles.append($0.menuTitle) }
        let socket = try await connected()
        client.disconnect()
        _ = socket
        #expect(
            titles == [
                "Disconnect from 192.168.1.20:9087", "Disconnect from 192.168.1.20:9087",
                "Connect to Server…",
            ])
    }

    // MARK: Messages and events

    @Test func aMessageRunsOnTheSinkAndItsEventGoesBeforeItsReply() async throws {
        let socket = try await connected()
        socket.receive(.text(#"{"command":"splitOrStart"}"#))
        #expect(await socket.waitForSent(2))
        #expect(socket.sent == [#"{"event":"Started"}"#, #"{"success":null}"#])
        #expect(TimerMenuState.read(from: timer).phase == .running)
    }

    @Test func aBinaryMessageIsAnInvalidCommand() async throws {
        let socket = try await connected()
        socket.receive(.binary)
        #expect(await socket.waitForSent(1))
        #expect(socket.sent == [#"{"Err":{"code":"InvalidCommand"}}"#])
        #expect(
            connectionLines().last
                == #"Received a binary message, replied {"Err":{"code":"InvalidCommand"}}"#)
    }

    @Test func repliesGoInTheOrderTheMessagesCame() async throws {
        let socket = try await connected()
        for index in 0..<10 {
            socket.receive(.text(#"{"command":"setComparison","comparison":"C\#(index)"}"#))
        }
        #expect(await socket.waitForSent(10))
        // Each is rejected the same way, so the log tells them apart.
        let received = connectionLines().filter { $0.hasPrefix("Received ") }
        #expect(
            received.map { $0.components(separatedBy: ", replied").first! }
                == (0..<10).map {
                    #"Received {"command":"setComparison","comparison":"C\#($0)"}"#
                })
        #expect(socket.sent.count == 10)
    }

    @Test func aReplyFinishedAfterDisconnectIsDropped() async throws {
        let gate = DispatchSemaphore(value: 0)
        let (reached, reachedSignal) = AsyncStream.makeStream(of: Void.self)
        makeClient(
            ask: { .no },
            answered: {
                reachedSignal.yield()
                gate.wait()
            })
        let socket = try await connected()
        socket.receive(.text(#"{"command":"splitOrStart"}"#))
        try await Task.sleep(for: .milliseconds(10))
        socket.receive(.text(#"{"command":"split"}"#))
        socket.receive(.text(#"{"command":"split"}"#))
        #expect(await socket.waitForSent(6))
        // The run ended with new best times: this reset asks, and waits once answered.
        socket.receive(.text(#"{"command":"reset"}"#))
        var iterator = reached.makeAsyncIterator()
        await iterator.next()
        client.disconnect()
        gate.signal()
        try await Task.sleep(for: .milliseconds(300))
        #expect(socket.sent.count == 6)
        #expect(!socket.sent.contains(#"{"event":"Reset"}"#))
    }

    @Test func aLocalSplitIsSentWhileConnectedOnly() async throws {
        _ = await run(.splitOrStart)
        #expect(sockets.all.isEmpty)
        let socket = try await connected()
        _ = await run(.splitOrStart)
        #expect(await socket.waitForSent(1))
        #expect(socket.sent == [#"{"event":"Splitted"}"#])
        #expect(connectionLines().last == #"Sent {"event":"Splitted"}"#)
        client.disconnect()
        _ = await run(.undoSplit)
        #expect(socket.sent.count == 1)
    }

    @Test func aRunOfGameTimesIsLoggedOnce() async throws {
        let socket = try await connected()
        socket.receive(.text(#"{"command":"splitOrStart"}"#))
        socket.receive(.text(#"{"command":"initializeGameTime"}"#))
        for time in ["1:01.0", "1:02.0", "1:03.0"] {
            socket.receive(.text(#"{"command":"setGameTime","time":"\#(time)"}"#))
        }
        socket.receive(.text(#"{"command":"pause"}"#))
        #expect(await socket.waitForSent(12))
        let lines = connectionLines()
        #expect(lines.filter { $0.contains("setGameTime") }.count == 1)
        #expect(lines.filter { $0 == #"Sent {"event":"GameTimeSet"}"# }.count == 1)
        #expect(lines.contains { $0.hasPrefix(#"Received {"command":"pause"}"#) })
        #expect(lines.contains(#"Sent {"event":"Paused"}"#))
        // Every message was still applied and answered.
        #expect(socket.sent.filter { $0 == #"{"event":"GameTimeSet"}"# }.count == 3)

        // A new connection starts a new filter.
        client.disconnect()
        let second = try await connected()
        second.receive(.text(#"{"command":"setGameTime","time":"1:04.0"}"#))
        #expect(await second.waitForSent(2))
        #expect(connectionLines().filter { $0.contains("setGameTime") }.count == 2)
    }

    /// A menu reset waiting for its question holds the menus' queue, not the server's: a server
    /// command gets `Busy` from the sink at once (spec §8.2).
    @Test func aServerCommandGetsBusyWhileAMenuResetWaitsForItsQuestion() async throws {
        let gate = DispatchSemaphore(value: 0)
        let (reached, reachedSignal) = AsyncStream.makeStream(of: Void.self)
        makeClient(
            ask: { .dontReset },
            answered: {
                reachedSignal.yield()
                gate.wait()
            })
        let socket = try await connected()
        _ = await run(.splitOrStart)
        try await Task.sleep(for: .milliseconds(10))
        _ = await run(.splitOrStart)
        #expect(await socket.waitForSent(2))
        runner.run(.reset, from: .menu)
        var iterator = reached.makeAsyncIterator()
        await iterator.next()
        socket.receive(.text(#"{"command":"split"}"#))
        #expect(await socket.waitForSent(3))
        #expect(socket.sent.last == #"{"error":{"code":"Busy"}}"#)
        gate.signal()
    }
}
