import Foundation
import TOML

/// Everything the app remembers between launches, stored in `app.toml` (spec §11). The splits
/// and layouts themselves stay wherever the user keeps them; only their paths are stored.
struct Settings: Codable, Equatable, Sendable {
    var lastSplitsPath: String?
    var lastLayoutPath: String?
    var recentSplits = RecentFiles()
    var recentLayouts = RecentFiles()
    /// The window's frame for each layout, by the layout's path (spec §6).
    var windows: [LayoutWindow] = []
    var alwaysOnTop = false
    /// The last URL used in Connect to Server (spec §8.1).
    var lastServerURL: String?

    /// The defaults, used when there is no file.
    init() {}

    /// The frame saved for the layout at `path`, if any.
    func frame(forLayout path: String) -> WindowFrame? {
        windows.first { $0.layout == path }?.frame
    }

    /// Saves `frame` for the layout at `path`, replacing any frame saved for it.
    mutating func setFrame(_ frame: WindowFrame, forLayout path: String) {
        if let index = windows.firstIndex(where: { $0.layout == path }) {
            windows[index].frame = frame
        } else {
            windows.append(LayoutWindow(layout: path, frame: frame))
        }
    }

    /// Settings read from the text of `app.toml`. Throws if it isn't TOML, or a key has the
    /// wrong type.
    static func decode(_ data: Data) throws -> Settings {
        try TOMLDecoder().decode(Settings.self, from: data)
    }

    /// The settings as TOML, keys sorted so the file doesn't reorder between saves.
    func tomlText() throws -> String {
        let encoder = TOMLEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encodeToString(self)
    }

    /// Why reading or writing failed, for the log. swift-toml's errors name the line and column.
    static func reason(for error: any Error) -> String {
        switch error {
        case let error as TOMLDecodingError: error.description
        case let error as TOMLEncodingError: error.description
        default: error.localizedDescription
        }
    }

    // Explicit keys, never a key strategy: a strategy could rewrite them, and the file's keys
    // are part of the spec (§11).
    private enum CodingKeys: String, CodingKey {
        case lastSplitsPath = "last_splits"
        case lastLayoutPath = "last_layout"
        case recentSplits = "recent_splits"
        case recentLayouts = "recent_layouts"
        case windows
        case alwaysOnTop = "always_on_top"
        case lastServerURL = "last_server_url"
    }

    /// Every key is optional, so a file from an older version, or edited by hand, still reads.
    /// Unknown keys are ignored. A key with the wrong type throws.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSplitsPath = try container.decodeIfPresent(String.self, forKey: .lastSplitsPath)
        lastLayoutPath = try container.decodeIfPresent(String.self, forKey: .lastLayoutPath)
        recentSplits =
            try container.decodeIfPresent(RecentFiles.self, forKey: .recentSplits) ?? RecentFiles()
        recentLayouts =
            try container.decodeIfPresent(RecentFiles.self, forKey: .recentLayouts)
            ?? RecentFiles()
        windows = try container.decodeIfPresent([LayoutWindow].self, forKey: .windows) ?? []
        alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        lastServerURL = try container.decodeIfPresent(String.self, forKey: .lastServerURL)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastSplitsPath, forKey: .lastSplitsPath)
        try container.encodeIfPresent(lastLayoutPath, forKey: .lastLayoutPath)
        try container.encode(recentSplits, forKey: .recentSplits)
        try container.encode(recentLayouts, forKey: .recentLayouts)
        try container.encode(windows, forKey: .windows)
        try container.encode(alwaysOnTop, forKey: .alwaysOnTop)
        try container.encodeIfPresent(lastServerURL, forKey: .lastServerURL)
    }
}

/// A window's position and size, in screen points, as AppKit gives them (origin at the bottom
/// left of the main screen).
struct WindowFrame: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// Whether the frame can be given to a window: finite, with a positive size. A
    /// hand-edited file can hold anything. Whether it is on a screen is for the window to decide.
    var isUsable: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
}

/// The frame saved for one layout. Written flat, as one table of `windows`.
struct LayoutWindow: Codable, Equatable, Sendable {
    var layout: String
    var frame: WindowFrame

    private enum CodingKeys: String, CodingKey {
        case layout, x, y, width, height
    }

    init(layout: String, frame: WindowFrame) {
        self.layout = layout
        self.frame = frame
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try container.decode(String.self, forKey: .layout)
        frame = WindowFrame(
            x: try container.decode(Double.self, forKey: .x),
            y: try container.decode(Double.self, forKey: .y),
            width: try container.decode(Double.self, forKey: .width),
            height: try container.decode(Double.self, forKey: .height))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(layout, forKey: .layout)
        try container.encode(frame.x, forKey: .x)
        try container.encode(frame.y, forKey: .y)
        try container.encode(frame.width, forKey: .width)
        try container.encode(frame.height, forKey: .height)
    }
}
