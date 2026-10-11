import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite final class TimerWindowTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    private var opened: [TimerWindowController] = []

    // Ends each window's display link, so they don't pile up across tests.
    isolated deinit {
        for controller in opened { controller.window.contentView = nil }
    }

    private func makeController(
        _ store: SettingsStore, notices: NoticeQueue = NoticeQueue(schedule: { _, _ in })
    ) -> TimerWindowController {
        let controller = TimerWindowController(
            content: TimerContent(lang: 0), settings: store, screens: [screen],
            mainScreen: screen, notices: notices)
        opened.append(controller)
        return controller
    }

    @Test func theWindowIsBorderlessResizableAndNamed() throws {
        let folder = try TemporaryFolder()
        let window = makeController(SettingsStore(directory: folder.url)).window
        #expect(window.styleMask.contains(.borderless))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(!window.styleMask.contains(.titled))
        #expect(window.isMovableByWindowBackground)
        #expect(window.canBecomeKey && window.canBecomeMain)
        #expect(window.accessibilityIdentifier() == "timer-window")
        #expect(window.title == "LiveSplit One")
        #expect(window.contentView?.accessibilityIdentifier() == "timer-layout")
    }

    /// The Window menu's Minimize (⌘M) is enabled for the timer window, though it has no title
    /// bar. A borderless window that isn't miniaturizable disables it.
    @Test func minimizeIsEnabledForTheWindow() throws {
        let folder = try TemporaryFolder()
        let window = makeController(SettingsStore(directory: folder.url)).window
        let minimize = NSMenuItem(
            title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        #expect(window.validateMenuItem(minimize))

        let plain = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        #expect(!plain.validateMenuItem(minimize))
    }

    /// The menus show the Control shortcuts only while the timer window is key (spec §7), so
    /// the controller says when it becomes and stops being key.
    @Test func theControllerSaysWhenTheWindowIsKey() throws {
        let folder = try TemporaryFolder()
        let controller = makeController(SettingsStore(directory: folder.url))
        var changes: [Bool] = []
        controller.onKeyChange = { changes.append($0) }
        controller.windowDidBecomeKey(
            Notification(name: NSWindow.didBecomeKeyNotification, object: controller.window))
        #expect(changes == [true])
        controller.windowDidResignKey(
            Notification(name: NSWindow.didResignKeyNotification, object: controller.window))
        #expect(changes == [true, false])
    }

    @Test func theWindowIsNotShownUntilAsked() throws {
        let folder = try TemporaryFolder()
        #expect(!makeController(SettingsStore(directory: folder.url)).window.isVisible)
    }

    @Test func withNoSavedFrameItIsCentredAtLiveSplitOnesSize() throws {
        let folder = try TemporaryFolder()
        let window = makeController(SettingsStore(directory: folder.url)).window
        #expect(window.frame == CGRect(x: 570, y: 187, width: 300, height: 500))
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

    @Test func aSavedFrameLargerThanTheScreenShrinksToFit() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        store.update {
            $0.setFrame(WindowFrame(x: 0, y: -1125, width: 3000, height: 2000), forLayout: nil)
        }
        #expect(makeController(store).window.frame == screen)
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

        let saved = try folder.read("app.toml")
        controller.saveFrameIfPending()
        #expect(try folder.read("app.toml") == saved)
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

    @Test func closingTheWindowStopsItsDisplayLink() throws {
        let folder = try TemporaryFolder()
        let controller = makeController(SettingsStore(directory: folder.url))
        #expect(controller.timerView.preferredFrameRate != nil)

        controller.window.close()

        #expect(controller.timerView.preferredFrameRate == nil)
    }

    @Test func aDragSavesOnceAfterItStops() async throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        let controller = makeController(store)
        let moved = CGRect(x: 50, y: 60, width: 300, height: 500)

        controller.window.setFrame(moved, display: false)
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        // Nothing is written while the drag goes on.
        #expect(try folder.names().isEmpty)

        try await Task.sleep(for: .milliseconds(800))

        #expect(store.settings.frame(forLayout: nil) == WindowPlacement.windowFrame(moved))
        #expect(try folder.read("app.toml").contains("[default_layout_window]"))
        // And no second save is waiting.
        let saved = try folder.read("app.toml")
        controller.saveFrameIfPending()
        #expect(try folder.read("app.toml") == saved)
    }
}
