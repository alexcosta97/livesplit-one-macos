import AppKit

/// The splits editor's contents (spec §9): the game's icon, game, category, start offset,
/// attempts and linked layout at the top, the segment table in the middle, the Real Time /
/// Game Time switch, a message line, and **Cancel** and **OK**. `SplitsEditing` decides what an
/// input means; this redraws from its state.
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

    /// Where the segment table goes (Task 6 of the plan).
    let tableContainer = NSView()
    /// Where the button rows go (Task 7 of the plan).
    let buttonRows = NSStackView()

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

        // The table (Task 6) fills this.
        tableContainer.translatesAutoresizingMaskIntoConstraints = false
        tableContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        tableContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // The button rows (Task 7) go in this.
        buttonRows.orientation = .vertical
        buttonRows.alignment = .leading
        buttonRows.spacing = 6
        buttonRows.translatesAutoresizingMaskIntoConstraints = false

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
        NSLayoutConstraint.activate([
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
            messageField.topAnchor.constraint(equalTo: timingControl.bottomAnchor, constant: gap),

            okButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            okButton.topAnchor.constraint(equalTo: timingControl.bottomAnchor, constant: gap),
            okButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin),
            cancelButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
        ])
        view = root
        refresh()
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
            ?? layoutTargets.firstIndex { $0 == linkedLayout } ?? 0
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

    /// Shows `text` in the message line, or hides it.
    func showMessage(_ text: String?) {
        messageField.stringValue = text ?? ""
        messageField.isHidden = text == nil
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
    }

    private func show(_ text: String, in field: NSTextField) {
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
    }

    // MARK: Fields

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === gameField {
            editing.setGame(field.stringValue)
        } else if field === categoryField {
            editing.setCategory(field.stringValue)
        } else if field === offsetField {
            // It was set when editing was about to end; show it as the editor writes it.
            field.stringValue = editing.state.offset
        } else if field === attemptsField {
            field.stringValue = String(editing.state.attempts)
        }
    }

    /// The offset and the attempts are checked as editing ends; a bad one keeps focus.
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        guard let field = control as? NSTextField, field === offsetField || field === attemptsField
        else { return true }
        return endEditing(field, text: field.currentEditor()?.string ?? field.stringValue)
    }

    private func endEditing(_ field: NSTextField, text: String) -> Bool {
        guard field === offsetField || field === attemptsField else { return true }
        let accepted =
            field === offsetField ? editing.setOffset(text) : editing.setAttempts(text)
        if accepted {
            offsetField.textColor = .labelColor
            attemptsField.textColor = .labelColor
            showMessage(nil)
        } else {
            field.textColor = .systemRed
            showMessage(
                field === offsetField
                    ? "Enter a time, such as 1:23.45." : "Enter a whole number.")
        }
        return accepted
    }

    // MARK: Actions

    private func chooseIcon() {
        guard let url = prompts.chooseImage() else { return }
        do {
            editing.setGameIcon(try ImageFile.load(url))
            refresh()
        } catch {
            prompts.showIconFailed(error, file: url.lastPathComponent)
        }
    }

    private func removeIcon() {
        editing.removeGameIcon()
        refresh()
    }

    @objc private func layoutChosen(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard layoutTargets.indices.contains(index) else { return }
        linkedLayout = layoutTargets[index]
        editing.setLinkedLayout(linkedLayout)
    }

    @objc private func timingMethodChosen(_ sender: NSSegmentedControl) {
        editing.selectTimingMethod(sender.selectedSegment == 0 ? .realTime : .gameTime)
    }

    @objc func okPressed(_ sender: Any?) { ok() }
    @objc func cancelPressed(_ sender: Any?) { cancel() }
}
