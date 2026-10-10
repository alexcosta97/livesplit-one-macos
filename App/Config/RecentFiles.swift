/// A recent files list: most recent first, each path once, at most 10 (spec §7, §11).
struct RecentFiles: Codable, Equatable, Sendable {
    static let limit = 10

    private(set) var paths: [String] = []

    /// A list holding `paths` in order, without empty paths or repeats, trimmed to the limit.
    /// A list read from a hand-edited file goes through here too.
    init(_ paths: [String] = []) {
        // Adding from the oldest keeps the order and the first of any repeat.
        for path in paths.reversed() where !path.isEmpty {
            add(path)
        }
    }

    /// Puts `path` first, moving it if it is already in the list.
    mutating func add(_ path: String) {
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > Self.limit {
            paths.removeLast(paths.count - Self.limit)
        }
    }

    mutating func remove(_ path: String) {
        paths.removeAll { $0 == path }
    }

    /// Clear Menu.
    mutating func clear() {
        paths.removeAll()
    }

    init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([String].self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(paths)
    }
}
