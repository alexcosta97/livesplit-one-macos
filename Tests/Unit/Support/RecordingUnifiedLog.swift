import Foundation

@testable import LiveSplitOne

/// A unified log that keeps what it is sent, for tests.
final class RecordingUnifiedLog: UnifiedLogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [LogEntry] = []

    var entries: [LogEntry] { lock.withLock { sent } }

    func send(_ entry: LogEntry) {
        lock.withLock { sent.append(entry) }
    }
}
