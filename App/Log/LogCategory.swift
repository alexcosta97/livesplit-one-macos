/// What a logged line is about (spec §12.1).
enum LogCategory: CaseIterable, Sendable {
    /// File load and save failures, connection failures, unexpected states.
    case error
    /// Connecting, connected, disconnected, retries, each command received and its reply, each
    /// event sent.
    case connection
    /// Timer actions and their source (menu, keyboard, server), run and layout changes.
    case timer
    /// Launch, version, settings read and written, files opened and saved.
    case app

    /// The tag in front of the line in the log files, as in livesplit-asr-bridge.
    var tag: String {
        switch self {
        case .error: "ERROR"
        case .connection: "CONNECTION"
        case .timer: "TIMER"
        case .app: "APP"
        }
    }

    /// The category in the unified log, as Console.app shows it (spec §12.3).
    var unifiedName: String {
        switch self {
        case .error: "Errors"
        case .connection: "Connection"
        case .timer: "Timer"
        case .app: "App"
        }
    }
}
