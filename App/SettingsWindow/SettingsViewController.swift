import AppKit

/// The Settings window's contents (spec §7.3): what a reset with new best times does, and each
/// Control command's shortcuts. Every change is saved at once, then `onChange` runs, so the
/// menus and the command queue follow it.
@MainActor
final class SettingsViewController: NSViewController {
    /// The reset choices, in the order the popup shows them, with the value each saves (§7.1).
    static let resetChoices: [(title: String, value: Bool?)] = [
        ("Ask", nil), ("Update them", true), ("Keep the old ones", false),
    ]

    private let store: SettingsStore
    private let onChange: () -> Void
    private let resetPopUp = NSPopUpButton()
    private let shortcutRows = NSStackView()
    /// The command whose next shortcut is being recorded, if any.
    private(set) var recording: ControlCommand?
    /// Why a shortcut wasn't added, shown under its command's row until the next change.
    private(set) var messages: [ControlCommand: String] = [:]

    init(store: SettingsStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
        title = "Settings"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsViewController is built in code")
    }

    override func loadView() {
        resetPopUp.addItems(withTitles: Self.resetChoices.map(\.title))
        resetPopUp.target = self
        resetPopUp.action = #selector(resetChoiceChanged(_:))
        resetPopUp.setAccessibilityIdentifier("reset-best-times")
        resetPopUp.setAccessibilityLabel("When a reset has new best times")
        let resetRow = NSStackView(views: [
            NSTextField(labelWithString: "When a reset has new best times:"), resetPopUp,
        ])

        shortcutRows.orientation = .vertical
        shortcutRows.alignment = .leading
        shortcutRows.spacing = 8

        let restore = NSButton(
            title: "Restore Defaults", target: self, action: #selector(restoreDefaults(_:)))
        restore.setAccessibilityIdentifier("restore-default-shortcuts")

        let stack = NSStackView(views: [
            heading("General"), resetRow, heading("Shortcuts"), shortcutRows, restore,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack
        reload()
    }

    /// Shows the settings as they are saved now.
    func reload() {
        let settings = store.settings
        resetPopUp.selectItem(
            at: Self.resetChoices.firstIndex { $0.value == settings.resetSavesBestTimes } ?? 0)
        for row in shortcutRows.arrangedSubviews { row.removeFromSuperview() }
        var recorder: KeyRecorderView?
        for command in ControlCommand.allCases {
            let (row, rowRecorder) = makeRow(for: command, shortcuts: settings.shortcuts)
            shortcutRows.addArrangedSubview(row)
            recorder = recorder ?? rowRecorder
        }
        if let recorder { view.window?.makeFirstResponder(recorder) }
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    /// One command's row: its name, a button per shortcut that removes it, and **+** (or the
    /// recorder while recording), with any refusal under it.
    private func makeRow(for command: ControlCommand, shortcuts: Shortcuts) -> (
        NSView, KeyRecorderView?
    ) {
        let index = ControlCommand.allCases.firstIndex(of: command)!
        let name = NSTextField(labelWithString: command.name)
        name.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let keys = NSStackView()
        keys.orientation = .horizontal
        keys.spacing = 6
        for (position, shortcut) in shortcuts.shortcuts(for: command).enumerated() {
            let token = NSButton(
                title: "\(shortcut.displayName)  ✕", target: self,
                action: #selector(removeShortcut(_:)))
            token.controlSize = .small
            // A command has far fewer than 100 shortcuts.
            token.tag = index * 100 + position
            token.setAccessibilityIdentifier("shortcut-\(command.rawValue)-\(position)")
            token.setAccessibilityLabel("Remove \(shortcut.displayName) from \(command.name)")
            keys.addArrangedSubview(token)
        }

        var recorder: KeyRecorderView?
        if recording == command {
            let view = KeyRecorderView(
                onRecord: { [weak self] in self?.record($0) },
                onCancel: { [weak self] in self?.cancelRecording() })
            keys.addArrangedSubview(view)
            recorder = view
        } else {
            let add = NSButton(title: "+", target: self, action: #selector(addShortcut(_:)))
            add.controlSize = .small
            add.tag = index
            add.setAccessibilityIdentifier("add-shortcut-\(command.rawValue)")
            add.setAccessibilityLabel("Add a shortcut to \(command.name)")
            keys.addArrangedSubview(add)
        }

        let line = NSStackView(views: [name, keys])
        line.orientation = .horizontal
        guard let message = messages[command] else { return (line, recorder) }
        let note = NSTextField(labelWithString: message)
        note.textColor = .secondaryLabelColor
        note.setAccessibilityIdentifier("shortcut-message-\(command.rawValue)")
        let column = NSStackView(views: [line, note])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        return (column, recorder)
    }

    @objc private func resetChoiceChanged(_ sender: NSPopUpButton) {
        let value = Self.resetChoices[sender.indexOfSelectedItem].value
        store.update { $0.resetSavesBestTimes = value }
        onChange()
    }

    @objc private func addShortcut(_ sender: NSButton) {
        recording = ControlCommand.allCases[sender.tag]
        messages = [:]
        reload()
    }

    @objc private func removeShortcut(_ sender: NSButton) {
        let command = ControlCommand.allCases[sender.tag / 100]
        let shortcut = store.settings.shortcuts.shortcuts(for: command)[sender.tag % 100]
        store.update { $0.shortcuts.remove(shortcut, from: command) }
        messages = [:]
        onChange()
        reload()
    }

    @objc private func restoreDefaults(_ sender: NSButton) {
        store.update { $0.shortcuts.restoreDefaults() }
        recording = nil
        messages = [:]
        onChange()
        reload()
    }

    private func record(_ shortcut: Shortcut) {
        guard let command = recording else { return }
        recording = nil
        var shortcuts = store.settings.shortcuts
        switch shortcuts.add(shortcut, to: command) {
        case nil:
            store.update { $0.shortcuts = shortcuts }
            onChange()
        case .reserved:
            messages[command] = "\(shortcut.displayName) is kept for the app's menus."
        case .usedBy(let other):
            messages[command] = "\(shortcut.displayName) is already used by \(other.name)."
        }
        reload()
    }

    private func cancelRecording() {
        recording = nil
        reload()
    }
}
