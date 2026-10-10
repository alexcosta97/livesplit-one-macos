import Foundation

/// One logged line.
struct LogEntry: Equatable, Sendable {
    /// When it was recorded.
    var time: Date
    var category: LogCategory
    var message: String

    /// The line as written to the log file: local time to the millisecond, tag and message, with
    /// a newline.
    func line(in calendar: Calendar) -> String {
        // Rounded once, so the milliseconds and the seconds always agree.
        let milliseconds = Int64((time.timeIntervalSince1970 * 1000).rounded())
        let second = Date(timeIntervalSince1970: TimeInterval(milliseconds / 1000))
        let parts = calendar.dateComponents([.hour, .minute, .second], from: second)
        let clock = String(
            format: "%02d:%02d:%02d.%03d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
            Int(milliseconds % 1000))
        return "\(clock)  \(category.tag)  \(message)\n"
    }
}
