import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct LogDayTests {
    let calendar = TestCalendar.london

    @Test func aDayIsTheLocalDate() {
        // 23:30 on the 10th in London is already the 11th in Paris.
        let late = TestCalendar.date(2026, 10, 10, 23, 30)
        #expect(LogDay(late, in: calendar) == LogDay(year: 2026, month: 10, day: 10))
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        #expect(LogDay(late, in: paris) == LogDay(year: 2026, month: 10, day: 11))
    }

    @Test func daysAreCountedAcrossMonths() {
        let start = LogDay(year: 2026, month: 9, day: 28)
        #expect(start.days(until: LogDay(year: 2026, month: 10, day: 5), in: calendar) == 7)
    }

    @Test func aDaylightSavingChangeDoesNotShiftTheCount() {
        // Clocks go back on 2026-10-25 in London: that day has 25 hours.
        let start = LogDay(year: 2026, month: 10, day: 20)
        #expect(start.days(until: LogDay(year: 2026, month: 10, day: 27), in: calendar) == 7)
        let spring = LogDay(year: 2026, month: 3, day: 26)
        #expect(spring.days(until: LogDay(year: 2026, month: 4, day: 2), in: calendar) == 7)
    }

    @Test func daysAreOrdered() {
        #expect(LogDay(year: 2026, month: 9, day: 30) < LogDay(year: 2026, month: 10, day: 1))
        #expect(LogDay(year: 2025, month: 12, day: 31) < LogDay(year: 2026, month: 1, day: 1))
    }

    @Test func filesAreNamedByDay() {
        let day = LogDay(year: 2026, month: 9, day: 7)
        #expect(LogFileName.of(day) == "livesplit-one-macos-2026-09-07.log")
        #expect(LogFileName.day(of: "livesplit-one-macos-2026-09-07.log") == day)
    }

    @Test func otherFilesAreNotLogFiles() {
        #expect(LogFileName.day(of: "livesplit-one-macos-2026-09-07.txt") == nil)
        #expect(LogFileName.day(of: "livesplit-one-macos-latest.log") == nil)
        #expect(LogFileName.day(of: "livesplit-asr-bridge-2026-09-07.log") == nil)
        #expect(LogFileName.day(of: "livesplit-one-macos-2026-13-07.log") == nil)
        #expect(LogFileName.day(of: "livesplit-one-macos-2026-02-30.log") == nil)
        #expect(LogFileName.day(of: "livesplit-one-macos-26-09-07.log") == nil)
        #expect(LogFileName.day(of: "notes.txt") == nil)
    }
}
