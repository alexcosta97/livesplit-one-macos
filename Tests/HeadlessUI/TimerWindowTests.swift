import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct TimerWindowTests {
    // An even height, so the centred window sits on whole points: AppKit rounds a window's frame
    // out to whole points, which would make it 501 points tall.
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 876)

    private func makeController(
        _ store: SettingsStore, notices: NoticeQueue = NoticeQueue(schedule: { _, _ in })
    ) -> TimerWindowController {
        TimerWindowController(
            content: TimerContent(lang: 0), settings: store, screens: [screen],
            mainScreen: screen, notices: notices)
    }

    @Test func theWindowIsBorderlessResizableAndNamed() throws {
        let folder = try TemporaryFolder()
        let window = makeController(SettingsStore(directory: folder.url)).window
        #expect(window.styleMask.contains(.borderless))
        #expect(window.styleMask.contains(.resizable))
        #expect(!window.styleMask.contains(.titled))
        #expect(window.isMovableByWindowBackground)
        #expect(window.canBecomeKey && window.canBecomeMain)
        #expect(window.accessibilityIdentifier() == "timer-window")
        #expect(window.title == "LiveSplit One")
        #expect(window.contentView?.accessibilityIdentifier() == "timer-layout")
    }

    @Test func theWindowIsNotShownUntilAsked() throws {
        let folder = try TemporaryFolder()
        #expect(!makeController(SettingsStore(directory: folder.url)).window.isVisible)
    }

    @Test func withNoSavedFrameItIsCentredAtLiveSplitOnesSize() throws {
        let folder = try TemporaryFolder()
        let window = makeController(SettingsStore(directory: folder.url)).window
        #expect(window.frame == CGRect(x: 570, y: 188, width: 300, height: 500))
    }

    @Test func aSavedFrameOnScreenIsUsed() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        store.update {
            $0.setFrame(WindowFrame(x: 100, y: 200, width: 250, height: 400), forLayout: nil)
        }
        #expect(
            makeController(store).window.frame == CGRect(x: 100, y: 200, width: 250, height: 400))
    }

    @Test func aSavedFrameOffScreenIsIgnored() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        store.update {
            $0.setFrame(WindowFrame(x: 5000, y: 200, width: 250, height: 400), forLayout: nil)
        }
        #expect(makeController(store).window.frame.size == CGSize(width: 300, height: 500))
    }

    @Test func savingTheFrameStoresItForTheDefaultLayout() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        let controller = makeController(store)
        controller.window.setFrame(CGRect(x: 50, y: 60, width: 320, height: 480), display: false)

        controller.saveFrame()

        #expect(
            store.settings.frame(forLayout: nil)
                == WindowFrame(x: 50, y: 60, width: 320, height: 480))
        #expect(try folder.read("app.toml").contains("[default_layout_window]"))
    }

    @Test func openingTheWindowSavesNothing() throws {
        let folder = try TemporaryFolder()
        let controller = makeController(SettingsStore(directory: folder.url))
        controller.saveFrameIfPending()
        #expect(try folder.names().isEmpty)
    }

    @Test func aSizeHintResizesTheWindowKeepingItsTopLeft() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        let controller = makeController(store)
        let before = controller.window.frame

        controller.fitLayout(CGSize(width: 300, height: 600))

        let after = controller.window.frame
        #expect(after.size == CGSize(width: 300, height: 600))
        #expect(after.minX == before.minX && after.maxY == before.maxY)
        #expect(store.settings.frame(forLayout: nil) == WindowPlacement.windowFrame(after))
    }

    @Test func alwaysOnTopComesFromTheSettings() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        store.update { $0.alwaysOnTop = true }
        #expect(makeController(store).window.level == .floating)
    }

    @Test func togglingAlwaysOnTopChangesTheWindowAndSavesIt() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        let controller = makeController(store)
        #expect(controller.window.level == .normal)

        controller.toggleAlwaysOnTop()

        #expect(controller.window.level == .floating)
        #expect(store.settings.alwaysOnTop)
        #expect(try folder.read("app.toml").contains("always_on_top = true"))
    }

    @Test func noticesShowOverTheTimer() throws {
        let folder = try TemporaryFolder()
        let controller = makeController(SettingsStore(directory: folder.url))
        #expect(controller.shownNotice == nil)
        controller.notices.show("Connected to pc")
        #expect(controller.shownNotice == "Connected to pc")
    }
}
