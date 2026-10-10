import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct LogEntryTests {
    @Test func aLineIsTimeTagAndMessage() {
        let entry = LogEntry(
            time: TestCalendar.date(2026, 10, 10), category: .connection,
            message: "Connected to 192.168.1.20")
        #expect(
            entry.line(in: TestCalendar.london)
                == "19:31:01.254  CONNECTION  Connected to 192.168.1.20\n")
    }

    @Test func everyCategoryHasItsTag() {
        #expect(LogCategory.allCases.map(\.tag) == ["ERROR", "CONNECTION", "TIMER", "APP"])
    }

    @Test func everyCategoryHasItsUnifiedLogName() {
        #expect(
            LogCategory.allCases.map(\.unifiedName) == ["Errors", "Connection", "Timer", "App"])
    }

    @Test func millisecondsRoundToTheNearest() {
        let calendar = TestCalendar.london
        let almost = TestCalendar.date(2026, 10, 10, 19, 31, 1, milliseconds: 999)
            .addingTimeInterval(0.0006)
        let line = LogEntry(time: almost, category: .app, message: "x").line(in: calendar)
        #expect(line == "19:31:02.000  APP  x\n")
    }

    @Test func theTimeIsLocal() {
        // 19:31 in London is 20:31 in Paris.
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let line = LogEntry(time: TestCalendar.date(2026, 10, 10), category: .app, message: "x")
            .line(in: paris)
        #expect(line == "20:31:01.254  APP  x\n")
    }
}
