import AppKit
import LiveSplitCore

/// Shows the rendered layout. On each display refresh it renders a frame, which draws only when
/// the layout or the size changed (spec §5.2).
@MainActor
final class TimerView: NSView {
    let content: TimerContent
    /// Called with the layout's natural size in points after its height changes.
    var onSizeHint: ((CGSize) -> Void)?
    /// How many frames were drawn, for tests.
    private(set) var framesDrawn = 0
    private var displayLink: CADisplayLink?

    /// The refresh rate while the timer is idle, so an idle timer wakes the app only a few times
    /// a second (spec §5.2).
    static let idleFrameRate = CAFrameRateRange(minimum: 4, maximum: 4, preferred: 4)

    /// The refresh rate to ask for: low while idle, the display's own otherwise.
    static func frameRate(idle: Bool) -> CAFrameRateRange {
        idle ? idleFrameRate : .default
    }

    /// The display link's current preferred rate, for tests.
    var preferredFrameRate: CAFrameRateRange? { displayLink?.preferredFrameRateRange }

    init(content: TimerContent) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Timer")
        setAccessibilityIdentifier("timer-layout")
        content.onChange = { [weak self] in self?.updateFrameRate(idle: false) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TimerView is built in code")
    }

    /// A drag anywhere moves the window, which has no title bar (spec §6).
    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(refresh(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        updateFrameRate(idle: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // A resize shows at the full rate.
        content.markChanged()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 1
    }

    @objc private func refresh(_ link: CADisplayLink) {
        drawFrame()
    }

    /// Renders one frame at the view's size in pixels. Each display refresh calls it.
    func drawFrame() {
        let pixels = convertToBacking(bounds).size
        let frame = content.render(
            pixelWidth: Int(pixels.width.rounded()), pixelHeight: Int(pixels.height.rounded()))
        if let image = frame.image {
            layer?.contents = image
            framesDrawn += 1
        }
        if let hint = frame.sizeHint,
            let size = WindowPlacement.size(
                forHint: hint, scale: window?.backingScaleFactor ?? 1)
        {
            onSizeHint?(size)
        }
        updateFrameRate(idle: content.isIdle)
    }

    private func updateFrameRate(idle: Bool) {
        guard let displayLink else { return }
        let rate = Self.frameRate(idle: idle)
        if displayLink.preferredFrameRateRange != rate {
            displayLink.preferredFrameRateRange = rate
        }
    }
}
