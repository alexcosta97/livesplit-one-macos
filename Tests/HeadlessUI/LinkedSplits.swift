import Foundation
import Testing

/// Splits that link to a layout, made from GameTime.lss, which has no `<LayoutPath>` element.
enum LinkedSplits {
    /// GameTime.lss with `<LayoutPath>layoutPath</LayoutPath>` added, written as `name` in
    /// `folder`.
    static func write(
        linking layoutPath: String, in folder: TemporaryFolder, name: String = "Linked.lss"
    ) throws -> URL {
        var text = try String(contentsOf: Fixtures.url("GameTime.lss"), encoding: .utf8)
        let open = try #require(text.range(of: "<Run version=\"1.6.0\">"))
        text.insert(contentsOf: "<LayoutPath>\(layoutPath)</LayoutPath>", at: open.upperBound)
        try folder.write(name, text)
        return folder.url.appending(path: name)
    }
}
