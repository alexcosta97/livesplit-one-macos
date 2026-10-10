import Foundation

/// A day in the user's calendar, which names a log file.
struct LogDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`.
    init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// A day written as `YYYY-MM-DD`, or `nil` if `text` isn't a real date in that form.
    init?(text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: Calendar(identifier: .gregorian)) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// `YYYY-MM-DD`.
    var text: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Whole days from this day to `later`; negative if `later` is earlier. Returns 0 if the
    /// calendar can't build the dates. That is deliberate: retention reads it as "not older
    /// than the limit" and keeps the file.
    func days(until later: LogDay, in calendar: Calendar) -> Int {
        // At noon, so a 23- or 25-hour day never changes the count.
        guard let start = calendar.date(from: noon), let end = calendar.date(from: later.noon)
        else { return 0 }
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func < (lhs: LogDay, rhs: LogDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private var noon: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: 12)
    }
}

/// The names of the log files: `livesplit-one-macos-YYYY-MM-DD.log` (spec §12.2).
enum LogFileName {
    static let prefix = "livesplit-one-macos-"
    static let suffix = ".log"

    /// The name of the file for `day`.
    static func of(_ day: LogDay) -> String { prefix + day.text + suffix }

    /// The day a log file is for, from its name, or `nil` if it isn't a log file.
    static func day(of name: String) -> LogDay? {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix),
            name.count > prefix.count + suffix.count
        else { return nil }
        return LogDay(text: String(name.dropFirst(prefix.count).dropLast(suffix.count)))
    }
}
