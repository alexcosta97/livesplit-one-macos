import AppKit

/// A square button showing an icon, or an empty well. Clicking it shows **Choose Image…** and
/// **Remove Image** (spec §9).
@MainActor
final class IconButton: NSButton {
    /// The side of the button, in points.
    static let side: CGFloat = 64

    var onChoose: () -> Void = {}
    var onRemove: () -> Void = {}

    /// The icon shown, or `nil` for the empty well. **Remove Image** is disabled without one.
    var icon: NSImage? {
        get { image }
        set { image = newValue }
    }

    /// `label` is what VoiceOver says, such as "Game icon".
    init(label: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        bezelStyle = .smallSquare
        imageScaling = .scaleProportionallyUpOrDown
        imagePosition = .imageOnly
        target = self
        action = #selector(showMenu(_:))
        setAccessibilityLabel(label)
        widthAnchor.constraint(equalToConstant: Self.side).isActive = true
        heightAnchor.constraint(equalToConstant: Self.side).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IconButton is built in code")
    }

    /// What the menu does, so tests can call it without popping the menu up.
    func chooseImage() { onChoose() }
    func removeImage() { onRemove() }

    /// The menu a click shows.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let choose = NSMenuItem(
            title: "Choose Image…", action: #selector(chooseItem(_:)), keyEquivalent: "")
        choose.target = self
        let remove = NSMenuItem(
            title: "Remove Image", action: #selector(removeItem(_:)), keyEquivalent: "")
        remove.target = self
        remove.isEnabled = icon != nil
        menu.addItem(choose)
        menu.addItem(remove)
        return menu
    }

    @objc private func showMenu(_ sender: Any?) {
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
    }

    @objc private func chooseItem(_ sender: Any?) { chooseImage() }
    @objc private func removeItem(_ sender: Any?) { removeImage() }
}
