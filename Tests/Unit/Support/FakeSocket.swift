import Foundation
import Synchronization

@testable import LiveSplitOne

/// A `WebSocket` the test drives: it records what the client sends and whether it closed, and
/// the test fires its callbacks.
final class FakeSocket: WebSocket, Sendable {
    private struct State {
        var events: WebSocketEvents?
        var sent: [String] = []
        var closed = false
    }

    let url: URL
    private let state = Mutex(State())

    init(url: URL) { self.url = url }

    var sent: [String] { state.withLock { $0.sent } }
    var closed: Bool { state.withLock { $0.closed } }
    var started: Bool { state.withLock { $0.events != nil } }

    func start(events: WebSocketEvents) { state.withLock { $0.events = events } }
    func send(_ text: String) { state.withLock { $0.sent.append(text) } }
    func close() { state.withLock { $0.closed = true } }

    private var events: WebSocketEvents? { state.withLock { $0.events } }

    func open() { events?.opened() }
    func receive(_ message: WebSocketMessage) { events?.received(message) }
    func end(_ reason: String) { events?.ended(reason) }

    /// Waits until `count` messages were sent, up to 10 s. Returns whether they were.
    func waitForSent(_ count: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while sent.count < count {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

/// Makes `FakeSocket`s and keeps them, in the order they were made.
final class FakeSockets: Sendable {
    private let made = Mutex<[FakeSocket]>([])

    var all: [FakeSocket] { made.withLock { $0 } }
    var last: FakeSocket? { all.last }

    var factory: WebSocketFactory {
        { url in
            let socket = FakeSocket(url: url)
            self.made.withLock { $0.append(socket) }
            return socket
        }
    }
}
