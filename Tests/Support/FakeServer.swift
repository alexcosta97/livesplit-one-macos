import Foundation
@preconcurrency import Network
import Synchronization

/// A LiveSplit One server for tests (spec §14.1, §14.2): a Network.framework WebSocket listener
/// on 127.0.0.1. It answers nothing on its own: it records what the app sends, and the test
/// sends the commands.
final class FakeServer: @unchecked Sendable {
    private struct State {
        var connections: [NWConnection] = []
        var connectionCount = 0
        var messages: [String] = []
        var normalCloses = 0
        var accepting = true
        var failure: NWError?
    }

    /// `ws://127.0.0.1:<port>`.
    var url: URL { URL(string: "ws://127.0.0.1:\(port)")! }
    var port: UInt16 { listener.port?.rawValue ?? 0 }
    private let listener: NWListener
    private let webSocket: Bool
    private let queue = DispatchQueue(label: "dev.alexcosta.livesplit-one-macos.fake-server")
    private let state = Mutex(State())
    private let ready = DispatchSemaphore(value: 0)

    /// `webSocket: false` makes a plain TCP listener, which accepts connections and never
    /// answers the WebSocket handshake. `autoReplyPing: false` never answers pings.
    init(webSocket: Bool = true, autoReplyPing: Bool = true) throws {
        let parameters = NWParameters.tcp
        if webSocket {
            let options = NWProtocolWebSocket.Options()
            options.autoReplyPing = autoReplyPing
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        }
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.webSocket = webSocket
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: ready.signal()
            case .failed(let error):
                self.state.withLock { $0.failure = error }
                ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 10)
        if let error = state.withLock({ $0.failure }) { throw error }
        guard listener.port != nil else { throw NWError.posix(.EADDRNOTAVAIL) }
    }

    deinit {
        stop()
    }

    /// Whether new connections are accepted. While `false`, each is closed at once.
    var accepting: Bool {
        get { state.withLock { $0.accepting } }
        set { state.withLock { $0.accepting = newValue } }
    }

    /// The text messages received so far, in order, from every connection.
    var messages: [String] { state.withLock { $0.messages } }
    /// How many connections were accepted so far.
    var connectionCount: Int { state.withLock { $0.connectionCount } }
    /// How many connections are open now.
    var openConnections: Int { state.withLock { $0.connections.count } }
    /// How many connections the app closed with the normal close code.
    var normalCloses: Int { state.withLock { $0.normalCloses } }

    /// Sends a text message to every open connection.
    func send(_ text: String) {
        send(Data(text.utf8), opcode: .text)
    }

    /// Sends a binary message to every open connection.
    func sendBinary(_ data: Data = Data([1, 2, 3])) {
        send(data, opcode: .binary)
    }

    /// Ends every open connection without a close frame, as a crash would.
    func dropConnections() {
        let connections = state.withLock { state in
            defer { state.connections = [] }
            return state.connections
        }
        for connection in connections { connection.forceCancel() }
    }

    /// Stops listening and ends every connection.
    func stop() {
        listener.cancel()
        dropConnections()
    }

    /// Waits until `condition` holds, up to `timeout` seconds. Returns whether it did.
    func wait(timeout: TimeInterval = 10, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    /// Waits for a received message that `matches`, and returns it.
    func waitForMessage(
        timeout: TimeInterval = 10, where matches: (String) -> Bool
    ) async -> String? {
        var found: String?
        _ = await wait(timeout: timeout) {
            found = messages.first(where: matches)
            return found != nil
        }
        return found
    }

    /// Waits until a connection is open. Returns whether one is.
    func waitForConnection(timeout: TimeInterval = 10) async -> Bool {
        await wait(timeout: timeout) { openConnections > 0 }
    }

    private func accept(_ connection: NWConnection) {
        let accepted = state.withLock { state in
            guard state.accepting else { return false }
            state.connectionCount += 1
            return true
        }
        guard accepted else {
            connection.forceCancel()
            return
        }
        connection.stateUpdateHandler = { [weak self, weak connection] newState in
            guard let self, let connection else { return }
            switch newState {
            case .ready:
                state.withLock { $0.connections.append(connection) }
            case .failed, .cancelled:
                forget(connection)
            default: break
            }
        }
        connection.start(queue: queue)
        // A plain TCP listener reads nothing: it never answers.
        if webSocket { receive(on: connection) }
    }

    private func forget(_ connection: NWConnection) {
        state.withLock { $0.connections.removeAll { $0 === connection } }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }
            if error != nil {
                forget(connection)
                return
            }
            let metadata =
                context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata
            switch metadata?.opcode {
            case .text?:
                let text = String(decoding: content ?? Data(), as: UTF8.self)
                state.withLock { $0.messages.append(text) }
            case .close?:
                if case .protocolCode(.normalClosure)? = metadata?.closeCode {
                    state.withLock { $0.normalCloses += 1 }
                }
                forget(connection)
                connection.cancel()
                return
            default: break
            }
            receive(on: connection)
        }
    }

    private func send(_ data: Data, opcode: NWProtocolWebSocket.Opcode) {
        let connections = state.withLock { $0.connections }
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        for connection in connections {
            connection.send(
                content: data, contentContext: context, isComplete: true,
                completion: .contentProcessed { _ in })
        }
    }
}
