import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct DiskLogTests {
    let calendar = TestCalendar.london

    func day(_ day: Int, month: Int = 9) -> LogDay { LogDay(year: 2026, month: month, day: day) }

    func entry(_ day: Int, _ category: LogCategory, _ message: String, month: Int = 9) -> LogEntry {
        LogEntry(time: TestCalendar.date(2026, month, day), category: category, message: message)
    }

    func name(_ day: Int, month: Int = 9) -> String { LogFileName.of(self.day(day, month: month)) }

    @Test func everyCategoryIsWritten() throws {
        let folder = try TemporaryFolder()
        var (log, _) = DiskLog.open(directory: folder.url, today: day(27), calendar: calendar)
        for category in LogCategory.allCases {
            _ = try log.write(entry(27, category, "x"))
        }
        #expect(
            try folder.read(name(27))
                == "19:31:01.254  ERROR  x\n19:31:01.254  CONNECTION  x\n"
                + "19:31:01.254  TIMER  x\n19:31:01.254  APP  x\n")
    }

    @Test func aNewDayStartsANewFile() throws {
        let folder = try TemporaryFolder()
        var (log, _) = DiskLog.open(directory: folder.url, today: day(26), calendar: calendar)
        _ = try log.write(entry(26, .app, "first"))
        _ = try log.write(entry(27, .app, "second"))
        #expect(try folder.names() == [name(26), name(27)])
        #expect(try folder.read(name(26)) == "19:31:01.254  APP  first\n")
        #expect(try folder.read(name(27)) == "19:31:01.254  APP  second\n")
    }

    @Test func aRelaunchAddsToTheDaysFile() throws {
        let folder = try TemporaryFolder()
        for message in ["before", "after"] {
            var (log, _) = DiskLog.open(directory: folder.url, today: day(27), calendar: calendar)
            _ = try log.write(entry(27, .app, message))
        }
        #expect(
            try folder.read(name(27)) == "19:31:01.254  APP  before\n19:31:01.254  APP  after\n")
    }

    @Test func filesOlderThan7DaysAreDeletedAtLaunch() throws {
        let folder = try TemporaryFolder()
        for dayOfMonth in [27, 26, 20, 19, 7] {
            try folder.write(name(dayOfMonth))
        }
        try folder.write("notes.txt")
        let (_, errors) = DiskLog.open(directory: folder.url, today: day(27), calendar: calendar)
        #expect(errors.isEmpty)
        #expect(try folder.names() == [name(20), name(26), name(27), "notes.txt"])
    }

    @Test func filesOlderThan7DaysAreDeletedAtEachRotation() throws {
        let folder = try TemporaryFolder()
        try folder.write(name(19))
        var (log, _) = DiskLog.open(directory: folder.url, today: day(26), calendar: calendar)
        _ = try log.write(entry(26, .app, "x"))
        // Seven days old on the 26th: kept.
        #expect(try folder.names().contains(name(19)))
        let errors = try log.write(entry(27, .app, "x"))
        #expect(errors.isEmpty)
        #expect(try !folder.names().contains(name(19)))
    }

    @Test func aRotationThatCantOpenTheNewFileThrowsAndDeletesNothing() throws {
        let folder = try TemporaryFolder()
        try folder.write(name(19))
        // A folder with the new day's file name can't be opened as a file.
        try FileManager.default.createDirectory(
            at: folder.url.appending(path: name(27)), withIntermediateDirectories: false)
        var (log, _) = DiskLog.open(directory: folder.url, today: day(26), calendar: calendar)
        _ = try log.write(entry(26, .app, "x"))
        #expect(throws: DiskLogError.self) { try log.write(entry(27, .app, "x")) }
        #expect(try folder.names().contains(name(19)))
    }

    @Test func retentionCountsDaysAcrossADaylightSavingChange() throws {
        // Clocks go back in London on 2026-10-25.
        let folder = try TemporaryFolder()
        try folder.write(name(20, month: 10))
        try folder.write(name(19, month: 10))
        _ = DiskLog.open(directory: folder.url, today: day(27, month: 10), calendar: calendar)
        #expect(try folder.names() == [name(20, month: 10)])
    }

    @Test func aMissingFolderIsCreatedOnTheFirstLine() throws {
        let folder = try TemporaryFolder()
        let logs = folder.url.appending(path: "Library/Logs/livesplit-one-macos")
        var (log, errors) = DiskLog.open(directory: logs, today: day(27), calendar: calendar)
        #expect(errors.isEmpty)
        _ = try log.write(entry(27, .app, "x"))
        let text = try String(contentsOf: logs.appending(path: name(27)), encoding: .utf8)
        #expect(text == "19:31:01.254  APP  x\n")
    }

    @Test func aFolderThatCantBeCreatedFailsTheWrite() throws {
        let folder = try TemporaryFolder()
        // A file where the log folder should be.
        try folder.write("logs")
        var (log, errors) = DiskLog.open(
            directory: folder.url.appending(path: "logs"), today: day(27), calendar: calendar)
        #expect(errors.isEmpty)
        #expect(throws: DiskLogError.self) { try log.write(entry(27, .app, "x")) }
    }

    @Test func pastTheCapOnlyErrorsAreWrittenAfterOneLineSayingSo() throws {
        let folder = try TemporaryFolder()
        // Each line is 25 bytes: the second line reaches the cap.
        var (log, _) = DiskLog.open(
            directory: folder.url, today: day(27), calendar: calendar, cap: 50)
        _ = try log.write(entry(27, .app, "one  "))
        _ = try log.write(entry(27, .app, "two  "))
        _ = try log.write(entry(27, .app, "dropped"))
        _ = try log.write(entry(27, .error, "kept"))
        _ = try log.write(entry(27, .connection, "dropped"))
        _ = try log.write(entry(27, .error, "kept too"))
        #expect(
            try folder.read(name(27))
                == "19:31:01.254  APP  one  \n19:31:01.254  APP  two  \n"
                + "19:31:01.254  APP  \(DiskLog.capMessage)\n19:31:01.254  ERROR  kept\n"
                + "19:31:01.254  ERROR  kept too\n")
    }

    @Test func theCapHoldsAfterARelaunch() throws {
        let folder = try TemporaryFolder()
        for _ in 0..<2 {
            var (log, _) = DiskLog.open(
                directory: folder.url, today: day(27), calendar: calendar, cap: 50)
            for message in ["one  ", "two  ", "dropped"] {
                _ = try log.write(entry(27, .app, message))
            }
        }
        let text = try folder.read(name(27))
        #expect(text.components(separatedBy: DiskLog.capMessage).count == 2)
        #expect(!text.contains("dropped"))
    }

    @Test func theCapIsPerDay() throws {
        let folder = try TemporaryFolder()
        var (log, _) = DiskLog.open(
            directory: folder.url, today: day(26), calendar: calendar, cap: 50)
        for message in ["one  ", "two  ", "dropped"] {
            _ = try log.write(entry(26, .app, message))
        }
        _ = try log.write(entry(27, .app, "written"))
        #expect(try folder.read(name(27)) == "19:31:01.254  APP  written\n")
    }

    @Test func theRealCapIs50MB() {
        #expect(DiskLog.dailyCap == 50 * 1024 * 1024)
        #expect(DiskLog.capMessage.contains("50 MB"))
        #expect(DiskLog.retentionDays == 7)
    }
}
