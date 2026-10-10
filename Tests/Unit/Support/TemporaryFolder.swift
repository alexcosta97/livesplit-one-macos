import Foundation

/// A new empty folder, deleted with everything in it when this goes away.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "lso-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// The names of the files in the folder, sorted.
    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    /// The text of the file `name` in the folder.
    func read(_ name: String) throws -> String {
        try String(contentsOf: url.appending(path: name), encoding: .utf8)
    }

    /// Creates the file `name` in the folder with `text`.
    func write(_ name: String, _ text: String = "") throws {
        try text.write(to: url.appending(path: name), atomically: true, encoding: .utf8)
    }
}
