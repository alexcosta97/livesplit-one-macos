import AppKit
import LiveSplitCore

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
    /// The open layout's path, or `nil` for the default layout. `showLayout` and
    /// `adoptLayoutPath` set it.
    private(set) var layoutPath: String?
    private let noticeView = NoticeView()
    private let settings: SettingsStore
    /// The screens' visible frames and the main screen's, read each time a frame is restored:
    /// a display can be unplugged while the app runs.
    private let screens: @MainActor () -> [CGRect]
    private let mainScreen: @MainActor () -> CGRect
    private var pendingSave: Task<Void, Never>?
    /// Called with `true` when the window becomes key and `false` when it stops being key, as
    /// when another window comes in front or the app goes to the background.
    var onKeyChange: (@MainActor (Bool) -> Void)?

    /// `screens` gives the screens' visible frames; `mainScreen` gives where a window with no
    /// usable saved frame goes.
    init(
        content: TimerContent, settings: SettingsStore,
        screens: @escaping @MainActor () -> [CGRect], mainScreen: @escaping @MainActor () -> CGRect,
        notices: NoticeQueue = NoticeQueue()
    ) {
        self.content = content
        self.settings = settings
        self.notices = notices
        self.screens = screens
        self.mainScreen = mainScreen
        let frame =
            WindowPlacement.restoredFrame(
                settings.settings.frame(forLayout: nil), screens: screens())
            ?? WindowPlacement.centred(WindowPlacement.defaultSize, on: mainScreen())
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

    /// A controller for the screens AppKit reports, asked each time.
    static func make(content: TimerContent, settings: SettingsStore) -> TimerWindowController {
        TimerWindowController(
            content: content, settings: settings,
            screens: { NSScreen.screens.map(\.visibleFrame) },
            mainScreen: {
                NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            })
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

    /// Shows `layout`, from the file at `path` or the default layout for `nil`, in the frame
    /// saved for it, or keeping the window's size until the size hint (spec §6). A saved frame
    /// that no screen shows enough of any more, since a display can go away while the app
    /// runs, puts the window in the middle of the main screen at the default size, as at
    /// launch. With no saved frame the window stays where it is.
    func showLayout(_ layout: Layout, path: String?) {
        // So a pending save isn't written under the new path.
        saveFrameIfPending()
        layoutPath = path
        let saved = settings.settings.frame(forLayout: path)
        let restored = WindowPlacement.restoredFrame(saved, screens: screens())
        if let restored {
            window.setFrame(restored, display: true)
        } else if saved != nil {
            window.setFrame(
                WindowPlacement.centred(WindowPlacement.defaultSize, on: mainScreen()),
                display: true)
        }
        content.setLayout(layout, keepingWindowSize: restored != nil)
        // Setting the frame scheduled a save of the frame just restored.
        pendingSave?.cancel()
        pendingSave = nil
    }

    /// After Save Layout As…, the window's layout is the new file: saves the current frame under
    /// its path. A move pending at that point is saved under the old path first.
    func adoptLayoutPath(_ path: String) {
        saveFrameIfPending()
        layoutPath = path
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

    func windowWillClose(_ notification: Notification) {
        timerView.stopDisplayLink()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onKeyChange?(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        onKeyChange?(false)
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
