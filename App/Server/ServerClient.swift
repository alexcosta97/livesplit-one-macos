import Foundation
import LiveSplitCore
import Synchronization

/// The connection to a LiveSplit One server (spec §8): connecting, the server's messages run
/// through the app's one sink, every event sent back, the status, the notices and automatic
/// reconnection.
@MainActor
final class ServerClient {
    typealias Schedule = NoticeQueue.Schedule

    private(set) var status: ConnectionStatus = .notConnected {
        didSet { onStatusChange?(status) }
    }
    /// Called after each change of `status`.
    var onStatusChange: ((ConnectionStatus) -> Void)?

    private let notices: @MainActor (String) -> Void
    private let log: Log
    private let makeSocket: WebSocketFactory
    private let schedule: Schedule
    private let wire: Wire
    /// The number of the current connection attempt. Anything from an older one does nothing.
    private var generation = 0
    private var socket: (any WebSocket)?

    /// `notices` shows an overlay notice. `schedule` runs the retries.
    init(
        sink: EventSink, notices: @escaping @MainActor (String) -> Void, log: Log = .shared,
        makeSocket: @escaping WebSocketFactory = { URLSessionWebSocket(url: $0) },
        schedule: @escaping Schedule = NoticeQueue.afterDelay
    ) {
        self.notices = notices
        self.log = log
        self.makeSocket = makeSocket
        self.schedule = schedule
        wire = Wire(sink: sink, log: log)
    }

    /// Connects to `server`, unless already connected or connecting (spec §8.1).
    func connect(to server: ServerURL) {
        guard case .notConnected = status else { return }
        log.record(.connection, "Connecting to \(server.url.absoluteString)")
        status = .connecting(server)
        startSocket(server)
    }

    /// Closes the connection with the normal close code and stops any retry (spec §8.3).
    func disconnect() {
        guard let server = status.server else { return }
        generation += 1
        wire.begin(nil, generation: generation)
        socket?.close()
        socket = nil
        status = .notConnected
        log.record(.connection, "Disconnected from \(server.host)")
    }

    /// Sends `event` to the server while connected; drops it otherwise (spec §8.2). Called with
    /// every event the sink reports, on the command's thread (`CommandRunner.observeEvents`):
    /// it never waits.
    nonisolated func send(_ event: TimerEvent) {
        wire.send(event)
    }

    private func startSocket(_ server: ServerURL) {
        generation += 1
        let generation = generation
        let socket = makeSocket(server.url)
        self.socket = socket
        wire.begin(socket, generation: generation)
        let wire = wire
        // The socket reports one callback at a time, and the main queue keeps their order.
        socket.start(
            events: WebSocketEvents(
                opened: { [weak self] in
                    guard wire.open(generation) else { return }
                    Self.onMain { self?.opened(generation) }
                },
                received: { wire.receive($0, generation: generation) },
                ended: { [weak self] reason in
                    wire.end(generation)
                    Self.onMain { self?.ended(generation, reason: reason) }
                }))
    }

    private nonisolated static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }

    private func opened(_ generation: Int) {
        guard generation == self.generation, let server = status.server else { return }
        status = .connected(server)
        notices("Connected to \(server.host)")
        log.record(.connection, "Connected to \(server.host)")
    }

    private func ended(_ generation: Int, reason: String) {
        guard generation == self.generation else { return }
        socket = nil
        switch status {
        case .notConnected:
            break
        case .connecting(let server):
            // A failed first attempt doesn't retry: the URL may be wrong (spec §8.3).
            status = .notConnected
            notices("Couldn't connect to \(server.host): \(reason)")
            log.record(.error, "Couldn't connect to \(server.host): \(reason)")
        case .connected(let server):
            log.record(.connection, "Lost connection to \(server.host): \(reason)")
            notices("Lost connection to \(server.host), retrying…")
            status = .retrying(server, attempt: 0)
            scheduleRetry()
        case .retrying(let server, let attempt):
            log.record(.connection, "Retry failed: \(reason)")
            status = .retrying(server, attempt: attempt + 1)
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard case .retrying(let server, let attempt) = status else { return }
        let seconds = ReconnectDelays.seconds(beforeRetry: attempt)
        log.record(.connection, "Retrying \(server.host) in \(seconds) s")
        let generation = generation
        schedule(TimeInterval(seconds)) { [weak self] in
            guard let self, generation == self.generation,
                case .retrying(let server, _) = status
            else { return }
            startSocket(server)
        }
    }
}

/// What the server's queue and the commands' threads share with the client: the open socket,
/// the server's messages and the events sent back. Never waits on the main actor.
private final class Wire: Sendable {
    /// The `InvalidCommand` reply LiveSplit One gives a binary message (spec §8.2).
    static let invalidCommand = #"{"Err":{"code":"InvalidCommand"}}"#

    private struct Current {
        var generation = 0
        var socket: (any WebSocket)?
        var open = false
    }

    /// What only the server's queue uses: the log filter, and whether the message being run
    /// is logged, which also decides for the events it causes (spec §12.1).
    private struct Messages {
        var filter = GameTimeLogFilter()
        var quiet = false
    }

    private let sink: EventSink
    private let log: Log
    /// Runs the server's messages one at a time, never on `CommandRunner`'s queue (spec §8.2).
    private let queue = DispatchQueue(label: "dev.alexcosta.livesplit-one-macos.server")
    private let onQueue = DispatchSpecificKey<Bool>()
    private let current = Mutex(Current())
    private let messages = Mutex(Messages())

    init(sink: EventSink, log: Log) {
        self.sink = sink
        self.log = log
        queue.setSpecific(key: onQueue, value: true)
    }

    /// A new attempt, or none (`socket` nil): what is sent from now on goes to it, once open.
    func begin(_ socket: (any WebSocket)?, generation: Int) {
        current.withLock { $0 = Current(generation: generation, socket: socket) }
    }

    /// Marks attempt `generation` open. Returns whether it is still the current one. A new
    /// connection gets a new log filter (spec §12.1).
    func open(_ generation: Int) -> Bool {
        let isCurrent = current.withLock { current in
            guard current.generation == generation, current.socket != nil else { return false }
            current.open = true
            return true
        }
        if isCurrent { messages.withLock { $0.filter = GameTimeLogFilter() } }
        return isCurrent
    }

    /// Attempt `generation` ended: nothing is sent to it any more.
    func end(_ generation: Int) {
        current.withLock { current in
            guard current.generation == generation else { return }
            current.open = false
            current.socket = nil
        }
    }

    /// The socket to send to for attempt `generation`, if it is still current and open.
    private func openSocket(for generation: Int?) -> (any WebSocket)? {
        current.withLock { current in
            guard current.open, generation == nil || current.generation == generation
            else { return nil }
            return current.socket
        }
    }

    /// Runs a message from the server on the server's queue, in order, and sends the reply
    /// unless the connection it came from has gone (spec §8.2).
    func receive(_ message: WebSocketMessage, generation: Int) {
        queue.async { [self] in
            guard openSocket(for: generation) != nil else { return }
            let reply: String
            switch message {
            case .text(let text):
                let logged = messages.withLock { messages in
                    let logged = messages.filter.shouldLog(text)
                    messages.quiet = !logged
                    return logged
                }
                // Events this causes are sent from `report`, before the reply.
                reply = sink.handleCommand(text)
                messages.withLock { $0.quiet = false }
                if logged { log.record(.connection, "Received \(text), replied \(reply)") }
            case .binary:
                reply = Self.invalidCommand
                log.record(.connection, "Received a binary message, replied \(reply)")
            }
            openSocket(for: generation)?.send(reply)
        }
    }

    /// Sends `event` to the open connection, if any. On any thread; never waits.
    func send(_ event: TimerEvent) {
        guard let socket = openSocket(for: nil) else { return }
        let json = EventSink.encodeEvent(event)
        // An event from a message that isn't logged isn't either. Only the server's queue runs
        // messages, so an event reported on another thread is from the menus or the keyboard.
        let quiet =
            DispatchQueue.getSpecific(key: onQueue) == true && messages.withLock { $0.quiet }
        if !quiet { log.record(.connection, "Sent \(json)") }
        socket.send(json)
    }
}
