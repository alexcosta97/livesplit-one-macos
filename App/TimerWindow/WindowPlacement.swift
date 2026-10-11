import CoreGraphics

/// Where the timer window goes and how big it is (spec §5.2, §6). Pure, so it's tested without
/// screens or windows.
enum WindowPlacement {
    /// LiveSplit One's size for a layout it hasn't sized yet, in points.
    static let defaultSize = CGSize(width: 300, height: 500)
    /// The smallest window, so it can't shrink to something that can't be grabbed.
    static let minimumSize = CGSize(width: 40, height: 20)
    /// How much of a saved frame, in both directions, must be on one screen for it to be used.
    /// A borderless window has no title bar to drag back from off screen.
    static let minimumVisible: CGFloat = 40

    /// The saved frame, at least `minimumSize`, if enough of it is on one of `screens` (their
    /// visible frames); otherwise `nil`. The visible part must be at least `min(minimumVisible,
    /// frame.width)` wide and at least `min(minimumVisible, frame.height)` tall, so a small frame
    /// must be fully visible but a normal frame needs at least 40 × 40 points.
    static func restoredFrame(_ saved: WindowFrame?, screens: [CGRect]) -> CGRect? {
        guard let saved, saved.isUsable else { return nil }
        let frame = CGRect(
            x: saved.x, y: saved.y, width: max(saved.width, minimumSize.width),
            height: max(saved.height, minimumSize.height))
        let onScreen = screens.contains { screen in
            let visible = screen.intersection(frame)
            let minWidthRequired = min(minimumVisible, frame.width)
            let minHeightRequired = min(minimumVisible, frame.height)
            return !visible.isNull && visible.width >= minWidthRequired
                && visible.height >= minHeightRequired
        }
        return onScreen ? frame : nil
    }

    /// A frame of `size` in the middle of `screen`.
    static func centred(_ size: CGSize, on screen: CGRect) -> CGRect {
        CGRect(
            x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
            width: size.width, height: size.height)
    }

    /// `frame` at `size`, keeping its top-left corner, so the layout grows downwards as in
    /// LiveSplit One.
    static func resized(_ frame: CGRect, to size: CGSize) -> CGRect {
        CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// The window size in points for a size hint in pixels at `scale`, at least `minimumSize`,
    /// or `nil` if the hint or the scale isn't a positive, finite number.
    static func size(forHint hint: CGSize, scale: CGFloat) -> CGSize? {
        let values = [hint.width, hint.height, scale]
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return CGSize(
            width: max(hint.width / scale, minimumSize.width),
            height: max(hint.height / scale, minimumSize.height))
    }

    /// `rect` as `app.toml` stores it.
    static func windowFrame(_ rect: CGRect) -> WindowFrame {
        WindowFrame(
            x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width),
            height: Double(rect.height))
    }
}
