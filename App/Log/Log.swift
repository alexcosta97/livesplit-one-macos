import Foundation

/// Records what the app does, in the day's log file and the unified log (spec §12).
///
/// Safe to call from any thread: server commands are logged from a background queue (spec
/// §8.2). `@unchecked Sendable` because `lock` guards all mutable state; `Mutex` would need
/// macOS 15.
final class Log: @unchecked Sendable {
    /// The log folder.
    let directory: URL

    private let lock = NSLock()
    /// The log files' writer, or `nil` once writing to them failed.
    private var disk: DiskLog?
    private let unified: any UnifiedLogSink
    private let now: @Sendable () -> Date

    init(
        directory: URL, unified: any UnifiedLogSink = SystemUnifiedLog(),
        calendar: Calendar = .autoupdatingCurrent, cap: Int = DiskLog.dailyCap,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.unified = unified
        self.now = now
        let (disk, errors) = DiskLog.open(
            directory: directory, today: LogDay(now(), in: calendar), calendar: calendar,
            cap: cap)
        self.disk = disk
        for error in errors {
            record(.error, error)
        }
    }

    /// Records a line, stamped with the current time. Never fails: if the file can't be
    /// written, the line still reaches the unified log.
    func record(_ category: LogCategory, _ message: String) {
        lock.withLock {
            // Stamped inside the lock so lines reach the file in time order. Otherwise two
            // threads straddling midnight could write an older line after a newer one, and the
            // writer would reopen yesterday's file.
            let entry = LogEntry(time: now(), category: category, message: message)
            unified.send(entry)
            for error in writeToDisk(entry) {
                let line = LogEntry(time: entry.time, category: .error, message: error)
                unified.send(line)
                // Same day as `entry`, so this write can't rotate and report more errors.
                _ = writeToDisk(line)
            }
        }
    }

    /// Writes `entry` to the file. Returns the errors to record. Called with `lock` held.
    private func writeToDisk(_ entry: LogEntry) -> [String] {
        guard var writer = disk else { return [] }
        do {
            let errors = try writer.write(entry)
            disk = writer
            return errors
        } catch {
            // Sent to the unified log only: writing it to the file would fail too.
            disk = nil
            unified.send(
                LogEntry(
                    time: entry.time, category: .error,
                    message: "Couldn't write the log file, so the log isn't saved to disk "
                        + "until the app restarts: \(error.message)"))
            return []
        }
    }
}
