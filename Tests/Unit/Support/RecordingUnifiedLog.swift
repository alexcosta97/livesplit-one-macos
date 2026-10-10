import Foundation
import Synchronization

@testable import LiveSplitOne

/// A unified log that keeps what it is sent, for tests.
final class RecordingUnifiedLog: UnifiedLogSink, Sendable {
    private let sent = Mutex<[LogEntry]>([])

    var entries: [LogEntry] { sent.withLock { $0 } }

    func send(_ entry: LogEntry) {
        sent.withLock { $0.append(entry) }
    }
}
