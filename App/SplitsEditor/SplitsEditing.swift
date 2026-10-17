import AppKit
import LiveSplitCore

/// A column of times in the splits editor (spec §9).
enum TimeColumn: Equatable {
    case split
    case segment
    case best
    case comparison(String)
}

/// The run being edited (spec §9): the only code that calls `RunEditor`. Every change goes to
/// the editor, then `state` is read again.
@MainActor
final class SplitsEditing {
    private let editor: RunEditor
    private let imageCache = ImageCache()
    private let lang: UInt8
    private var finished = false
    private(set) var state: RunEditorState

    /// Starts editing `run`, which has segments. Times and offsets parse with `lang`.
    init(run: Run, lang: UInt8 = TimerContent.systemLanguage) {
        // A run with no segments is refused when it's opened.
        editor = RunEditor(run)!
        self.lang = lang
        state = Self.read(editor, imageCache, lang)
    }

    private static func read(_ editor: RunEditor, _ cache: ImageCache, _ lang: UInt8)
        -> RunEditorState
    {
        let json = editor.stateAsJson(cache, lang)
        cache.collect()
        // The JSON is livesplit-core's own, so failing to decode it is a bug here.
        return try! RunEditorState.decode(json)
    }

    private func refresh() {
        state = Self.read(editor, imageCache, lang)
    }

    /// The icon for an image id, or nil for the empty image or data that isn't an image.
    func image(_ id: String) -> NSImage? {
        let length = imageCache.lookupDataLen(id)
        guard length > 0, let pointer = imageCache.lookupDataPtr(id) else { return nil }
        return NSImage(data: Data(bytes: pointer, count: length))
    }

    /// The edited run. The editor can't be used after.
    func finish() -> Run {
        precondition(!finished, "The run was already finished")
        finished = true
        return editor.close()
    }

    // MARK: Run

    func setGame(_ name: String) {
        editor.setGameName(name)
        refresh()
    }

    func setCategory(_ name: String) {
        editor.setCategoryName(name)
        refresh()
    }

    /// `false` if `text` isn't a time.
    func setOffset(_ text: String) -> Bool {
        let parsed = editor.parseAndSetOffset(text, lang)
        refresh()
        return parsed
    }

    /// `false` if `text` isn't a number of attempts.
    func setAttempts(_ text: String) -> Bool {
        let parsed = editor.parseAndSetAttemptCount(text)
        refresh()
        return parsed
    }

    func setGameIcon(_ data: Data) {
        data.withUnsafeBytes {
            editor.setGameIcon(UnsafeMutableRawPointer(mutating: $0.baseAddress), $0.count)
        }
        refresh()
    }

    func removeGameIcon() {
        editor.removeGameIcon()
        refresh()
    }

    func setLinkedLayout(_ link: LinkedLayoutTarget) {
        switch link {
        case .none: editor.removeLinkedLayout()
        case .defaultLayout: editor.setLinkedLayout(LinkedLayout(""))
        case .path(let path): editor.setLinkedLayout(LinkedLayout(path))
        }
        refresh()
    }

    func selectTimingMethod(_ method: TimingMethod) {
        editor.selectTimingMethod(method.rawValue)
        refresh()
    }

    // MARK: Segments

    func insertAbove() { change { $0.insertSegmentAbove() } }
    func insertBelow() { change { $0.insertSegmentBelow() } }
    func removeSegments() { change { $0.removeSegments() } }
    func moveUp() { change { $0.moveSegmentsUp() } }
    func moveDown() { change { $0.moveSegmentsDown() } }

    private func change(_ edit: (RunEditor) -> Void) {
        edit(editor)
        refresh()
    }

    // MARK: Groups

    /// Groups the selected segments, unnamed, so the group takes its last segment's name.
    /// `false` if they aren't next to each other, or overlap a group.
    func createGroup() -> Bool {
        let created = editor.createSegmentGroupFromSelection("")
        refresh()
        return created
    }

    /// Removes the selected groups, keeping their segments. `false` if the selection isn't
    /// whole groups.
    func removeGroups() -> Bool {
        let removed = editor.removeSelectedSegmentGroups()
        refresh()
        return removed
    }

    /// An empty name gives the group its last segment's name.
    func renameGroup(_ index: Int, _ name: String) {
        // The group calls here and below return false only for an index with no group, and the indexes come
        // from `state`, so the results are dropped.
        _ = editor.renameSegmentGroup(index, name)
        refresh()
    }

    func setGroupIcon(_ index: Int, _ data: Data) {
        data.withUnsafeBytes {
            _ = editor.setSegmentGroupIcon(
                index, UnsafeMutableRawPointer(mutating: $0.baseAddress), $0.count)
        }
        refresh()
    }

    func removeGroupIcon(_ index: Int) {
        _ = editor.removeSegmentGroupIcon(index)
        refresh()
    }

    // MARK: Fields of one segment

    /// Makes `segment` the active one, keeping the rest of the selection, for the call after.
    private func activate(_ segment: Int) {
        let isActive = state.rows.contains {
            if case .segment(let row) = $0 {
                return row.segmentIndex == segment && row.selected == .active
            }
            return false
        }
        if !isActive { editor.selectAdditionally(segment) }
    }

    func setName(_ name: String, segment: Int) {
        activate(segment)
        editor.activeSetName(name)
        refresh()
    }

    /// `false` if `text` isn't a time. An empty one clears the time. `segment` becomes the
    /// active one even when the text doesn't parse, as editing a cell does in LiveSplit One.
    func setTime(_ column: TimeColumn, _ text: String, segment: Int) -> Bool {
        activate(segment)
        let parsed =
            switch column {
            case .split: editor.activeParseAndSetSplitTime(text, lang)
            case .segment: editor.activeParseAndSetSegmentTime(text, lang)
            case .best: editor.activeParseAndSetBestSegmentTime(text, lang)
            case .comparison(let name): editor.activeParseAndSetComparisonTime(name, text, lang)
            }
        refresh()
        return parsed
    }

    func setSegmentIcon(_ data: Data, segment: Int) {
        activate(segment)
        data.withUnsafeBytes {
            editor.activeSetIcon(UnsafeMutableRawPointer(mutating: $0.baseAddress), $0.count)
        }
        refresh()
    }

    func removeSegmentIcon(segment: Int) {
        activate(segment)
        editor.activeRemoveIcon()
        refresh()
    }

    // MARK: Comparisons

    /// `false` if the name is taken or reserved.
    func addComparison(_ name: String) -> Bool {
        let added = editor.addComparison(name)
        refresh()
        return added
    }

    /// `false` if `new` is taken or reserved.
    func renameComparison(_ old: String, to new: String) -> Bool {
        let renamed = editor.renameComparison(old, new)
        refresh()
        return renamed
    }

    func removeComparison(_ name: String) {
        editor.removeComparison(name)
        refresh()
    }

    func clearHistory() { change { $0.clearHistory() } }
    func clearTimes() { change { $0.clearTimes() } }
}
