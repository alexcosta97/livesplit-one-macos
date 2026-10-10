import Foundation

/// Why a line couldn't be written to the log file.
struct DiskLogError: Error, Equatable {
    let message: String
}

/// The log files: one per day, kept for 7 days, with a per-day size cap (spec §12.2). A port of
/// livesplit-asr-bridge's `src/logging/disk.rs`.
///
/// Every category is written. Past the cap, only errors are written, after one line saying the
/// cap was reached. Not thread-safe: `Log` serialises every call.
struct DiskLog {
    /// Files more than this many days older than today are deleted.
    static let retentionDays = 7
    /// The size past which only errors are written to a day's file: 50 MB.
    static let dailyCap = 50 * 1024 * 1024
    /// The line written once when a day's file reaches the cap.
    static let capMessage =
        "Today's log reached 50 MB, so only errors are written to it until tomorrow"

    let directory: URL
    private let calendar: Calendar
    private let cap: Int
    private var file: DayFile?

    private init(directory: URL, calendar: Calendar, cap: Int) {
        self.directory = directory
        self.calendar = calendar
        self.cap = cap
    }

    /// A writer for the log folder `directory`, after deleting the files that are too old on
    /// `today`. Returns what couldn't be deleted.
    static func open(
        directory: URL, today: LogDay, calendar: Calendar, cap: Int = dailyCap
    ) -> (DiskLog, [String]) {
        let log = DiskLog(directory: directory, calendar: calendar, cap: cap)
        return (log, log.deleteOld(today: today))
    }

    /// Writes `entry` to its day's file, starting a new file when the day changes and then
    /// deleting the files that are too old. Returns what couldn't be deleted. Throws if the line
    /// couldn't be written.
    mutating func write(_ entry: LogEntry) throws(DiskLogError) -> [String] {
        let day = LogDay(entry.time, in: calendar)
        var errors: [String] = []
        if file?.day != day {
            let rotating = file != nil
            file = nil
            if rotating {
                errors = deleteOld(today: day)
            }
            file = try DayFile.open(directory: directory, day: day, cap: cap)
        }
        guard let file else { return errors }

        if file.size >= cap && entry.category != .error {
            if !file.capped {
                var marker = entry
                marker.category = .app
                marker.message = Self.capMessage
                try file.append(marker.line(in: calendar))
                file.capped = true
            }
            return errors
        }
        try file.append(entry.line(in: calendar))
        return errors
    }

    /// Deletes the log files more than `retentionDays` older than `today`. Other files in the
    /// folder are left alone. Returns what couldn't be deleted.
    private func deleteOld(today: LogDay) -> [String] {
        // A missing folder, or a file where the folder should be, has nothing to delete. The
        // write reports the real problem.
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isFolder),
            isFolder.boolValue
        else { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            return [
                "Couldn't delete old log files in \(directory.path): \(error.localizedDescription)"
            ]
        }
        var errors: [String] = []
        for name in names {
            guard let day = LogFileName.day(of: name),
                day.days(until: today, in: calendar) > Self.retentionDays
            else { continue }
            let path = directory.appending(path: name)
            do {
                try FileManager.default.removeItem(at: path)
            } catch {
                errors.append(
                    "Couldn't delete the old log file \(path.path): \(error.localizedDescription)")
            }
        }
        return errors
    }
}

/// The open file of one day.
private final class DayFile {
    let day: LogDay
    private let handle: FileHandle
    private(set) var size: Int
    /// Whether the cap was reached and the line saying so written.
    var capped: Bool

    private init(day: LogDay, handle: FileHandle, size: Int, capped: Bool) {
        self.day = day
        self.handle = handle
        self.size = size
        self.capped = capped
    }

    deinit {
        try? handle.close()
    }

    /// Opens the file of `day` in `directory` to add to it, creating the folder and the file if
    /// needed.
    static func open(directory: URL, day: LogDay, cap: Int) throws(DiskLogError) -> DayFile {
        let url = directory.appending(path: LogFileName.of(day))
        func failure(_ reason: String) -> DiskLogError {
            DiskLogError(message: "couldn't open \(url.path): \(reason)")
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        } catch {
            throw failure(error.localizedDescription)
        }
        // O_APPEND: every write goes to the end, even with another copy of the app writing.
        let descriptor = Darwin.open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw failure(String(cString: strerror(errno))) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        let size: Int
        let capped: Bool
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            // The line saying the cap was reached is always after the cap, so only that part
            // of the file needs reading.
            if size >= cap {
                let reader = try FileHandle(forReadingFrom: url)
                defer { try? reader.close() }
                try reader.seek(toOffset: UInt64(cap))
                let rest = try reader.readToEnd() ?? Data()
                capped = String(decoding: rest, as: UTF8.self).contains(DiskLog.capMessage)
            } else {
                capped = false
            }
        } catch {
            throw failure(error.localizedDescription)
        }
        return DayFile(day: day, handle: handle, size: size, capped: capped)
    }

    func append(_ line: String) throws(DiskLogError) {
        let data = Data(line.utf8)
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw DiskLogError(
                message: "couldn't write the log file: \(error.localizedDescription)")
        }
        size += data.count
    }
}
