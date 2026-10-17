import Foundation

/// Turns what the table proposes into `RunEditor`'s selection calls (spec §9), so the table's
/// selection is always the editor's.
enum EditorSelection {
    /// One `RunEditor` selection call. Segment calls take segment indexes, group calls take
    /// group indexes; neither is a row number.
    enum Call: Equatable {
        case only(Int)
        case additionally(Int)
        case unselect(Int)
        case range(Int)
        case group(Int)
        case toggleGroup(Int)
        case groupRange(Int)
    }

    enum Modifier { case none, command, shift }

    /// A click on `row` (a presentation row) with `modifier`.
    static func click(row: Int, modifier: Modifier, rows: [RunEditorState.Row]) -> [Call] {
        precondition(rows.indices.contains(row), "Row \(row) is not one of \(rows.count) rows")
        switch rows[row] {
        case .segment(let segment):
            let index = segment.segmentIndex
            switch modifier {
            case .none: return [.only(index)]
            case .command:
                return [segment.selected == .notSelected ? .additionally(index) : .unselect(index)]
            case .shift: return [.range(index)]
            }
        case .group(let group):
            switch modifier {
            case .none: return [.group(group.groupIndex)]
            case .command: return [.toggleGroup(group.groupIndex)]
            case .shift: return [.groupRange(group.groupIndex)]
            }
        }
    }

    /// A selection the table proposes with no click (arrow keys, ⇧-arrows, ⌘A): `proposed` and
    /// `current` are row indexes, and `lastSelected` is the table's last-selected row for the
    /// proposal. Group rows in a proposal stand for their segments. When the selection is
    /// rebuilt, the segment of `lastSelected` (a group's last segment) is applied last, so it
    /// is the active one; without it, or if it isn't in the proposal, the highest segment is.
    static func proposed(
        _ proposed: IndexSet, current: IndexSet, lastSelected: Int?, rows: [RunEditorState.Row]
    ) -> [Call] {
        if proposed == current { return [] }
        if proposed.count == 1, let row = proposed.first {
            return click(row: row, modifier: .none, rows: rows)
        }
        // One row added next to the current selection extends it, as ⇧-arrow does.
        let added = proposed.subtracting(current)
        if added.count == 1, let row = added.first, let first = current.first,
            let last = current.last,
            current.isSubset(of: proposed), row == first - 1 || row == last + 1
        {
            return click(row: row, modifier: .shift, rows: rows)
        }
        // Anything else is rebuilt, with the active segment last.
        var segments = segmentIndexes(of: proposed, rows: rows)
        if let lastSelected, proposed.contains(lastSelected),
            let active = segmentIndexes(of: [lastSelected], rows: rows).last
        {
            segments.removeAll { $0 == active }
            segments.append(active)
        }
        guard let first = segments.first else { return [] }
        return [.only(first)] + segments.dropFirst().map { .additionally($0) }
    }

    /// The calls that select again, in a new editor of the same run, the segments `rows` shows
    /// selected, with the active one last so it stays active. Nothing if none is selected.
    static func restoring(_ rows: [RunEditorState.Row]) -> [Call] {
        var segments: [Int] = []
        var active: Int?
        for case .segment(let segment) in rows {
            switch segment.selected {
            case .selected: segments.append(segment.segmentIndex)
            case .active: active = segment.segmentIndex
            case .notSelected: break
            }
        }
        if let active { segments.append(active) }
        guard let first = segments.first else { return [] }
        return [.only(first)] + segments.dropFirst().map { .additionally($0) }
    }

    /// The rows the state shows selected: segments `.selected` or `.active`, groups `selected`.
    static func selectedRows(_ rows: [RunEditorState.Row]) -> IndexSet {
        var selected = IndexSet()
        for (row, value) in rows.enumerated() {
            switch value {
            case .segment(let segment) where segment.selected != .notSelected: selected.insert(row)
            case .group(let group) where group.selected: selected.insert(row)
            default: break
            }
        }
        return selected
    }

    /// The segment indexes of the rows, in row order, once each: a segment row's own, and for
    /// a group row the segments after it that are indented.
    private static func segmentIndexes(of selection: IndexSet, rows: [RunEditorState.Row])
        -> [Int]
    {
        var indexes: [Int] = []
        for row in selection {
            precondition(rows.indices.contains(row), "Row \(row) is not one of \(rows.count) rows")
            switch rows[row] {
            case .segment(let segment):
                if !indexes.contains(segment.segmentIndex) { indexes.append(segment.segmentIndex) }
            case .group:
                // Membership is `isIndented`, which livesplit-core's state supplies (a segment
                // is indented exactly when it's in a group), so nothing is inferred here.
                for case .segment(let member) in rows[(row + 1)...].prefix(while: {
                    if case .segment(let segment) = $0 { return segment.isIndented }
                    return false
                }) where !indexes.contains(member.segmentIndex) {
                    indexes.append(member.segmentIndex)
                }
            }
        }
        return indexes.sorted()
    }
}
