import CoreGraphics
import Foundation
import LiveSplitCore
import Testing

/// A layout, a timer and the layout's state, as the timer window holds them.
private final class Scene {
    let layout = Layout.defaultLayout(Scene.english)
    let imageCache = ImageCache()
    let timer: SharedTimer
    let state: LayoutState

    static let english = Lang.parseLocale("en")

    init(segments: [String] = ["Time"]) {
        let run = Run()
        for name in segments { run.pushSegment(Segment(name)) }
        // `LiveSplitCore.Timer`, not Foundation's.
        timer = LiveSplitCore.Timer(run)!.intoShared()
        let lock = timer.read()
        state = layout.state(imageCache, lock.timer(), Self.english)
        lock.dispose()
    }

    /// Updates the state from the timer, as each display refresh does.
    func update() {
        let lock = timer.read()
        layout.updateState(state, imageCache, lock.timer(), Self.english)
        lock.dispose()
    }
}

@Suite struct RenderingTests {
    @Test func theDefaultLayoutMatchesItsSnapshot() throws {
        let scene = Scene()
        let frame = LayoutRenderer().render(scene.state, scene.imageCache, width: 300, height: 500)
        let image = try #require(frame.image)
        #expect(Snapshot.mismatch(image, "default-layout") == nil)
    }

    @Test func theDefaultLayoutAtTwiceTheScaleMatchesItsSnapshot() throws {
        let scene = Scene()
        let frame = LayoutRenderer().render(scene.state, scene.imageCache, width: 600, height: 1000)
        let image = try #require(frame.image)
        #expect(image.width == 600 && image.height == 1000)
        #expect(Snapshot.mismatch(image, "default-layout-2x") == nil)
    }

    @Test func aRunWithSegmentsMatchesItsSnapshot() throws {
        let scene = Scene(segments: ["Forest", "Castle", "Final Boss"])
        let frame = LayoutRenderer().render(scene.state, scene.imageCache, width: 300, height: 500)
        let image = try #require(frame.image)
        #expect(Snapshot.mismatch(image, "three-segments") == nil)
    }

    @Test func anIdleTimerDrawsNothingNew() {
        let scene = Scene()
        let renderer = LayoutRenderer()
        #expect(
            renderer.render(scene.state, scene.imageCache, width: 300, height: 500).image != nil)

        scene.update()
        let again = renderer.render(scene.state, scene.imageCache, width: 300, height: 500)

        #expect(again.image == nil)
        #expect(again.sizeHint == nil)
    }

    @Test func aRunningTimerDrawsAgain() {
        let scene = Scene()
        let renderer = LayoutRenderer()
        _ = renderer.render(scene.state, scene.imageCache, width: 300, height: 500)
        let sink = EventSink(timer: scene.timer, report: { _ in }, decideReset: { .cancel })
        #expect(sink.handleCommand(#"{"command":"start"}"#) == #"{"success":null}"#)
        // Starting also changes the timer's colour, so the frame differs however little time passes.
        Thread.sleep(forTimeInterval: 0.02)

        scene.update()

        #expect(
            renderer.render(scene.state, scene.imageCache, width: 300, height: 500).image != nil)
    }

    @Test func aTallerLayoutGivesASizeHint() throws {
        let scene = Scene()
        let renderer = LayoutRenderer()
        _ = renderer.render(scene.state, scene.imageCache, width: 300, height: 500)

        scene.layout.push(BlankSpaceComponent().intoGeneric())
        scene.update()
        let hint = try #require(
            renderer.render(scene.state, scene.imageCache, width: 300, height: 500).sizeHint)

        #expect(hint.width == 300)
        #expect(hint.height > 500)
    }

    @Test func aZeroOrHugeSizeDrawsNothing() {
        let scene = Scene()
        let renderer = LayoutRenderer()
        let side = LayoutRenderer.maximumSide
        #expect(renderer.render(scene.state, scene.imageCache, width: 0, height: 500).image == nil)
        #expect(renderer.render(scene.state, scene.imageCache, width: 300, height: -1).image == nil)
        #expect(
            renderer.render(scene.state, scene.imageCache, width: side + 1, height: 10).image
                == nil)
    }
}
