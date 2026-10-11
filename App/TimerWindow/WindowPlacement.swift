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
    /// must be fully visible but a normal frame needs at least 40 × 40 points. A frame larger
    /// than the screen it is most on shrinks to fit it, keeping its top-left corner unless that
    /// would leave part of it off the screen.
    static func restoredFrame(_ saved: WindowFrame?, screens: [CGRect]) -> CGRect? {
        guard let saved, saved.isUsable else { return nil }
        let frame = CGRect(
            x: saved.x, y: saved.y, width: max(saved.width, minimumSize.width),
            height: max(saved.height, minimumSize.height))
        let shown = screens.filter { screen in
            let visible = screen.intersection(frame)
            return !visible.isNull && visible.width >= min(minimumVisible, frame.width)
                && visible.height >= min(minimumVisible, frame.height)
        }
        guard
            let screen = shown.max(by: {
                area($0.intersection(frame)) < area($1.intersection(frame))
            })
        else { return nil }
        return fitted(frame, in: screen)
    }

    /// `frame`, no larger than `screen`. A frame that shrinks keeps its top-left corner, then
    /// moves onto `screen` if part of it is still off it. A frame that fits is left as it is.
    private static func fitted(_ frame: CGRect, in screen: CGRect) -> CGRect {
        guard frame.width > screen.width || frame.height > screen.height else { return frame }
        var fitted = resized(
            frame,
            to: CGSize(
                width: min(frame.width, screen.width), height: min(frame.height, screen.height)))
        fitted.origin.x = min(max(fitted.minX, screen.minX), screen.maxX - fitted.width)
        fitted.origin.y = min(max(fitted.minY, screen.minY), screen.maxY - fitted.height)
        return fitted
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    /// A frame of `size` in the middle of `screen`. The origin is in whole points, so AppKit
    /// doesn't round the size out.
    static func centred(_ size: CGSize, on screen: CGRect) -> CGRect {
        CGRect(
            x: (screen.midX - size.width / 2).rounded(.down),
            y: (screen.midY - size.height / 2).rounded(.down),
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
