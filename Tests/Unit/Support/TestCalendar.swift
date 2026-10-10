import Foundation

/// A fixed calendar and time zone, so tests don't depend on the Mac running them.
enum TestCalendar {
    static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    /// A local time in London.
    static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 19, _ minute: Int = 31,
        _ second: Int = 1, milliseconds: Int = 254
    ) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return london.date(from: components)!
            .addingTimeInterval(Double(milliseconds) / 1000)
    }
}
