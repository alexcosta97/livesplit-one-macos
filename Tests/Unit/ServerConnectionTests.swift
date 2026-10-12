import Foundation
import LiveSplitCore
import Testing

@testable import LiveSplitOne

/// The server client with the real socket, the real livesplit-core and the fake server: server
/// commands move the timer, events reach the server in order, and the client reconnects (spec
/// §8, §14.1). In the unit target because the integration target doesn't compile the app's
/// sources.
@MainActor
@Suite(.timeLimit(.minutes(1))) final class ServerConnectionTests {
    let folder: TemporaryFolder
    let log: Log
    let timer: SharedTimer
    let runner: CommandRunner
    let fakeServer: FakeServer
    var notices: [String] = []
    var client: ServerClient!

    init() throws {
        folder = try TemporaryFolder()
        log = Log(directory: folder.url, unified: RecordingUnifiedLog())
        let run = Run()
        run.pushSegment(Segment("One"))
        run.pushSegment(Segment("Two"))
        timer = LiveSplitCore.Timer(run)!.intoShared()
        runner = CommandRunner(
            timer: timer, resetSavesBestTimes: nil, log: log, changed: {}, remember: { _ in })
        fakeServer = try FakeServer()
        // Retries come 10 times sooner; their order is checked with fake sockets.
        client = ServerClient(
            sink: runner.sink, notices: { [unowned self] in notices.append($0) }, log: log,
            schedule: { delay, action in NoticeQueue.afterDelay(delay / 10, action) })
        runner.observeEvents { [client] in client?.send($0) }
    }

    deinit {
        fakeServer.stop()
    }

    private var server: ServerURL { try! ServerURL.parse(fakeServer.url.absoluteString).get() }

    /// Waits until `condition` holds, up to `timeout` seconds, letting the main actor run.
    private func wait(timeout: TimeInterval = 10, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func connect() async {
        client.connect(to: server)
        #expect(await wait { client.status == .connected(server) })
        #expect(await fakeServer.waitForConnection())
    }

    private func phase() -> TimerPhase? { TimerMenuState.read(from: timer).phase }

    @Test func theServersCommandMovesTheTimerAndItsEventComesBeforeItsReply() async {
        await connect()
        fakeServer.send(#"{"command":"splitOrStart"}"#)
        #expect(await wait { fakeServer.messages.count == 2 })
        #expect(fakeServer.messages == [#"{"event":"Started"}"#, #"{"success":null}"#])
        #expect(phase() == .running)
        client.disconnect()
    }

    @Test func aLocalSplitReachesTheServer() async {
        await connect()
        fakeServer.send(#"{"command":"start"}"#)
        #expect(await wait { fakeServer.messages.count == 2 })
        runner.run(.splitOrStart, from: .keyboard)
        #expect(await fakeServer.waitForMessage { $0 == #"{"event":"Splitted"}"# } != nil)
        client.disconnect()
    }

    @Test func aDroppedConnectionIsRetriedAndCommandsWorkAgain() async {
        await connect()
        fakeServer.dropConnections()
        #expect(await wait { notices.contains("Lost connection to \(server.host), retrying…") })
        // The first retry comes after 1 s, shortened to 0.1 s.
        #expect(await wait(timeout: 2) { client.status == .connected(server) })
        #expect(notices.filter { $0 == "Connected to \(server.host)" }.count == 2)
        #expect(await fakeServer.waitForConnection())
        fakeServer.send(#"{"command":"splitOrStart"}"#)
        #expect(await fakeServer.waitForMessage { $0 == #"{"event":"Started"}"# } != nil)
        client.disconnect()
    }

    @Test func disconnectSendsANormalCloseAndNothingAfter() async {
        await connect()
        client.disconnect()
        #expect(await wait { fakeServer.normalCloses == 1 })
        runner.run(.splitOrStart, from: .menu)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(fakeServer.messages.isEmpty)
        #expect(phase() == .running)
    }

    @Test func aPortWithNoListenerFailsWithoutRetrying() async {
        let server = server
        fakeServer.stop()
        client.connect(to: server)
        #expect(await wait { client.status == .notConnected })
        #expect(notices.count == 1)
        #expect(notices.first?.hasPrefix("Couldn't connect to \(server.host): ") == true)
        try? await Task.sleep(for: .milliseconds(500))
        #expect(client.status == .notConnected)
    }
}
