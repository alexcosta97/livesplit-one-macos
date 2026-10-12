import Foundation
import Testing

@testable import LiveSplitOne

/// The real socket against the fake server (spec §14.1). In the unit target because the
/// integration target doesn't compile the app's sources.
@Suite(.timeLimit(.minutes(1))) struct URLSessionWebSocketTests {
    private func open(
        _ server: FakeServer, _ recorder: SocketRecorder, pingInterval: TimeInterval = 10,
        pongTimeout: TimeInterval = 10
    ) async throws -> URLSessionWebSocket {
        let socket = URLSessionWebSocket(
            url: server.url, pingInterval: pingInterval, pongTimeout: pongTimeout)
        socket.start(events: recorder.events)
        #expect(await recorder.wait { $0 == "opened" })
        #expect(await server.waitForConnection())
        return socket
    }

    @Test func receivesTheServersMessagesInOrder() async throws {
        let server = try FakeServer()
        let recorder = SocketRecorder()
        let socket = try await open(server, recorder)
        server.send(#"{"command":"start"}"#)
        server.sendBinary()
        server.send(#"{"command":"split"}"#)
        #expect(await recorder.wait { $0 == #"text {"command":"split"}"# })
        #expect(
            recorder.all == [
                "opened", #"text {"command":"start"}"#, "binary", #"text {"command":"split"}"#,
            ])
        socket.close()
    }

    @Test func whatItSendsReachesTheServer() async throws {
        let server = try FakeServer()
        let socket = try await open(server, SocketRecorder())
        socket.send("one")
        socket.send("two")
        #expect(await server.wait { server.messages.count == 2 })
        #expect(server.messages == ["one", "two"])
        socket.close()
    }

    @Test func closeSendsANormalCloseAndReportsNothing() async throws {
        let server = try FakeServer()
        let recorder = SocketRecorder()
        let socket = try await open(server, recorder)
        socket.close()
        #expect(await server.wait { server.normalCloses == 1 })
        try await Task.sleep(for: .milliseconds(500))
        #expect(recorder.all == ["opened"])
    }

    @Test func aDroppedConnectionEndsIt() async throws {
        let server = try FakeServer()
        let recorder = SocketRecorder()
        _ = try await open(server, recorder)
        server.dropConnections()
        #expect(await recorder.wait { $0.hasPrefix("ended ") })
        #expect(recorder.all.filter { $0.hasPrefix("ended ") }.count == 1)
    }

    @Test func aPortNobodyListensOnEndsItWithMacOSsReason() async throws {
        let server = try FakeServer()
        let url = server.url
        server.stop()
        let recorder = SocketRecorder()
        URLSessionWebSocket(url: url).start(events: recorder.events)
        #expect(await recorder.wait { $0.hasPrefix("ended ") })
        #expect(!recorder.all.contains("opened"))
        #expect(!recorder.all.contains("ended \(URLSessionWebSocket.timeoutReason)"))
    }

    @Test func noHandshakeEndsItWithTheTimeout() async throws {
        let server = try FakeServer(webSocket: false)
        let recorder = SocketRecorder()
        URLSessionWebSocket(url: server.url, handshakeTimeout: 1).start(events: recorder.events)
        #expect(await recorder.wait { $0.hasPrefix("ended ") })
        #expect(recorder.all == ["ended The server didn't answer within 10 seconds."])
        server.stop()
    }

    @Test func noPongEndsIt() async throws {
        let server = try FakeServer(autoReplyPing: false)
        let recorder = SocketRecorder()
        _ = try await open(server, recorder, pingInterval: 0.5, pongTimeout: 0.5)
        #expect(await recorder.wait { $0.hasPrefix("ended ") })
        #expect(recorder.all == ["opened", "ended The server stopped answering."])
    }

    @Test func answeredPingsKeepAnIdleConnectionOpen() async throws {
        let server = try FakeServer()
        let recorder = SocketRecorder()
        let socket = try await open(server, recorder, pingInterval: 0.5, pongTimeout: 0.5)
        try await Task.sleep(for: .seconds(3))
        #expect(recorder.all == ["opened"])
        #expect(server.openConnections == 1)
        socket.close()
    }

    @Test func reasonsAreTheTextTheUserSees() {
        #expect(
            URLSessionWebSocket.reason(for: URLError(.notConnectedToInternet))
                == "LiveSplit One for macOS needs local network access. Allow it in System "
                + "Settings › Privacy & Security › Local Network.")
        #expect(
            URLSessionWebSocket.reason(for: URLError(.timedOut))
                == "The server didn't answer within 10 seconds.")
        let refused = URLError(.cannotConnectToHost)
        #expect(URLSessionWebSocket.reason(for: refused) == refused.localizedDescription)
    }
}
