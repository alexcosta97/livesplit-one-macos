import Foundation

/// Which server messages are logged (spec §12.1). A bridge can set the game time on every tick,
/// so only the first `setGameTime` of a run is logged; any other command ends the run. The
/// messages are still applied and answered. The same rule as livesplit-asr-bridge's. One per
/// connection.
struct GameTimeLogFilter {
    private var inGameTimeRun = false

    /// Whether to log `message`, a server protocol message, with its reply and its event.
    mutating func shouldLog(_ message: String) -> Bool {
        let isGameTime = Self.command(of: message) == "setGameTime"
        defer { inGameTimeRun = isGameTime }
        return !(isGameTime && inGameTimeRun)
    }

    /// The `command` of a server protocol message, or `nil` if it has none.
    static func command(of message: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(message.utf8)),
            let fields = object as? [String: Any]
        else { return nil }
        return fields["command"] as? String
    }
}
