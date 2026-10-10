import Foundation
import Synchronization

/// Records what the app does, in the day's log file and the unified log (spec §12).
///
/// Safe to call from any thread: server commands are logged from a background queue (spec
/// §8.2). `disk`, the only mutable state, is behind a `Mutex`.
final class Log: Sendable {
    /// The log folder.
    let directory: URL

    /// The app's log, in `LogFolder.current`.
    static let shared = Log(directory: LogFolder.current)

    /// The calendar that names the log files and stamps their lines: Gregorian, whatever
    /// calendar System Settings uses, because file names are `YYYY-MM-DD` in Gregorian years
    /// (spec §12.2), in the user's time zone.
    static func defaultCalendar(in timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The log files' writer, or `nil` once writing to them failed.
    private let disk: Mutex<DiskLog?>
    private let unified: any UnifiedLogSink
    private let now: @Sendable () -> Date

    init(
        directory: URL, unified: any UnifiedLogSink = SystemUnifiedLog(),
        calendar: Calendar = Log.defaultCalendar(), cap: Int = DiskLog.dailyCap,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.unified = unified
        self.now = now
        let (disk, errors) = DiskLog.open(
            directory: directory, today: LogDay(now(), in: calendar), calendar: calendar,
            cap: cap)
        self.disk = Mutex(disk)
        for error in errors {
            record(.error, error)
        }
    }

    /// Records a line, stamped with the current time. Never fails: if the file can't be
    /// written, the line still reaches the unified log.
    func record(_ category: LogCategory, _ message: String) {
        disk.withLock { disk in
            // Stamped inside the lock so lines reach the file in time order. Otherwise two
            // threads straddling midnight could write an older line after a newer one, and the
            // writer would reopen yesterday's file.
            let entry = LogEntry(time: now(), category: category, message: message)
            unified.send(entry)
            for error in writeToDisk(entry, to: &disk) {
                let line = LogEntry(time: entry.time, category: .error, message: error)
                unified.send(line)
                // Same day as `entry`, so this write can't rotate and report more errors.
                _ = writeToDisk(line, to: &disk)
            }
        }
    }

    /// Writes `entry` to the file. Returns the errors to record. Called with the lock held,
    /// with `disk` the value inside it.
    private func writeToDisk(_ entry: LogEntry, to disk: inout DiskLog?) -> [String] {
        guard var writer = disk else { return [] }
        do {
            let errors = try writer.write(entry)
            disk = writer
            return errors
        } catch {
            // Sent to the unified log only: writing it to the file would fail too.
            disk = nil
            // Reported even though the write failed: nothing else will.
            for message in error.deletionErrors {
                unified.send(LogEntry(time: entry.time, category: .error, message: message))
            }
            unified.send(
                LogEntry(
                    time: entry.time, category: .error,
                    message: "Couldn't write the log file, so the log isn't saved to disk "
                        + "until the app restarts: \(error.message)"))
            return []
        }
    }
}
