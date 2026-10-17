import Foundation
import LiveSplitCore

/// The timer, the layout and what the window draws from them (spec §5). It starts with
/// livesplit-core's default layout and LiveSplit One's new run; opening files replaces them
/// (`setRun`, `setLayout`).
@MainActor
final class TimerContent {
    /// The one timer (spec §5.1). Commands reach it through an `EventSink` built on it.
    let timer: SharedTimer
    private(set) var layout: Layout
    let imageCache = ImageCache()
    private var state: LayoutState
    /// Drop the next updated frame's size hint: a layout with a saved frame keeps it (spec §6).
    private var dropNextSizeHint = false
    private let renderer = LayoutRenderer()
    private let lang: UInt8
    /// Whether something changed the timer, the run or the layout since the last update.
    private var needsUpdate = true
    private var lastUpdate = ContinuousClock.now
    private var lastPixelSize: (Int, Int)?
    private var lastPhase: UInt8?
    /// Whether the timer is idle: it wasn't running at the last `render`, and nothing is pending.
    /// The window then refreshes at a low rate.
    var isIdle: Bool { lastPhase != 1 && !needsUpdate }
    /// Called by `markChanged()`, so the window can return to its full refresh rate at once. It
    /// has one listener, the `TimerView` that shows this content, which owns it.
    var onChange: (() -> Void)?

    /// While the timer isn't running, the layout state is updated this often at least, so a
    /// missed `markChanged()` shows within `idleRefresh` plus one idle tick: an idle window
    /// refreshes at 4 Hz (`TimerView.idleFrameRate`), so about 0.75 s. A change of phase (a
    /// split that ends the run, a pause, a reset) is shown on the next tick, whoever caused it.
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

    /// Shows `layout` from the next frame. With `keepingWindowSize`, its first size hint is
    /// ignored, since the window already has the frame saved for it.
    func setLayout(_ layout: Layout, keepingWindowSize: Bool) {
        self.layout = layout
        let lock = timer.read()
        state = layout.state(imageCache, lock.timer(), lang)
        lock.dispose()
        dropNextSizeHint = keepingWindowSize
        imageCache.collect()
        markChanged()
    }

    /// What `setRun(_:)` did.
    enum SetRunResult: Equatable {
        /// The timer times with the run from now on.
        case replaced
        /// The run has no segments, which a timer can't use. Nothing changed.
        case noSegments
        /// An attempt is running, paused or finished and not reset. Nothing changed.
        case attemptInProgress
    }

    /// Times with `run` from now on, unless an attempt is in progress or `run` has no segments.
    ///
    /// The phase is checked under the same write lock that replaces the run, so an attempt
    /// that starts while a file picker or alert was open (a server command can start one) is
    /// never dropped: `Timer.setRun` resets without keeping the attempt's times. Callers still
    /// check `FileController.canReplaceRun` first to skip the picker. It takes the write lock
    /// on the main thread, so don't call it while a command waits on the reset question; it
    /// runs only from menu actions, which a modal alert blocks.
    @discardableResult
    func setRun(_ run: Run) -> SetRunResult {
        var result = SetRunResult.replaced
        timer.writeWith { timer in
            guard timer.currentPhase() == TimerPhase.notRunning.rawValue else {
                result = .attemptInProgress
                return
            }
            if timer.setRun(run) != nil { result = .noSegments }
        }
        guard result == .replaced else { return result }
        imageCache.collect()
        markChanged()
        return .replaced
    }

    /// Runs `body` on the timer's run, under the read lock.
    func withRun<T>(_ body: (RunRef) -> T) -> T {
        var result: T!
        timer.readWith { result = body($0.getRun()) }
        return result
    }

    /// The timer's phase, read under the read lock.
    var phase: TimerPhase {
        var phase = TimerPhase.notRunning
        timer.readWith { phase = TimerPhase(rawValue: $0.currentPhase()) ?? .notRunning }
        return phase
    }

    /// Whether the run may be replaced: no attempt is running, paused or finished and not reset,
    /// which replacing the run would drop (spec §7). The one place this rule is written.
    var canReplaceRun: Bool { phase == .notRunning }

    /// Whether the run changed since it was opened or last saved. A reset attempt counts.
    var hasUnsavedChanges: Bool { withRun { $0.hasBeenModified() } }

    /// The run as `.lss` text.
    func lssText() -> String { withRun { $0.saveAsLss() } }

    /// After `text` was written: marks the run saved, unless it changed since (a server command
    /// can change it meanwhile). Like `setRun`, it takes the write lock on the main thread, so
    /// it must not run while a command waits on the reset question; only menu actions call it,
    /// and a modal alert blocks them.
    func markSaved(_ text: String) {
        timer.writeWith { timer in
            if timer.getRun().saveAsLss() == text { timer.markAsUnmodified() }
        }
    }

    /// The layout the run links to, if any.
    var linkedLayout: LinkedLayoutTarget {
        withRun { run in
            guard let link = run.linkedLayout() else { return .none }
            return link.isDefault() ? .defaultLayout : .path(link.path())
        }
    }

    /// Call after anything changes the timer, the run or the layout (commands from the menu or a
    /// server, opening files, the splits editor), so the next frame shows it at once.
    func markChanged() {
        needsUpdate = true
        onChange?()
    }

    /// Updates the layout's state from the timer, then renders it at the size in pixels if
    /// anything changed. While the timer runs, the state is updated every frame; otherwise only
    /// after `markChanged()` or `idleRefresh`. Holds the timer's read lock only while updating
    /// (spec §5.1).
    func render(pixelWidth: Int, pixelHeight: Int) -> RenderedFrame {
        let lock = timer.read()
        // 1 is Running, as `Timer.currentPhase()` returns it.
        let phase = lock.timer().currentPhase()
        let running = phase == 1
        let now = ContinuousClock.now
        let updated =
            running || needsUpdate || phase != lastPhase
            || now - lastUpdate >= Self.idleRefresh
        lastPhase = phase
        if updated {
            layout.updateState(state, imageCache, lock.timer(), lang)
            needsUpdate = false
            lastUpdate = now
        }
        lock.dispose()
        let size = (pixelWidth, pixelHeight)
        if !updated, let last = lastPixelSize, last == size { return .nothing }
        lastPixelSize = size
        var frame = renderer.render(state, imageCache, width: pixelWidth, height: pixelHeight)
        if updated, dropNextSizeHint {
            dropNextSizeHint = false
            frame = RenderedFrame(image: frame.image, sizeHint: nil)
        }
        return frame
    }
}

/// Which layout a run asks for (spec §7.1).
enum LinkedLayoutTarget: Equatable {
    /// The run links no layout.
    case none
    /// It links livesplit-core's default layout.
    case defaultLayout
    /// It links the layout file at this path.
    case path(String)
}
