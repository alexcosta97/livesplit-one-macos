import AppKit

/// The timer window with its contents and notices: where it goes, what it remembers, and how it
/// follows the layout's size (spec §5.2, §6).
@MainActor
final class TimerWindowController: NSObject, NSWindowDelegate {
    /// How long after the window stops moving its frame is saved, so a drag saves once.
    static let saveDelay: Duration = .milliseconds(500)

    let window: TimerWindow
    let timerView: TimerView
    let notices: NoticeQueue
    let content: TimerContent
    /// The open layout's path, or `nil` for the default layout. #12 sets it.
    private(set) var layoutPath: String?
    private let noticeView = NoticeView()
    private let settings: SettingsStore
    private var pendingSave: Task<Void, Never>?

    /// `screens` are the screens' visible frames; `mainScreen` is where a window with no usable
    /// saved frame goes.
    init(
        content: TimerContent, settings: SettingsStore, screens: [CGRect], mainScreen: CGRect,
        notices: NoticeQueue = NoticeQueue()
    ) {
        self.content = content
        self.settings = settings
        self.notices = notices
        let frame =
            WindowPlacement.restoredFrame(settings.settings.frame(forLayout: nil), screens: screens)
            ?? WindowPlacement.centred(WindowPlacement.defaultSize, on: mainScreen)
        window = TimerWindow(contentRect: frame)
        timerView = TimerView(content: content)
        super.init()

        window.contentView = timerView
        noticeView.place(in: timerView)
        window.setAlwaysOnTop(settings.settings.alwaysOnTop)
        notices.onChange = { [weak self] text in self?.noticeView.show(text) }
        timerView.onSizeHint = { [weak self] size in self?.fitLayout(size) }
        // Last, so placing the window above saves nothing.
        window.delegate = self
    }

    /// A controller for the screens AppKit reports.
    static func make(content: TimerContent, settings: SettingsStore) -> TimerWindowController {
        let main =
            NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return TimerWindowController(
            content: content, settings: settings, screens: NSScreen.screens.map(\.visibleFrame),
            mainScreen: main)
    }

    /// The notice on screen, if any.
    var shownNotice: String? { noticeView.isHidden ? nil : noticeView.text }

    /// Always on Top (spec §6), saved in `app.toml`.
    func toggleAlwaysOnTop() {
        settings.update { $0.alwaysOnTop.toggle() }
        window.setAlwaysOnTop(settings.settings.alwaysOnTop)
    }

    /// Gives the window the layout's natural size, keeping its top-left corner, as LiveSplit One
    /// does when the renderer gives a size hint (spec §5.2).
    func fitLayout(_ size: CGSize) {
        window.setFrame(WindowPlacement.resized(window.frame, to: size), display: true)
        saveFrame()
    }

    /// Saves the window's frame for the open layout now.
    func saveFrame() {
        pendingSave?.cancel()
        pendingSave = nil
        let frame = WindowPlacement.windowFrame(window.frame)
        settings.update { $0.setFrame(frame, forLayout: layoutPath) }
    }

    /// Saves the frame if a move or resize hasn't been saved yet, as when the app quits.
    func saveFrameIfPending() {
        if pendingSave != nil { saveFrame() }
    }

    func windowDidMove(_ notification: Notification) {
        scheduleSave()
    }

    func windowDidResize(_ notification: Notification) {
        scheduleSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }

    /// Saves the frame `saveDelay` after the last move or resize step.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveFrame()
        }
    }
}
