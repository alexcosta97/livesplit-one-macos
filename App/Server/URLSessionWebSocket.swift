import Foundation
import Synchronization

/// A WebSocket connection with `URLSessionWebSocketTask` (spec §8.1), with no `Origin` header,
/// its own handshake timeout, and a ping to notice a server that vanished (spec §8.2).
final class URLSessionWebSocket: NSObject, WebSocket, URLSessionWebSocketDelegate, Sendable {
    static let timeoutReason = "The server didn't answer within 10 seconds."
    static let localNetworkReason =
        "LiveSplit One for macOS needs local network access. Allow it in System Settings › "
        + "Privacy & Security › Local Network."
    static let closedReason = "The server closed the connection."
    static let stoppedAnsweringReason = "The server stopped answering."

    private enum Phase { case idle, opening, open, ended }

    private struct State {
        var phase = Phase.idle
        var session: URLSession?
        var task: URLSessionWebSocketTask?
        var events: WebSocketEvents?
        /// The number of the ping waiting for its pong, if any.
        var waitingPing: Int?
        var pings = 0
    }

    private let url: URL
    private let handshakeTimeout: TimeInterval
    private let pingInterval: TimeInterval
    private let pongTimeout: TimeInterval
    /// Runs the session's delegate calls and the timers, one at a time.
    private let queue = DispatchQueue(label: "dev.alexcosta.livesplit-one-macos.websocket")
    private let state = Mutex(State())

    init(
        url: URL, handshakeTimeout: TimeInterval = 10, pingInterval: TimeInterval = 10,
        pongTimeout: TimeInterval = 10
    ) {
        self.url = url
        self.handshakeTimeout = handshakeTimeout
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
    }

    /// The text the user sees for an error (spec §8.1).
    static func reason(for error: any Error) -> String {
        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorNotConnectedToInternet: return localNetworkReason
            case NSURLErrorTimedOut: return timeoutReason
            default: break
            }
        }
        return error.localizedDescription
    }

    func start(events: WebSocketEvents) {
        let configuration = URLSessionConfiguration.ephemeral
        // The handshake has its own timeout below. On a WebSocket task this one can also end a
        // connection that is idle, which the ping already watches.
        configuration.timeoutIntervalForRequest = 86_400
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = queue
        // The session holds its delegate, this socket, until it is invalidated when it ends.
        let session = URLSession(
            configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        let task = session.webSocketTask(with: url)
        let started = state.withLock { state in
            guard state.phase == .idle else { return false }
            state.phase = .opening
            state.session = session
            state.task = task
            state.events = events
            return true
        }
        guard started else {
            session.invalidateAndCancel()
            return
        }
        task.resume()
        queue.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self] in
            guard let self, state.withLock({ $0.phase == .opening }) else { return }
            end(Self.timeoutReason)
        }
    }

    func send(_ text: String) {
        guard let task = state.withLock({ $0.phase == .open ? $0.task : nil }) else { return }
        // A failed send also fails the receive loop, which reports the end.
        task.send(.string(text)) { _ in }
    }

    func close() {
        let (task, session) = state.withLock { state in
            defer {
                state.phase = .ended
                state.events = nil
            }
            return state.phase == .ended ? (nil, nil) : (state.task, state.session)
        }
        task?.cancel(with: .normalClosure, reason: nil)
        // Lets the close frame go out before the session goes.
        session?.finishTasksAndInvalidate()
    }

    /// Ends the connection and reports `reason`, unless it already ended or was closed.
    private func end(_ reason: String) {
        let (events, task, session) = state.withLock { state in
            defer {
                state.phase = .ended
                state.events = nil
            }
            return state.phase == .ended
                ? (nil, nil, nil) : (state.events, state.task, state.session)
        }
        guard let events else { return }
        task?.cancel()
        session?.invalidateAndCancel()
        events.ended(reason)
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let received: WebSocketMessage =
                    switch message {
                    case .string(let text): .text(text)
                    case .data: .binary
                    @unknown default: .binary
                    }
                guard let events = state.withLock({ $0.phase == .open ? $0.events : nil })
                else { return }
                events.received(received)
                receive(task)
            case .failure(let error):
                end(task.closeCode == .invalid ? Self.reason(for: error) : Self.closedReason)
            }
        }
    }

    /// Sends a ping `pingInterval` from now; no pong within `pongTimeout` ends the connection.
    private func schedulePing(_ task: URLSessionWebSocketTask) {
        queue.asyncAfter(deadline: .now() + pingInterval) { [weak self] in
            guard let self else { return }
            let number: Int? = state.withLock { state in
                guard state.phase == .open else { return nil }
                state.pings += 1
                state.waitingPing = state.pings
                return state.pings
            }
            guard let number else { return }
            task.sendPing { [weak self] error in
                guard let self else { return }
                if let error {
                    end(Self.reason(for: error))
                    return
                }
                let answered = state.withLock { state in
                    guard state.waitingPing == number, state.phase == .open else { return false }
                    state.waitingPing = nil
                    return true
                }
                if answered { schedulePing(task) }
            }
            queue.asyncAfter(deadline: .now() + pongTimeout) { [weak self] in
                guard let self, state.withLock({ $0.waitingPing == number }) else { return }
                end(Self.stoppedAnsweringReason)
            }
        }
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        let events: WebSocketEvents? = state.withLock { state in
            guard state.phase == .opening else { return nil }
            state.phase = .open
            return state.events
        }
        guard let events else { return }
        events.opened()
        receive(webSocketTask)
        schedulePing(webSocketTask)
    }

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
    ) {
        end(Self.closedReason)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        end(error.map(Self.reason(for:)) ?? Self.closedReason)
    }
}
