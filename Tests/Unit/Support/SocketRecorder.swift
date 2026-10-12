import Foundation
import Synchronization

@testable import LiveSplitOne

/// Records what a `WebSocket` reports, from whatever thread it reports on, as lines such as
/// `opened`, `text <message>`, `binary` and `ended <reason>`.
final class SocketRecorder: Sendable {
    private let lines = Mutex<[String]>([])

    var all: [String] { lines.withLock { $0 } }

    var events: WebSocketEvents {
        WebSocketEvents(
            opened: { self.append("opened") },
            received: { message in
                switch message {
                case .text(let text): self.append("text \(text)")
                case .binary: self.append("binary")
                }
            },
            ended: { self.append("ended \($0)") })
    }

    private func append(_ line: String) { lines.withLock { $0.append(line) } }

    /// Waits until a line satisfies `matches`, up to `timeout` seconds. Returns whether one did.
    func wait(timeout: TimeInterval = 10, for matches: @Sendable (String) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !all.contains(where: matches) {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
