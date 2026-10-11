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
    /// Whether something changed the timer, the run or the layout since the last update.
    private var needsUpdate = true
    private var lastUpdate = ContinuousClock.now
    private var lastPixelSize: (Int, Int)?

    /// While the timer isn't running, the layout state is updated this often at least, so a
    /// missed `markChanged()` shows within half a second.
    static let idleRefresh: Duration = .milliseconds(500)

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

    /// Call after anything changes the timer, the run or the layout (commands from the menu or a
    /// server, opening files, the splits editor), so the next frame shows it at once.
    func markChanged() {
        needsUpdate = true
    }

    /// Updates the layout's state from the timer, then renders it at the size in pixels if
    /// anything changed. While the timer runs, the state is updated every frame; otherwise only
    /// after `markChanged()` or `idleRefresh`. Holds the timer's read lock only while updating
    /// (spec §5.1).
    func render(pixelWidth: Int, pixelHeight: Int) -> RenderedFrame {
        let lock = timer.read()
        // 1 is Running, as `Timer.currentPhase()` returns it.
        let running = lock.timer().currentPhase() == 1
        let now = ContinuousClock.now
        let updated = running || needsUpdate || now - lastUpdate >= Self.idleRefresh
        if updated {
            layout.updateState(state, imageCache, lock.timer(), lang)
            needsUpdate = false
            lastUpdate = now
        }
        lock.dispose()
        let size = (pixelWidth, pixelHeight)
        if !updated, let last = lastPixelSize, last == size { return .nothing }
        lastPixelSize = size
        return renderer.render(state, imageCache, width: pixelWidth, height: pixelHeight)
    }
}
