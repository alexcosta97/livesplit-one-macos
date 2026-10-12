import AppKit

/// The Connect to Server sheet (spec §8.1): the server's address, prefilled with the last one
/// used, and Connect and Cancel. An address that can't be used keeps the sheet open and says why.
@MainActor
final class ConnectSheet: NSViewController, NSTextFieldDelegate {
    private let field = NSTextField()
    private let error = NSTextField(wrappingLabelWithString: "")
    private let connectButton = NSButton()
    private let prefill: String?
    private let connect: (ServerURL, String) -> Void
    private let cancel: () -> Void

    /// `connect` gets the address and the text as typed, trimmed, for `app.toml`.
    init(
        prefill: String?, connect: @escaping (ServerURL, String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.prefill = prefill
        self.connect = connect
        self.cancel = cancel
        super.init(nibName: nil, bundle: nil)
        title = "Connect to Server"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ConnectSheet is built in code")
    }

    /// A window holding the sheet, to show with `NSWindow.beginSheet`.
    func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: self)
        window.styleMask = [.titled]
        window.title = "Connect to Server"
        window.setAccessibilityIdentifier("connect-sheet")
        window.initialFirstResponder = field
        return window
    }

    override func loadView() {
        let heading = NSTextField(labelWithString: "Connect to Server")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let label = NSTextField(labelWithString: "Server address:")

        field.stringValue = prefill ?? ""
        field.placeholderString = "ws://192.168.1.20:9087"
        field.delegate = self
        field.setAccessibilityIdentifier("connect-url")
        field.setAccessibilityLabel("Server address")
        field.widthAnchor.constraint(equalToConstant: 320).isActive = true

        error.textColor = .systemRed
        error.isHidden = true
        error.setAccessibilityIdentifier("connect-error")
        error.preferredMaxLayoutWidth = 320

        let cancelButton = NSButton(
            title: "Cancel", target: self, action: #selector(cancelPressed(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("connect-cancel")
        connectButton.title = "Connect"
        connectButton.bezelStyle = .push
        connectButton.target = self
        connectButton.action = #selector(connectPressed(_:))
        connectButton.keyEquivalent = "\r"
        connectButton.setAccessibilityIdentifier("connect-button")
        let buttons = NSStackView(views: [cancelButton, connectButton])

        let stack = NSStackView(views: [heading, label, field, error, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(16, after: error)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        buttons.trailingAnchor.constraint(equalTo: field.trailingAnchor).isActive = true
        view = stack
        updateConnectButton()
    }

    /// Typing clears the error, and Connect is enabled only while there is an address.
    func controlTextDidChange(_ notification: Notification) {
        show(nil)
        updateConnectButton()
    }

    private var trimmed: String {
        field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateConnectButton() {
        connectButton.isEnabled = !trimmed.isEmpty
    }

    private func show(_ message: String?) {
        error.stringValue = message ?? ""
        error.isHidden = message == nil
    }

    @objc func connectPressed(_ sender: Any?) {
        guard !trimmed.isEmpty else { return }
        switch ServerURL.parse(trimmed) {
        case .success(let server): connect(server, trimmed)
        case .failure(let problem): show(problem.message)
        }
    }

    @objc func cancelPressed(_ sender: Any?) {
        cancel()
    }
}
