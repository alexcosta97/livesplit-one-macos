import AppKit

/// The splits editor's contents (spec §9): the game's icon, game, category, start offset,
/// attempts and linked layout at the top, the segment table in the middle, the segment, group
/// and comparison buttons, the Real Time / Game Time switch, a message line, and **Cancel** and
/// **OK**. `SplitsEditing` decides what an input means; this redraws from its state.
@MainActor
final class SplitsEditorViewController: NSViewController, NSTextFieldDelegate {
    /// The smallest size of the contents, in points.
    static let minimumSize = NSSize(width: 640, height: 420)

    /// The editor, replaced by the presenter after an attempt blocked OK.
    var editing: SplitsEditing

    /// The layout the splits link to, as the **Layout:** pop-up shows it. The window keeps it
    /// (spec §9) because the editor's state doesn't include it.
    private(set) var linkedLayout: LinkedLayoutTarget

    private let currentLayout: String?
    private let prompts: SplitsEditorPrompts
    private let ok: () -> Void
    private let cancel: () -> Void

    private let iconButton = IconButton(label: "Game icon")
    private let gameField = NSTextField()
    private let categoryField = NSTextField()
    private let offsetField = NSTextField()
    private let attemptsField = NSTextField()
    private let layoutPopUp = NSPopUpButton()
    /// What each item of `layoutPopUp` links to.
    private var layoutTargets: [LinkedLayoutTarget] = []
    private let timingControl = NSSegmentedControl(
        labels: ["Real Time", "Game Time"], trackingMode: .selectOne, target: nil, action: nil)
    private let messageField = NSTextField(wrappingLabelWithString: "")

    /// What the message line shows: a refused entry's text, which the next good entry takes
    /// away, or another text, which stays until it is replaced.
    private enum Message: Equatable {
        case invalidTime, invalidNumber
        case other(String)

        var text: String {
            switch self {
            case .invalidTime: "Enter a time, such as 1:23.45."
            case .invalidNumber: "Enter a whole number."
            case .other(let text): text
            }
        }
    }
    private var message: Message?

    /// The segment table, in `tableContainer`.
    private(set) lazy var segmentTable = SegmentTable(
        editing: { [unowned self] in editing }, prompts: prompts)
    /// Holds the segment table.
    private let tableContainer = NSView()
    /// The button rows: segments, groups, comparisons. Internal for the test that checks they
    /// fit in the smallest window.
    let buttonRows = NSStackView()

    private let insertAboveButton = NSButton()
    private let insertBelowButton = NSButton()
    private let removeButton = NSButton()
    private let moveUpButton = NSButton()
    private let moveDownButton = NSButton()
    private let createGroupButton = NSButton()
    private let removeGroupButton = NSButton()
    private let addComparisonButton = NSButton()
    private let renameComparisonPopUp = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeComparisonPopUp = NSPopUpButton(frame: .zero, pullsDown: true)
    private let otherPopUp = NSPopUpButton(frame: .zero, pullsDown: true)

    /// `currentLayout` is what the timer window shows (`TimerWindowController.layoutPath`, nil
    /// for the default layout).
    init(
        editing: SplitsEditing, linkedLayout: LinkedLayoutTarget, currentLayout: String?,
        prompts: SplitsEditorPrompts, ok: @escaping () -> Void, cancel: @escaping () -> Void
    ) {
        self.editing = editing
        self.linkedLayout = linkedLayout
        self.currentLayout = currentLayout
        self.prompts = prompts
        self.ok = ok
        self.cancel = cancel
        super.init(nibName: nil, bundle: nil)
        title = "Edit Splits"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SplitsEditorViewController is built in code")
    }

    // MARK: Building

    override func loadView() {
        let root = NSView()
        root.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumSize.width)
            .isActive = true
        root.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumSize.height)
            .isActive = true
        preferredContentSize = NSSize(width: 800, height: 560)

        iconButton.setAccessibilityIdentifier("editor-game-icon")
        iconButton.onChoose = { [weak self] in self?.chooseIcon() }
        iconButton.onRemove = { [weak self] in self?.removeIcon() }

        configure(gameField, "editor-game", "Game")
        configure(categoryField, "editor-category", "Category")
        configure(offsetField, "editor-offset", "Start Offset")
        configure(attemptsField, "editor-attempts", "Attempts")
        for narrow in [offsetField, attemptsField] {
            narrow.widthAnchor.constraint(equalToConstant: 110).isActive = true
        }

        buildLayoutPopUp()
        layoutPopUp.target = self
        layoutPopUp.action = #selector(layoutChosen(_:))
        layoutPopUp.setAccessibilityIdentifier("editor-layout")
        layoutPopUp.setAccessibilityLabel("Layout")

        let grid = NSGridView(views: [
            [label("Game:"), gameField],
            [label("Category:"), categoryField],
            [label("Start Offset:"), offsetField],
            [label("Attempts:"), attemptsField],
            [label("Layout:"), layoutPopUp],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        for row in 0..<2 { grid.cell(atColumnIndex: 1, rowIndex: row).xPlacement = .fill }
        grid.translatesAutoresizingMaskIntoConstraints = false

        tableContainer.translatesAutoresizingMaskIntoConstraints = false
        tableContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        tableContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let tableScroll = segmentTable.scrollView
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableContainer.addSubview(tableScroll)
        NSLayoutConstraint.activate([
            tableScroll.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: tableContainer.topAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor),
        ])
        segmentTable.endEditing = { [weak self] in self?.endFieldEditing() ?? true }
        segmentTable.onChange = { [weak self] in self?.refresh() }
        segmentTable.onCancel = { [weak self] in self?.cancel() }
        segmentTable.onTimeEntered = { [weak self] accepted in
            if accepted { self?.clearInvalid() } else { self?.show(.invalidTime) }
        }

        buildButtonRows()

        timingControl.segmentStyle = .rounded
        timingControl.target = self
        timingControl.action = #selector(timingMethodChosen(_:))
        timingControl.setAccessibilityIdentifier("editor-timing-method")
        timingControl.setAccessibilityLabel("Timing method")
        timingControl.translatesAutoresizingMaskIntoConstraints = false

        messageField.textColor = .systemRed
        messageField.isHidden = true
        messageField.setAccessibilityIdentifier("editor-message")
        messageField.translatesAutoresizingMaskIntoConstraints = false
        messageField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let cancelButton = NSButton(
            title: "Cancel", target: self, action: #selector(cancelPressed(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("editor-cancel")
        let okButton = NSButton(title: "OK", target: self, action: #selector(okPressed(_:)))
        okButton.bezelStyle = .push
        okButton.keyEquivalent = "\r"
        okButton.setAccessibilityIdentifier("editor-ok")
        for button in [cancelButton, okButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
        }

        iconButton.translatesAutoresizingMaskIntoConstraints = false
        for subview in [
            iconButton, grid, tableContainer, buttonRows, timingControl, messageField,
            cancelButton, okButton,
        ] {
            root.addSubview(subview)
        }

        let margin: CGFloat = 20
        let gap: CGFloat = 12
        // The table starts under the header, or under the icon if that is taller; this pins it.
        let tableTop = tableContainer.topAnchor.constraint(
            equalTo: grid.bottomAnchor, constant: gap)
        tableTop.priority = .defaultHigh
        NSLayoutConstraint.activate([
            tableTop,
            iconButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            iconButton.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            grid.leadingAnchor.constraint(equalTo: iconButton.trailingAnchor, constant: gap),
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),

            tableContainer.leadingAnchor.constraint(
                equalTo: root.leadingAnchor, constant: margin),
            tableContainer.trailingAnchor.constraint(
                equalTo: root.trailingAnchor, constant: -margin),
            tableContainer.topAnchor.constraint(
                greaterThanOrEqualTo: grid.bottomAnchor, constant: gap),
            tableContainer.topAnchor.constraint(
                greaterThanOrEqualTo: iconButton.bottomAnchor, constant: gap),
            tableContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),

            buttonRows.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            buttonRows.trailingAnchor.constraint(
                lessThanOrEqualTo: root.trailingAnchor, constant: -margin),
            buttonRows.topAnchor.constraint(equalTo: tableContainer.bottomAnchor, constant: gap),

            timingControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            timingControl.topAnchor.constraint(equalTo: buttonRows.bottomAnchor, constant: gap),

            messageField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            messageField.trailingAnchor.constraint(
                lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -gap),
            messageField.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),

            okButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            okButton.topAnchor.constraint(equalTo: timingControl.bottomAnchor, constant: gap),
            okButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin),
            cancelButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
        ])
        view = root
        refresh()
    }

    /// The buttons (spec §9). Their enabled state comes from `refresh()`.
    private func buildButtonRows() {
        buttonRows.orientation = .vertical
        buttonRows.alignment = .leading
        buttonRows.spacing = 6
        buttonRows.translatesAutoresizingMaskIntoConstraints = false

        let buttons: [(NSButton, String, String, Selector)] = [
            (
                insertAboveButton, "Insert Above", "editor-insert-above",
                #selector(insertAbovePressed(_:))
            ),
            (
                insertBelowButton, "Insert Below", "editor-insert-below",
                #selector(insertBelowPressed(_:))
            ),
            (removeButton, "Remove Segment", "editor-remove", #selector(removeSegmentPressed(_:))),
            (moveUpButton, "Move Up", "editor-move-up", #selector(moveUpPressed(_:))),
            (moveDownButton, "Move Down", "editor-move-down", #selector(moveDownPressed(_:))),
            (
                createGroupButton, "Create Group", "editor-create-group",
                #selector(createGroupPressed(_:))
            ),
            (
                removeGroupButton, "Remove Group", "editor-remove-group",
                #selector(removeGroupPressed(_:))
            ),
            (
                addComparisonButton, "Add Comparison…", "editor-add-comparison",
                #selector(addComparisonPressed(_:))
            ),
        ]
        for (button, title, identifier, action) in buttons {
            button.title = title
            button.bezelStyle = .push
            button.target = self
            button.action = action
            button.setAccessibilityIdentifier(identifier)
        }
        for (popUp, title, identifier) in [
            (renameComparisonPopUp, "Rename Comparison", "editor-rename-comparison"),
            (removeComparisonPopUp, "Remove Comparison", "editor-remove-comparison"),
            (otherPopUp, "Other", "editor-other"),
        ] {
            popUp.addItem(withTitle: title)
            popUp.setAccessibilityIdentifier(identifier)
            popUp.setAccessibilityLabel(title)
        }
        let clearHistory = NSMenuItem(
            title: "Clear History…", action: #selector(clearHistoryPressed(_:)), keyEquivalent: "")
        let clearTimes = NSMenuItem(
            title: "Clear Times…", action: #selector(clearTimesPressed(_:)), keyEquivalent: "")
        for item in [clearHistory, clearTimes] {
            item.target = self
            otherPopUp.menu?.addItem(item)
        }

        let rows: [[NSView]] = [
            [insertAboveButton, insertBelowButton, removeButton, moveUpButton, moveDownButton],
            [createGroupButton, removeGroupButton],
            [addComparisonButton, renameComparisonPopUp, removeComparisonPopUp, otherPopUp],
        ]
        for views in rows {
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.spacing = 8
            // A row keeps the width of its controls; stretched to the widest row, the extra
            // width would be shared between its controls ambiguously.
            row.setHuggingPriority(.required, for: .horizontal)
            buttonRows.addArrangedSubview(row)
        }
    }

    private func configure(_ field: NSTextField, _ identifier: String, _ label: String) {
        field.delegate = self
        field.setAccessibilityIdentifier(identifier)
        field.setAccessibilityLabel(label)
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    /// The pop-up's items (spec §9): **None**, the layout the timer window shows (or **Default
    /// Layout**), and the linked layout when it is another one. A link to the current layout is
    /// that item, not a second.
    private func buildLayoutPopUp() {
        let currentTarget: LinkedLayoutTarget =
            currentLayout.map { .path($0) } ?? .defaultLayout
        var items: [(String, LinkedLayoutTarget)] = [
            ("None", .none),
            (currentLayout.map(Self.fileName) ?? "Default Layout", currentTarget),
        ]
        switch linkedLayout {
        case .none: break
        case .defaultLayout:
            if currentLayout != nil { items.append(("Default Layout", .defaultLayout)) }
        case .path(let path):
            if Self.standardised(path) != currentLayout.map(Self.standardised) {
                items.append((Self.fileName(path), linkedLayout))
            }
        }
        layoutPopUp.removeAllItems()
        for (title, _) in items {
            // `addItem(withTitle:)` merges equal titles; two files can share a name.
            layoutPopUp.menu?.addItem(
                NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        layoutTargets = items.map(\.1)
        selectLayoutItem()
    }

    private func selectLayoutItem() {
        let index =
            layoutTargets.firstIndex { Self.same($0, linkedLayout) }
            ?? 0
        layoutPopUp.selectItem(at: index)
    }

    private static func same(_ a: LinkedLayoutTarget, _ b: LinkedLayoutTarget) -> Bool {
        switch (a, b) {
        case (.path(let x), .path(let y)): standardised(x) == standardised(y)
        default: a == b
        }
    }

    private static func standardised(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func fileName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: Drawing

    /// Shows `text` in the message line, or hides it. A good entry in a field doesn't take it
    /// away.
    func showMessage(_ text: String?) {
        show(text.map { .other($0) })
    }

    private func show(_ message: Message?) {
        self.message = message
        messageField.stringValue = message?.text ?? ""
        messageField.isHidden = message == nil
    }

    /// Redraws everything from `editing.state`, leaving alone a field that is being edited.
    func refresh() {
        guard isViewLoaded else { return }
        let state = editing.state
        iconButton.icon = editing.image(state.icon)
        show(state.game, in: gameField)
        show(state.category, in: categoryField)
        show(state.offset, in: offsetField)
        show(String(state.attempts), in: attemptsField)
        timingControl.selectedSegment = state.timingMethod == .realTime ? 0 : 1
        segmentTable.refresh()
        removeButton.isEnabled = state.buttons.canRemove
        moveUpButton.isEnabled = state.buttons.canMoveUp
        moveDownButton.isEnabled = state.buttons.canMoveDown
        createGroupButton.isEnabled = state.buttons.canCreateSegmentGroup
        removeGroupButton.isEnabled = state.buttons.canRemoveSegmentGroups
        fillComparisons(renameComparisonPopUp, action: #selector(renameComparisonPressed(_:)))
        fillComparisons(removeComparisonPopUp, action: #selector(removeComparisonPressed(_:)))
    }

    /// Rebuilds a pull-down's items after its title item from the comparisons' names; the
    /// pull-down is disabled when there are none.
    private func fillComparisons(_ popUp: NSPopUpButton, action: Selector) {
        guard let menu = popUp.menu else { return }
        let names = editing.state.comparisonNames
        while menu.numberOfItems > 1 { menu.removeItem(at: 1) }
        for name in names {
            let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
            item.representedObject = name
            item.target = self
            menu.addItem(item)
        }
        popUp.isEnabled = !names.isEmpty
    }

    private func show(_ text: String, in field: NSTextField) {
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
    }

    // MARK: Fields

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        // A name left unchanged isn't set: setting it marks the splits changed and drops their
        // speedrun.com run.
        if field === gameField {
            if field.stringValue != editing.state.game { editing.setGame(field.stringValue) }
        } else if field === categoryField {
            if field.stringValue != editing.state.category {
                editing.setCategory(field.stringValue)
            }
        } else if field === offsetField {
            // It was set when editing was about to end; show it as the editor writes it.
            field.stringValue = editing.state.offset
            clearInvalid()
        } else if field === attemptsField {
            field.stringValue = String(editing.state.attempts)
            clearInvalid()
        }
    }

    /// The offset and the attempts are checked as editing ends; a bad one keeps focus.
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        guard let field = control as? NSTextField, field === offsetField || field === attemptsField
        else { return true }
        return endEditing(field, text: field.currentEditor()?.string ?? field.stringValue)
    }

    /// Takes the red and the message of a refused entry away, leaving any other message.
    private func clearInvalid() {
        offsetField.textColor = .controlTextColor
        attemptsField.textColor = .controlTextColor
        if message == .invalidTime || message == .invalidNumber { show(nil) }
    }

    private func endEditing(_ field: NSTextField, text: String) -> Bool {
        let accepted =
            field === offsetField ? editing.setOffset(text) : editing.setAttempts(text)
        if accepted {
            clearInvalid()
        } else {
            field.textColor = .systemRed
            show(field === offsetField ? .invalidTime : .invalidNumber)
        }
        return accepted
    }

    // MARK: Actions

    private func chooseIcon() {
        guard endFieldEditing(), let url = prompts.chooseImage() else { return }
        do {
            editing.setGameIcon(try ImageFile.load(url))
            refresh()
        } catch {
            prompts.showIconFailed(error, file: url.lastPathComponent)
        }
    }

    private func removeIcon() {
        perform { editing.removeGameIcon() }
    }

    @objc private func layoutChosen(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard layoutTargets.indices.contains(index) else { return }
        linkedLayout = layoutTargets[index]
        editing.setLinkedLayout(linkedLayout)
    }

    @objc private func timingMethodChosen(_ sender: NSSegmentedControl) {
        let method: TimingMethod = sender.selectedSegment == 0 ? .realTime : .gameTime
        guard endFieldEditing() else {
            refresh()
            return
        }
        editing.selectTimingMethod(method)
        refresh()
    }

    /// Ends the editing of a field, which applies what was typed (spec §9). `false` means a
    /// field refused its text and keeps focus, so the action must not go on. Segment indexes
    /// are positions, so an action that moved or removed segments must not run before the typed
    /// text has been written to the segment it was typed for.
    private func endFieldEditing() -> Bool {
        guard let window = view.window else { return true }
        return window.makeFirstResponder(nil)
    }

    /// Runs a button's or menu item's action after ending editing, then redraws.
    private func perform(_ action: () -> Void) {
        guard endFieldEditing() else { return }
        action()
        refresh()
    }

    @objc private func insertAbovePressed(_ sender: Any?) { perform { editing.insertAbove() } }
    @objc private func insertBelowPressed(_ sender: Any?) { perform { editing.insertBelow() } }
    @objc private func removeSegmentPressed(_ sender: Any?) { perform { editing.removeSegments() } }
    @objc private func moveUpPressed(_ sender: Any?) { perform { editing.moveUp() } }
    @objc private func moveDownPressed(_ sender: Any?) { perform { editing.moveDown() } }
    @objc private func createGroupPressed(_ sender: Any?) { perform { _ = editing.createGroup() } }
    @objc private func removeGroupPressed(_ sender: Any?) { perform { _ = editing.removeGroups() } }

    @objc private func addComparisonPressed(_ sender: Any?) {
        perform {
            _ = prompts.askName(
                title: "Add Comparison", prefill: "", accept: { editing.addComparison($0) })
        }
    }

    @objc private func renameComparisonPressed(_ sender: NSMenuItem) {
        guard let old = sender.representedObject as? String else { return }
        perform {
            _ = prompts.askName(
                title: "Rename Comparison", prefill: old,
                accept: { editing.renameComparison(old, to: $0) })
        }
    }

    @objc private func removeComparisonPressed(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        perform { editing.removeComparison(name) }
    }

    @objc private func clearHistoryPressed(_ sender: Any?) {
        perform { if prompts.confirm(.clearHistory) { editing.clearHistory() } }
    }

    @objc private func clearTimesPressed(_ sender: Any?) {
        perform { if prompts.confirm(.clearTimes) { editing.clearTimes() } }
    }

    @objc func okPressed(_ sender: Any?) {
        guard endFieldEditing() else { return }
        ok()
    }
    @objc func cancelPressed(_ sender: Any?) { cancel() }
    /// Escape, when the Cancel button's key equivalent didn't take it, is Cancel too (spec §9).
    override func cancelOperation(_ sender: Any?) { cancel() }
}
