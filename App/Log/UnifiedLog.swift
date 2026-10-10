import os

/// Where every line also goes, besides the log file (spec §12.3).
///
/// `Log` calls `send` with its lock held, so a sink must never call `Log`.
protocol UnifiedLogSink: Sendable {
    func send(_ entry: LogEntry)
}

/// The system's unified log, so lines show in Console.app's live stream next to system messages
/// such as local network permission decisions.
struct SystemUnifiedLog: UnifiedLogSink {
    static let subsystem = "dev.alexcosta.livesplit-one-macos"

    private let loggers: [LogCategory: Logger]

    init() {
        var loggers: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            loggers[category] = Logger(subsystem: Self.subsystem, category: category.unifiedName)
        }
        self.loggers = loggers
    }

    func send(_ entry: LogEntry) {
        guard let logger = loggers[entry.category] else { return }
        // Public, or Console.app shows <private> instead of the message. The messages hold
        // file paths and server addresses, nothing secret (spec §13).
        if entry.category == .error {
            logger.error("\(entry.message, privacy: .public)")
        } else {
            // Not .info: Console.app hides info and debug messages by default.
            logger.notice("\(entry.message, privacy: .public)")
        }
    }
}
