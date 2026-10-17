import AppKit

/// The splits editor's segment table (spec §9): an icon, the name and the times of each segment,
/// one column per custom comparison, and a header row for each group above its indented
/// segments. Its rows, values and selection come from `SplitsEditing`'s state; every edit and
/// every selection goes to the editor, and the table is redrawn from what the editor then says.
@MainActor
final class SegmentTable: NSObject, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate
{
    /// The table, in `scrollView`.
    let tableView = NSTableView()
    let scrollView = NSScrollView()

    /// Called after the table changed the editor's state, to redraw the window.
    var onChange: () -> Void = {}
    /// Told whether a time entered in a cell was taken, so the window can show or take away
    /// the invalid-time message.
    var onTimeEntered: (_ accepted: Bool) -> Void = { _ in }

    /// The editor, which the window can replace.
    private let editing: () -> SplitsEditing
    private let prompts: SplitsEditorPrompts

    /// The rows' kinds and the comparisons last drawn. While they stay the same, a redraw
    /// changes the cells in place, so a cell being edited keeps its editor (Review Focus 3).
    private struct Shape: Equatable {
        var groupRows: [Bool]
        var comparisons: [String]
    }
    private var drawn: Shape?
    /// Set while `selection(proposed:event:clickedRow:)` changes the editor's selection. The
    /// window's redraw that follows calls `refresh()`, which must not call `selectRowIndexes`
    /// then: the table is in the middle of choosing its selection and sets the one returned.
    /// It doesn't guard against the delegate being asked again: the table doesn't ask about a
    /// selection set in code (see `select(_:)`).
    private var isAnswering = false

    /// A column of the table, named as in the cells' identifiers.
    private enum Column: Equatable {
        case icon, name, split, segment, best
        /// The custom comparison at this index of `comparisonNames`.
        case comparison(Int)

        init?(_ identifier: NSUserInterfaceItemIdentifier) {
            switch identifier.rawValue {
            case "icon": self = .icon
            case "name": self = .name
            case "split": self = .split
            case "segment": self = .segment
            case "best": self = .best
            case let raw where raw.hasPrefix("comparison-"):
                guard let index = Int(raw.dropFirst("comparison-".count)) else { return nil }
                self = .comparison(index)
            default: return nil
            }
        }

        var identifier: String {
            switch self {
            case .icon: "icon"
            case .name: "name"
            case .split: "split"
            case .segment: "segment"
            case .best: "best"
            case .comparison(let index): "comparison-\(index)"
            }
        }
    }

    /// The side of a row's icon, in points.
    private static let iconSide: CGFloat = 24
    /// How far a group's segments' names are indented, in points.
    private static let indent: CGFloat = 16

    init(editing: @escaping () -> SplitsEditing, prompts: SplitsEditorPrompts) {
        self.editing = editing
        self.prompts = prompts
        super.init()
        tableView.setAccessibilityIdentifier("editor-segments")
        tableView.setAccessibilityLabel("Segments")
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = false
        tableView.allowsColumnReordering = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = Self.iconSide + 4
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let fixed: [(Column, String, CGFloat)] = [
            (.icon, "", Self.iconSide + 8), (.name, "Segment Name", 180),
            (.split, "Split Time", 100), (.segment, "Segment Time", 100),
            (.best, "Best Segment", 100),
        ]
        for (column, title, width) in fixed {
            tableView.addTableColumn(Self.makeColumn(column, title: title, width: width))
        }
        let icon = tableView.tableColumns[0]
        icon.headerCell.setAccessibilityLabel("Icon")
        icon.resizingMask = []
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
    }

    private static func makeColumn(_ column: Column, title: String, width: CGFloat)
        -> NSTableColumn
    {
        let tableColumn = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier(column.identifier))
        tableColumn.title = title
        tableColumn.width = width
        tableColumn.minWidth = column == .icon ? width : 60
        return tableColumn
    }

    // MARK: Drawing

    /// Redraws from the editor's state, then selects what it selects. Cells change in place
    /// while the rows' kinds and the comparisons are as last drawn, leaving a field being
    /// edited alone; otherwise the table is reloaded.
    func refresh() {
        let state = editing().state
        let shape = Shape(
            groupRows: state.rows.map {
                if case .group = $0 { return true }
                return false
            }, comparisons: state.comparisonNames)
        if shape == drawn {
            for row in 0..<tableView.numberOfRows {
                for (index, tableColumn) in tableView.tableColumns.enumerated() {
                    guard let column = Column(tableColumn.identifier),
                        let view = tableView.view(atColumn: index, row: row, makeIfNecessary: false)
                    else { continue }
                    configure(view, column, row, state)
                }
            }
        } else {
            if shape.comparisons != drawn?.comparisons {
                buildComparisonColumns(state.comparisonNames, replacing: drawn?.comparisons ?? [])
            }
            drawn = shape
            tableView.reloadData()
        }
        if !isAnswering { select(EditorSelection.selectedRows(state.rows)) }
    }

    /// Makes the comparison columns one per name, in order, keeping the columns, and so the
    /// widths, of comparisons that stay. With as many names as before, a column keeps its
    /// place, so a renamed comparison keeps its column; otherwise columns are matched by name.
    private func buildComparisonColumns(_ names: [String], replacing old: [String]) {
        var columns: [Int: NSTableColumn] = [:]
        for tableColumn in tableView.tableColumns {
            if case .comparison(let index) = Column(tableColumn.identifier) {
                columns[index] = tableColumn
                tableView.removeTableColumn(tableColumn)
            }
        }
        for (index, name) in names.enumerated() {
            let kept =
                names.count == old.count
                ? columns[index] : old.firstIndex(of: name).flatMap { columns[$0] }
            let tableColumn = kept ?? Self.makeColumn(.comparison(index), title: name, width: 100)
            tableColumn.identifier = NSUserInterfaceItemIdentifier(
                Column.comparison(index).identifier)
            tableColumn.title = name
            tableView.addTableColumn(tableColumn)
        }
    }

    /// Shows `rows` selected. The table doesn't ask its delegate about a selection set in code,
    /// so this doesn't go back to the editor.
    private func select(_ rows: IndexSet) {
        guard tableView.selectedRowIndexes != rows else { return }
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        editing().state.rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        guard let tableColumn, let column = Column(tableColumn.identifier) else { return nil }
        let state = editing().state
        guard state.rows.indices.contains(row) else { return nil }
        let view: NSView
        if column == .icon {
            view =
                tableView.makeView(withIdentifier: IconCell.identifier, owner: self)
                ?? makeIconCell()
        } else {
            let cell =
                tableView.makeView(withIdentifier: TextCell.identifier, owner: self) as? TextCell
                ?? makeTextCell()
            // A refused time is red only while it is being edited.
            cell.field.textColor = .controlTextColor
            view = cell
        }
        configure(view, column, row, state)
        return view
    }

    private func makeIconCell() -> IconCell {
        let cell = IconCell(side: Self.iconSide)
        cell.button.onChoose = { [weak self, unowned cell] in self?.chooseIcon(cell) }
        cell.button.onRemove = { [weak self, unowned cell] in self?.removeIcon(cell) }
        return cell
    }

    private func makeTextCell() -> TextCell {
        let cell = TextCell()
        cell.field.delegate = self
        return cell
    }

    /// Shows the state of `row` in `view`, a cell of `column`. A field being edited keeps its
    /// text.
    private func configure(_ view: NSView, _ column: Column, _ row: Int, _ state: RunEditorState) {
        guard state.rows.indices.contains(row) else { return }
        let identifier = "editor-cell-\(column.identifier)-\(row)"
        if let cell = view as? IconCell {
            cell.button.setAccessibilityIdentifier(identifier)
            switch state.rows[row] {
            case .segment(let segment):
                cell.button.icon = editing().image(segment.icon)
                cell.button.canRemove = nil
                cell.button.setAccessibilityLabel("\(segment.name) icon")
            case .group(let group):
                cell.button.icon = editing().image(group.icon)
                cell.button.canRemove = group.hasExplicitIcon
                cell.button.setAccessibilityLabel("\(group.name) icon")
            }
            return
        }
        guard let cell = view as? TextCell else { return }
        let field = cell.field
        field.setAccessibilityIdentifier(identifier)
        guard field.currentEditor() == nil else { return }
        let content = Self.content(column, state.rows[row], state.comparisonNames)
        if field.stringValue != content.text { field.stringValue = content.text }
        field.placeholderString = content.placeholder
        field.isEditable = content.isEditable
        // A group's time cells are blank: no stop for the keyboard or for VoiceOver, whose
        // element is the field's cell.
        field.isSelectable = content.isEditable
        field.cell?.setAccessibilityElement(content.isEditable)
        field.alignment = column == .name ? .natural : .right
        field.font =
            switch (column, state.rows[row]) {
            case (.name, .group): .boldSystemFont(ofSize: NSFont.systemFontSize)
            case (.name, .segment): .systemFont(ofSize: NSFont.systemFontSize)
            default: .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            }
        field.setAccessibilityLabel(content.label)
        if case .segment(let segment) = state.rows[row], column == .name, segment.isIndented {
            cell.indent = Self.indent
        } else {
            cell.indent = 0
        }
    }

    /// What a text cell shows: a group row has its name, with the name it takes from its last
    /// segment as the placeholder, and no times.
    private static func content(
        _ column: Column, _ row: RunEditorState.Row, _ comparisons: [String]
    ) -> (text: String, placeholder: String?, isEditable: Bool, label: String) {
        switch row {
        case .group(let group):
            if column == .name {
                return (group.explicitName ?? "", group.name, true, "Group name")
            }
            return ("", nil, false, "")
        case .segment(let segment):
            let label =
                switch column {
                case .icon, .name: "Segment name"
                case .split: "Split time"
                case .segment: "Segment time"
                case .best: "Best segment"
                case .comparison(let index):
                    comparisons.indices.contains(index)
                        ? comparisons[index] : ""
                }
            return (text(column, segment) ?? "", nil, true, label)
        }
    }

    /// The text a segment shows in `column`.
    private static func text(_ column: Column, _ segment: RunEditorState.Segment) -> String? {
        switch column {
        case .icon: nil
        case .name: segment.name
        case .split: segment.splitTime
        case .segment: segment.segmentTime
        case .best: segment.bestSegmentTime
        case .comparison(let index):
            segment.comparisonTimes.indices.contains(index)
                ? segment.comparisonTimes[index] : nil
        }
    }

    /// The column and row of a cell's view, or nil if it isn't in the table.
    private func position(of view: NSView) -> (column: Column, row: Int)? {
        let row = tableView.row(for: view)
        let index = tableView.column(for: view)
        guard row >= 0, index >= 0, editing().state.rows.indices.contains(row),
            let column = Column(tableView.tableColumns[index].identifier)
        else { return nil }
        return (column, row)
    }

    // MARK: Selection

    /// Which modifier of a click counts: ⌘ before ⇧.
    static func modifier(_ flags: NSEvent.ModifierFlags) -> EditorSelection.Modifier {
        if flags.contains(.command) { return .command }
        if flags.contains(.shift) { return .shift }
        return .none
    }

    func tableView(
        _ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet
    ) -> IndexSet {
        let event = NSApp.currentEvent
        var clicked = -1
        if let event, event.type == .leftMouseDown, event.window === tableView.window {
            clicked = tableView.row(at: tableView.convert(event.locationInWindow, from: nil))
        }
        return selection(proposed: proposed, event: event, clickedRow: clicked)
    }

    /// The selection to show for one the table proposes (spec §9): a left mouse down on a row
    /// is a click on `clickedRow`, with its modifier; anything else (keys, a drag, ⌘A) is the
    /// proposal itself. The editor's selection is changed, and what it then selects returned.
    func selection(proposed: IndexSet, event: NSEvent?, clickedRow: Int) -> IndexSet {
        let rows = editing().state.rows
        let calls: [EditorSelection.Call]
        if let event, event.type == .leftMouseDown, rows.indices.contains(clickedRow) {
            calls = EditorSelection.click(
                row: clickedRow, modifier: Self.modifier(event.modifierFlags), rows: rows)
        } else {
            let last = tableView.selectedRow
            calls = EditorSelection.proposed(
                proposed, current: tableView.selectedRowIndexes,
                lastSelected: last >= 0 ? last : nil, rows: rows)
        }
        if !calls.isEmpty {
            isAnswering = true
            defer { isAnswering = false }
            editing().apply(calls)
            onChange()
        }
        return EditorSelection.selectedRows(editing().state.rows)
    }

    // MARK: Editing

    /// Names are set as editing ends. A time was set when editing was about to end; after a
    /// forced end of a refused one, the state's time shows again.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
            let (column, row) = position(of: field)
        else { return }
        let editing = editing()
        let text = field.stringValue
        switch (column, editing.state.rows[row]) {
        case (.name, .segment(let segment)):
            // Leaving a field unchanged doesn't make its segment the active one.
            guard text != segment.name else { return }
            editing.setName(text, segment: segment.segmentIndex)
        case (.name, .group(let group)):
            guard text != group.explicitName ?? "" else { return }
            editing.renameGroup(group.groupIndex, text)
        case (.icon, _), (.name, _):
            return
        default:
            // The time shows as the editor writes it, now that the field isn't being edited.
            if field.textColor == .systemRed {
                field.textColor = .controlTextColor
                onTimeEntered(true)
            }
        }
        onChange()
    }

    /// A time is checked as editing ends; one the editor refuses turns red and keeps focus.
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        guard let field = control as? NSTextField, let (column, row) = position(of: field),
            column != .icon, column != .name,
            case .segment(let segment) = editing().state.rows[row]
        else { return true }
        let text = field.currentEditor()?.string ?? field.stringValue
        let accepted: Bool
        if text == Self.text(column, segment) {
            // Unchanged: nothing to set, and the segment doesn't become the active one.
            accepted = true
        } else {
            let names = editing().state.comparisonNames
            let time: TimeColumn
            switch column {
            case .split: time = .split
            case .segment: time = .segment
            case .best: time = .best
            case .comparison(let index) where names.indices.contains(index):
                time = .comparison(names[index])
            default: return true
            }
            accepted = editing().setTime(time, text, segment: segment.segmentIndex)
            onChange()
        }
        field.textColor = accepted ? .controlTextColor : .systemRed
        onTimeEntered(accepted)
        return accepted
    }

    // MARK: Icons

    private func chooseIcon(_ cell: NSView) {
        guard let (_, row) = position(of: cell), let url = prompts.chooseImage(),
            editing().state.rows.indices.contains(row)
        else { return }
        let data: Data
        do {
            data = try ImageFile.load(url)
        } catch {
            prompts.showIconFailed(error, file: url.lastPathComponent)
            return
        }
        switch editing().state.rows[row] {
        case .segment(let segment): editing().setSegmentIcon(data, segment: segment.segmentIndex)
        case .group(let group): editing().setGroupIcon(group.groupIndex, data)
        }
        onChange()
    }

    private func removeIcon(_ cell: NSView) {
        guard let (_, row) = position(of: cell) else { return }
        switch editing().state.rows[row] {
        case .segment(let segment): editing().removeSegmentIcon(segment: segment.segmentIndex)
        case .group(let group): editing().removeGroupIcon(group.groupIndex)
        }
        onChange()
    }
}

/// A cell showing a row's icon, which can be chosen or removed (spec §9).
@MainActor
private final class IconCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("editor-icon-cell")
    let button: IconButton

    init(side: CGFloat) {
        button = IconButton(label: "Icon", side: side)
        super.init(frame: .zero)
        identifier = Self.identifier
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IconCell is built in code")
    }
}

/// A cell with an editable text field, which can be indented.
@MainActor
private final class TextCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("editor-text-cell")
    let field = NSTextField()
    private let margin: CGFloat = 2
    private var leading: NSLayoutConstraint!

    /// How far the field is indented, in points.
    var indent: CGFloat {
        get { leading.constant - margin }
        set { leading.constant = margin + newValue }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(field)
        textField = field
        leading = field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin)
        NSLayoutConstraint.activate([
            leading,
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TextCell is built in code")
    }
}
