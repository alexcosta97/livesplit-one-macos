import Foundation
import LiveSplitCore

/// The timer, the layout and what the window draws from them (spec §5). Until #12 opens files,
/// it holds livesplit-core's default layout and LiveSplit One's new run.
@MainActor
final class TimerContent {
    /// The one timer (spec §5.1). Commands reach it through an `EventSink` built on it.
    let timer: SharedTimer
    let layout: Layout
    let imageCache = ImageCache()
    private let state: LayoutState
    private let renderer = LayoutRenderer()
    private let lang: UInt8

    init(lang: UInt8 = TimerContent.systemLanguage) {
        self.lang = lang
        layout = Layout.defaultLayout(lang)
        // A run with one segment always makes a timer.
        timer = LiveSplitCore.Timer(Self.defaultRun())!.intoShared()
        let lock = timer.read()
        state = layout.state(imageCache, lock.timer(), lang)
        lock.dispose()
    }

    /// The layout's language: macOS's first preferred language, as LiveSplit One uses the
    /// browser's.
    static var systemLanguage: UInt8 {
        Lang.parseLocale(Locale.preferredLanguages.first ?? "en")
    }

    /// LiveSplit One's new run: one segment named "Time".
    static func defaultRun() -> Run {
        let run = Run()
        run.pushSegment(Segment("Time"))
        return run
    }

    /// Updates the layout's state from the timer, then renders it at the size in pixels if
    /// anything changed. Holds the timer's read lock only while updating (spec §5.1).
    func render(pixelWidth: Int, pixelHeight: Int) -> RenderedFrame {
        let lock = timer.read()
        layout.updateState(state, imageCache, lock.timer(), lang)
        lock.dispose()
        return renderer.render(state, imageCache, width: pixelWidth, height: pixelHeight)
    }
}
