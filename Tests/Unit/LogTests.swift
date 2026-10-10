import Foundation
import OSLog
import Synchronization
import Testing

@testable import LiveSplitOne

@Suite struct LogTests {
    let calendar = TestCalendar.london

    func makeLog(
        _ directory: URL, unified: RecordingUnifiedLog = RecordingUnifiedLog(),
        now: @escaping @Sendable () -> Date = { TestCalendar.date(2026, 10, 10) }
    ) -> Log {
        Log(directory: directory, unified: unified, calendar: calendar, now: now)
    }

    @Test func linesGoToTheFileAndTheUnifiedLog() throws {
        let folder = try TemporaryFolder()
        let unified = RecordingUnifiedLog()
        let log = makeLog(folder.url, unified: unified)
        log.record(.timer, "Split from the menu")
        #expect(
            try folder.read("livesplit-one-macos-2026-10-10.log")
                == "19:31:01.254  TIMER  Split from the menu\n")
        #expect(unified.entries.map(\.message) == ["Split from the menu"])
        #expect(unified.entries.map(\.category) == [.timer])
    }

    @Test func aFailedWriteIsReportedOnceAndStopsWritingFiles() throws {
        let folder = try TemporaryFolder()
        // A file where the log folder should be, so the folder can't be created.
        try folder.write("logs")
        let unified = RecordingUnifiedLog()
        let log = makeLog(folder.url.appending(path: "logs"), unified: unified)
        log.record(.app, "one")
        log.record(.app, "two")
        let failures = unified.entries.filter { $0.category == .error }
        #expect(failures.count == 1)
        #expect(
            failures.first?.message.hasPrefix(
                "Couldn't write the log file, so the log isn't saved to disk until the app "
                    + "restarts: couldn't open ") == true)
        #expect(unified.entries.filter { $0.category == .app }.map(\.message) == ["one", "two"])
    }

    @Test func oldFilesThatCantBeDeletedAreLoggedAsErrors() throws {
        let folder = try TemporaryFolder()
        // A non-empty folder with an old log file's name can't be removed as a file.
        let old = folder.url.appending(path: "livesplit-one-macos-2026-09-01.log")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: false)
        try "x".write(to: old.appending(path: "inside"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: old.path)
        let unified = RecordingUnifiedLog()
        _ = makeLog(folder.url, unified: unified)
        let errors = unified.entries.filter { $0.category == .error }.map(\.message)
        #expect(errors.count == 1)
        #expect(errors.first?.hasPrefix("Couldn't delete the old log file ") == true)
        #expect(
            try folder.read("livesplit-one-macos-2026-10-10.log").contains(
                "  ERROR  Couldn't delete the old log file "))
        // Writable again, so the folder can be deleted. `folder` is kept alive until then.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: old.path)
        withExtendedLifetime(folder) {}
    }

    @Test func linesFromManyThreadsAreAllWrittenWhole() async throws {
        let folder = try TemporaryFolder()
        let log = makeLog(folder.url)
        await withTaskGroup(of: Void.self) { group in
            for thread in 0..<8 {
                group.addTask {
                    for line in 0..<200 {
                        log.record(.connection, "thread \(thread) line \(line)")
                    }
                }
            }
        }
        let lines = try folder.read("livesplit-one-macos-2026-10-10.log")
            .split(separator: "\n")
        #expect(lines.count == 1600)
        #expect(lines.allSatisfy { $0.hasPrefix("19:31:01.254  CONNECTION  thread ") })
        for thread in 0..<8 {
            #expect(lines.filter { $0.contains("thread \(thread) line ") }.count == 200)
        }
    }

    @Test func midnightStartsTheNextDaysFile() throws {
        let folder = try TemporaryFolder()
        let clock = TestClock(TestCalendar.date(2026, 10, 10, 23, 59, 59))
        let log = makeLog(folder.url, now: { clock.now })
        log.record(.app, "before")
        clock.now = TestCalendar.date(2026, 10, 11, 0, 0, 1)
        log.record(.app, "after")
        #expect(
            try folder.names() == [
                "livesplit-one-macos-2026-10-10.log", "livesplit-one-macos-2026-10-11.log",
            ])
    }

    @Test func linesReachTheSystemUnifiedLog() throws {
        let marker = "unified-log-test-\(UUID().uuidString)"
        SystemUnifiedLog().send(LogEntry(time: Date(), category: .connection, message: marker))
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@", SystemUnifiedLog.subsystem)
        let found = try store.getEntries(matching: predicate)
            .compactMap { $0 as? OSLogEntryLog }
            .first { $0.composedMessage == marker }
        #expect(found?.category == "Connection")
        #expect(found?.level == .notice)
    }
}

/// A clock a test moves by hand.
final class TestClock: Sendable {
    private let time: Mutex<Date>

    init(_ time: Date) { self.time = Mutex(time) }

    var now: Date {
        get { time.withLock { $0 } }
        set { time.withLock { $0 = newValue } }
    }
}
