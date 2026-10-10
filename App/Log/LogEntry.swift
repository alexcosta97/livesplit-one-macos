import Foundation

/// One logged line.
struct LogEntry: Equatable, Sendable {
    /// When it was recorded.
    var time: Date
    var category: LogCategory
    var message: String

    /// The line as written to the log file: local time to the millisecond, tag and message, with
    /// a newline. Line breaks in the message are escaped, so the line stays one line.
    func line(in calendar: Calendar) -> String {
        // Rounded once, so the milliseconds and the seconds always agree.
        let milliseconds = Int64((time.timeIntervalSince1970 * 1000).rounded())
        let second = Date(timeIntervalSince1970: TimeInterval(milliseconds / 1000))
        let parts = calendar.dateComponents([.hour, .minute, .second], from: second)
        let clock = String(
            format: "%02d:%02d:%02d.%03d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
            Int(milliseconds % 1000))
        return "\(clock)  \(category.tag)  \(Self.escaped(message))\n"
    }

    /// `message` on one line: `\` is written as `\\`, a line feed as `\n` and a carriage
    /// return as `\r`, so a message can't be read as several entries.
    private static func escaped(_ message: String) -> String {
        var result = ""
        for character in message.unicodeScalars {
            switch character {
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            default: result.unicodeScalars.append(character)
            }
        }
        return result
    }
}
