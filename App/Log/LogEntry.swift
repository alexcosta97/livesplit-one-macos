import Foundation

/// One logged line.
struct LogEntry: Equatable, Sendable {
    /// When it was recorded.
    var time: Date
    var category: LogCategory
    var message: String

    /// The line as written to the log file: local time to the millisecond, tag and message, with
    /// a newline. The message is escaped (`escaped(_:)`), so the line stays one line.
    func line(in calendar: Calendar) -> String {
        // Rounded once, so the milliseconds and the seconds always agree.
        let milliseconds = Int64((time.timeIntervalSince1970 * 1000).rounded())
        let second = Date(timeIntervalSince1970: TimeInterval(milliseconds / 1000))
        let parts = calendar.dateComponents([.hour, .minute, .second], from: second)
        let clock = String(
            format: "%02d:%02d:%02d.%03d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
            Int(milliseconds % 1000))
        return "\(clock)  \(category.tag)  \(escapedMessage)\n"
    }

    /// The message as every sink gets it, the file and the unified log alike.
    var escapedMessage: String { Self.escaped(message) }

    /// `message` on one line, safe for a log, in this one place for every message. A path from a
    /// splits file, `app.toml` or a script can't be trusted, and macOS's reasons name the file:
    /// `\` is written as `\\`, a line feed as `\n`, a carriage return as `\r` and a tab as
    /// `\t`, and any other control character, and U+2028 and U+2029, as `\u{hex}`. So a message
    /// can't be read as several entries or forge an escape (spec §12.2).
    static func escaped(_ message: String) -> String {
        var result = ""
        for scalar in message.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                switch scalar.properties.generalCategory {
                case .control, .lineSeparator, .paragraphSeparator:
                    result += "\\u{" + String(scalar.value, radix: 16) + "}"
                default:
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
