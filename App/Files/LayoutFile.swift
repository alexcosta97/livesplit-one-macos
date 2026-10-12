import Foundation
import LiveSplitCore

/// Layout files (spec §7): `.ls1l` and `.lsl` open, and only `.ls1l` is written.
enum LayoutFile {
    /// The layout in `url`: LiveSplit One's JSON, else LiveSplit's XML, whatever the extension.
    static func load(_ url: URL) throws(FileLoadError) -> Layout {
        let data = try FileLoadError.read(url)
        guard !data.isEmpty else { throw .notLayout }
        if let text = String(data: data, encoding: .utf8), let layout = Layout.parseJson(text) {
            return layout
        }
        let layout = data.withUnsafeBytes { bytes in
            Layout.parseOriginalLivesplit(
                UnsafeMutableRawPointer(mutating: bytes.baseAddress), bytes.count)
        }
        guard let layout else { throw .notLayout }
        return layout
    }

    /// The name Save Layout As… suggests: the layout's own name with `.ls1l`, so an `.lsl` is
    /// never overwritten (spec §7).
    static func suggestedName(path: String?) -> String {
        guard let path else { return "Layout.ls1l" }
        return URL(filePath: path).deletingPathExtension().lastPathComponent + ".ls1l"
    }
}
