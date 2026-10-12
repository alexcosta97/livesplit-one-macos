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

    /// The app's own menu shortcuts: Quit, Hide, Hide Others, Minimize, Settings, Close,
    /// Save Splits and Save Splits As (spec §7.3). They can't be recorded, and are dropped from
    /// the file.
    static let reserved: Set<Shortcut> = [
        Shortcut(key: .character("q"), modifiers: .meta),
        Shortcut(key: .character("h"), modifiers: .meta),
        Shortcut(key: .character("h"), modifiers: [.alt, .meta]),
        Shortcut(key: .character("m"), modifiers: .meta),
        Shortcut(key: .character(","), modifiers: .meta),
        Shortcut(key: .character("w"), modifiers: .meta),
        Shortcut(key: .character("s"), modifiers: .meta),
        Shortcut(key: .character("s"), modifiers: [.shift, .meta]),
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

    /// A key in the `[shortcuts]` table, which may not be a command.
    private struct CommandKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Reads the table, resolving every command in order (spec §11): an entry that isn't a
    /// shortcut, is reserved, or that an earlier command already has, is dropped into `dropped`.
    /// A command's list of the wrong type throws, which makes the file unreadable. A key that
    /// isn't a command is noted in `dropped` too, whatever its type, and otherwise ignored.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CommandKey.self)
        var table: [String: [String]] = [:]
        for command in ControlCommand.allCases {
            let key = CommandKey(stringValue: command.rawValue)!
            if let listed = try container.decodeIfPresent([String].self, forKey: key) {
                table[command.rawValue] = listed
            }
        }
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
        // Sorted, since the table's order isn't kept.
        let commandNames = Set(ControlCommand.allCases.map(\.rawValue))
        for key in container.allKeys.map(\.stringValue).sorted()
        where !commandNames.contains(key) {
            dropped.append("\"\(key)\": not a command")
        }
    }

    /// Writes only the commands that differ from the defaults, so a later version's new
    /// defaults reach anyone who never changed them.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CommandKey.self)
        for (command, shortcuts) in changed {
            try container.encode(
                shortcuts.map(\.description), forKey: CommandKey(stringValue: command.rawValue)!)
        }
    }
}
