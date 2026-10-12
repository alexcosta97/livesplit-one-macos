import Foundation

/// What `ServerClient` needs from a WebSocket connection (spec §8). The app's is
/// `URLSessionWebSocket`; unit tests use a fake. Callbacks may come on any thread, one at a
/// time.
protocol WebSocket: AnyObject, Sendable {
    /// Starts connecting. `opened` or `ended` comes first; after `opened`, `received` for each
    /// message in order, then `ended` once. Nothing comes after `close()`.
    func start(events: WebSocketEvents)
    /// Queues a text frame while open. Never blocks.
    func send(_ text: String)
    /// Closes with the normal close code (1000). No callback follows.
    func close()
}

/// What a `WebSocket` reports.
struct WebSocketEvents: Sendable {
    var opened: @Sendable () -> Void
    var received: @Sendable (WebSocketMessage) -> Void
    /// Why it ended, already as the text the user sees (spec §8.1).
    var ended: @Sendable (String) -> Void
}

/// A message from the server.
enum WebSocketMessage: Equatable, Sendable {
    case text(String)
    case binary
}

/// Makes a socket for a URL. Tests pass one that makes fakes.
typealias WebSocketFactory = @Sendable (URL) -> any WebSocket
