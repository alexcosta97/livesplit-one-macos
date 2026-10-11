/// Each Control command's shortcuts (spec §7.2), stored in `app.toml`'s `[shortcuts]` table
/// (§11), which holds only the commands that differ from the defaults.
struct Shortcuts: Codable, Equatable, Sendable {
    static let defaults: [ControlCommand: [Shortcut]] = [
        .startSplit: [Shortcut(key: .named(.space))],
        .reset: [Shortcut(key: .named(.backspace))],
        .undoSplit: [Shortcut(key: .character("u"))],
        .skipSplit: [Shortcut(key: .character("s"))],
        .pause: [Shortcut(key: .character("p"))],
        .undoAllPauses: [],
    ]

    /// The app's own menu shortcuts: Quit, Hide, Hide Others, Minimize, Settings and Close
    /// (spec §7.3). They can't be recorded, and are dropped from the file.
    static let reserved: Set<Shortcut> = [
        Shortcut(key: .character("q"), modifiers: .meta),
        Shortcut(key: .character("h"), modifiers: .meta),
        Shortcut(key: .character("h"), modifiers: [.alt, .meta]),
        Shortcut(key: .character("m"), modifiers: .meta),
        Shortcut(key: .character(","), modifiers: .meta),
        Shortcut(key: .character("w"), modifiers: .meta),
    ]

    /// Why adding a shortcut was refused.
    enum Refusal: Equatable, Sendable {
        case reserved
        case usedBy(ControlCommand)
    }

    /// The commands whose shortcuts differ from the defaults.
    private var changed: [ControlCommand: [Shortcut]] = [:]
    /// A line for each entry reading the file dropped, for the log. Not a setting: not
    /// compared, not saved.
    private(set) var dropped: [String] = []

    init() {}

    var isDefault: Bool { changed.isEmpty }

    func shortcuts(for command: ControlCommand) -> [Shortcut] {
        changed[command] ?? Self.defaults[command] ?? []
    }

    /// The command a shortcut runs, if any.
    func command(for shortcut: Shortcut) -> ControlCommand? {
        ControlCommand.allCases.first { shortcuts(for: $0).contains(shortcut) }
    }

    /// Adds `shortcut` to `command`'s list, unless the app keeps it for its menus or another
    /// command has it. Adding one the command already has changes nothing.
    mutating func add(_ shortcut: Shortcut, to command: ControlCommand) -> Refusal? {
        if Self.reserved.contains(shortcut) { return .reserved }
        if let other = self.command(for: shortcut) {
            return other == command ? nil : .usedBy(other)
        }
        set(shortcuts(for: command) + [shortcut], for: command)
        return nil
    }

    mutating func remove(_ shortcut: Shortcut, from command: ControlCommand) {
        set(shortcuts(for: command).filter { $0 != shortcut }, for: command)
    }

    mutating func restoreDefaults() {
        changed = [:]
    }

    private mutating func set(_ shortcuts: [Shortcut], for command: ControlCommand) {
        changed[command] = shortcuts == Self.defaults[command] ? nil : shortcuts
    }

    static func == (lhs: Shortcuts, rhs: Shortcuts) -> Bool { lhs.changed == rhs.changed }

    /// Reads the table, resolving every command in order (spec §11): an entry that isn't a
    /// shortcut, is reserved, or that an earlier command already has, is dropped into `dropped`.
    /// A list of the wrong type throws, which makes the file unreadable.
    init(from decoder: any Decoder) throws {
        let table = try decoder.singleValueContainer().decode([String: [String]].self)
        var seen: [Shortcut: ControlCommand] = [:]
        for command in ControlCommand.allCases {
            let listed =
                table[command.rawValue]
                ?? (Self.defaults[command] ?? []).map(\.description)
            var kept: [Shortcut] = []
            for text in listed {
                let problem: String?
                if let shortcut = Shortcut(text) {
                    if Self.reserved.contains(shortcut) {
                        problem = "the app keeps it for its menus"
                    } else if let other = seen[shortcut] {
                        problem = "\(other.rawValue) already has it"
                    } else {
                        problem = nil
                        seen[shortcut] = command
                        kept.append(shortcut)
                    }
                } else {
                    problem = "it isn't a shortcut"
                }
                if let problem {
                    dropped.append("\"\(text)\" for \(command.rawValue): \(problem)")
                }
            }
            set(kept, for: command)
        }
    }

    /// Writes only the commands that differ from the defaults, so a later version's new
    /// defaults reach anyone who never changed them.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(
            Dictionary(
                uniqueKeysWithValues: changed.map { ($0.key.rawValue, $0.value.map(\.description)) }
            ))
    }
}
