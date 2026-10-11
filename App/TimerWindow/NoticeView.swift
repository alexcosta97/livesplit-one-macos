import AppKit

/// One overlay notice, drawn over the bottom of the timer (spec §6). Not part of the layout:
/// it is a view above the layout's image, never drawn into it.
@MainActor
final class NoticeView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private static let margin: CGFloat = 6
    private static let padding = CGSize(width: 8, height: 4)

    var text: String { label.stringValue }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        layer?.cornerRadius = 6
        isHidden = true

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.setAccessibilityIdentifier("overlay-notice")
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding.width),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding.width),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding.height),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoticeView is built in code")
    }

    /// Adds the notice to `view`, centred at its bottom and never wider than it.
    func place(in view: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.margin),
            widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -2 * Self.margin),
        ])
    }

    /// Shows `text`, or hides the notice when it is `nil`. VoiceOver reads each new notice.
    func show(_ text: String?) {
        label.stringValue = text ?? ""
        isHidden = text == nil
        guard let text else { return }
        NSAccessibility.post(
            element: label, notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }

    override func layout() {
        // A wrapping label needs a width to wrap at.
        let available = (superview?.bounds.width ?? 0) - 2 * (Self.margin + Self.padding.width)
        label.preferredMaxLayoutWidth = max(available, 0)
        super.layout()
    }

    /// Clicks go through to the timer, so a drag that starts here still moves the window.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
