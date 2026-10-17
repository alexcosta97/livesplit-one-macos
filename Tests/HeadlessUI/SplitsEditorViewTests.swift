import AppKit
import Foundation
import Testing

@testable import LiveSplitOne

@MainActor
@Suite final class SplitsEditorViewTests {
    var oks = 0
    var cancels = 0
    let prompts = ScriptedPrompts()
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    private func makeController(
        fixture: String? = "Grouped.lss", link: LinkedLayoutTarget = .none,
        current: String? = nil
    ) throws -> SplitsEditorViewController {
        let run =
            try fixture.map { try SplitsFile.load(Fixtures.url($0)) } ?? TimerContent.defaultRun()
        let controller = SplitsEditorViewController(
            editing: SplitsEditing(run: run, lang: 0), linkedLayout: link, currentLayout: current,
            prompts: prompts, ok: { [unowned self] in oks += 1 },
            cancel: { [unowned self] in cancels += 1 })
        _ = controller.view
        return controller
    }

    private func find<T: NSView>(_ identifier: String, in view: NSView) -> T? {
        if view.accessibilityIdentifier() == identifier, let match = view as? T { return match }
        for subview in view.subviews {
            if let match: T = find(identifier, in: subview) { return match }
        }
        return nil
    }

    private func field(_ identifier: String, _ controller: SplitsEditorViewController) throws
        -> NSTextField
    {
        try #require(find(identifier, in: controller.view))
    }

    private func popUp(_ controller: SplitsEditorViewController) throws -> NSPopUpButton {
        try #require(find("editor-layout", in: controller.view))
    }

    private func button(_ identifier: String, _ controller: SplitsEditorViewController) throws
        -> NSButton
    {
        try #require(find(identifier, in: controller.view))
    }

    /// Ends editing of `field` with `text`, as the field tells its delegate.
    private func endEditing(
        _ identifier: String, with text: String, _ controller: SplitsEditorViewController
    ) throws {
        let field = try field(identifier, controller)
        field.stringValue = text
        controller.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field))
    }

    private func shouldEnd(
        _ identifier: String, with text: String, _ controller: SplitsEditorViewController
    ) throws -> Bool {
        let field = try field(identifier, controller)
        field.stringValue = text
        return controller.control(field, textShouldEndEditing: NSText())
    }

    private func png() throws -> Data {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private func finishedLink(_ controller: SplitsEditorViewController) -> String? {
        controller.editing.finish().linkedLayout().map { $0.isDefault() ? "default" : $0.path() }
    }

    @Test func theFieldsShowTheRun() throws {
        let controller = try makeController()
        let state = controller.editing.state
        #expect(try field("editor-game", controller).stringValue == state.game)
        #expect(try field("editor-category", controller).stringValue == state.category)
        #expect(try field("editor-offset", controller).stringValue == state.offset)
        #expect(
            try field("editor-attempts", controller).stringValue == String(state.attempts))
        let icon: IconButton = try #require(find("editor-game-icon", in: controller.view))
        #expect(icon.icon != nil)
        #expect(icon.accessibilityLabel() == "Game icon")
        #expect(try field("editor-message", controller).isHidden)
    }

    @Test func endingTheGameFieldSetsTheGame() throws {
        let controller = try makeController()
        try endEditing("editor-game", with: "X", controller)
        #expect(controller.editing.state.game == "X")
        try endEditing("editor-category", with: "Any%", controller)
        #expect(controller.editing.state.category == "Any%")
    }

    @Test func aBadOffsetKeepsFocusInRedWithAMessage() throws {
        let controller = try makeController()
        let offset = try field("editor-offset", controller)
        let before = controller.editing.state.offset
        #expect(try !shouldEnd("editor-offset", with: "abc", controller))
        #expect(controller.editing.state.offset == before)
        #expect(offset.textColor == .systemRed)
        let message: NSTextField = try #require(find("editor-message", in: controller.view))
        #expect(!message.isHidden)
        #expect(message.stringValue == "Enter a time, such as 1:23.45.")
        #expect(message.textColor == .systemRed)

        #expect(try shouldEnd("editor-offset", with: "1.5", controller))
        #expect(offset.textColor == .controlTextColor)
        #expect(message.isHidden)
        #expect(controller.editing.state.offset == "1.50")
    }

    @Test func aBadNumberOfAttemptsSaysSo() throws {
        let controller = try makeController()
        #expect(try !shouldEnd("editor-attempts", with: "-1", controller))
        let message: NSTextField = try #require(find("editor-message", in: controller.view))
        #expect(message.stringValue == "Enter a whole number.")
        #expect(try field("editor-attempts", controller).textColor == .systemRed)
        #expect(try shouldEnd("editor-attempts", with: "7", controller))
        #expect(try field("editor-attempts", controller).textColor == .controlTextColor)
        #expect(message.isHidden)
        #expect(controller.editing.state.attempts == 7)
    }

    @Test func aForcedEndOfABadEntryClearsTheRedAndTheMessage() throws {
        let controller = try makeController()
        let offset = try field("editor-offset", controller)
        let before = controller.editing.state.offset
        #expect(try !shouldEnd("editor-offset", with: "abc", controller))
        try endEditing("editor-offset", with: "abc", controller)
        #expect(offset.stringValue == before)
        #expect(offset.textColor == .controlTextColor)
        #expect(try field("editor-message", controller).isHidden)

        #expect(try !shouldEnd("editor-attempts", with: "x", controller))
        try endEditing("editor-attempts", with: "x", controller)
        #expect(try field("editor-attempts", controller).textColor == .controlTextColor)
        #expect(try field("editor-message", controller).isHidden)
    }

    @Test func showMessageShowsAndHides() throws {
        let controller = try makeController()
        controller.showMessage("Hello")
        let message: NSTextField = try #require(find("editor-message", in: controller.view))
        #expect(message.stringValue == "Hello")
        #expect(!message.isHidden)
        controller.showMessage(nil)
        #expect(message.isHidden)
    }

    @Test func theLayoutListShowsNoneTheCurrentAndTheLinkedOne() throws {
        let controller = try makeController(link: .path("/a/Other.lsl"), current: "/b/Dark.lsl")
        let popUp = try popUp(controller)
        #expect(popUp.itemTitles == ["None", "Dark.lsl", "Other.lsl"])
        #expect(popUp.titleOfSelectedItem == "Other.lsl")
        popUp.selectItem(at: 1)
        popUp.sendAction(popUp.action, to: popUp.target)
        #expect(finishedLink(controller) == "/b/Dark.lsl")
    }

    @Test func aLinkToTheCurrentLayoutIsOneItem() throws {
        let controller = try makeController(link: .path("/b/./Dark.lsl"), current: "/b/Dark.lsl")
        let popUp = try popUp(controller)
        #expect(popUp.itemTitles == ["None", "Dark.lsl"])
        #expect(popUp.titleOfSelectedItem == "Dark.lsl")
    }

    @Test func theDefaultLayoutIsTheCurrentItemWithoutAFile() throws {
        let controller = try makeController(link: .defaultLayout, current: nil)
        let popUp = try popUp(controller)
        #expect(popUp.itemTitles == ["None", "Default Layout"])
        #expect(popUp.titleOfSelectedItem == "Default Layout")
        popUp.selectItem(at: 0)
        popUp.sendAction(popUp.action, to: popUp.target)
        #expect(finishedLink(controller) == nil)
    }

    @Test func choosingTheDefaultLayoutLinksIt() throws {
        let controller = try makeController(link: .none, current: nil)
        let popUp = try popUp(controller)
        #expect(popUp.titleOfSelectedItem == "None")
        popUp.selectItem(at: 1)
        popUp.sendAction(popUp.action, to: popUp.target)
        #expect(finishedLink(controller) == "default")
    }

    @Test func aLinkToTheDefaultLayoutWhileAFileIsCurrentHasItsOwnItem() throws {
        let controller = try makeController(link: .defaultLayout, current: "/b/Dark.lsl")
        let popUp = try popUp(controller)
        #expect(popUp.itemTitles == ["None", "Dark.lsl", "Default Layout"])
        #expect(popUp.titleOfSelectedItem == "Default Layout")
        #expect(controller.linkedLayout == .defaultLayout)
    }

    @Test func choosingNoneRemovesTheLink() throws {
        let controller = try makeController(link: .path("/b/Dark.lsl"), current: "/b/Dark.lsl")
        let popUp = try popUp(controller)
        popUp.selectItem(at: 0)
        popUp.sendAction(popUp.action, to: popUp.target)
        #expect(controller.linkedLayout == .none)
        #expect(finishedLink(controller) == nil)
    }

    @Test func theGameTimeSwitchSelectsGameTime() throws {
        let controller = try makeController()
        let control: NSSegmentedControl = try #require(
            find("editor-timing-method", in: controller.view))
        #expect(control.label(forSegment: 0) == "Real Time")
        #expect(control.label(forSegment: 1) == "Game Time")
        control.selectedSegment = 1
        control.sendAction(control.action, to: control.target)
        #expect(controller.editing.state.timingMethod == .gameTime)
    }

    @Test func chooseImageSetsTheIcon() throws {
        let controller = try makeController(fixture: nil)
        let icon: IconButton = try #require(find("editor-game-icon", in: controller.view))
        #expect(icon.icon == nil)
        #expect(!icon.makeMenu().items[1].isEnabled)
        let url = folder.url.appending(path: "icon.png")
        try png().write(to: url)
        prompts.images = [url]
        icon.chooseImage()
        #expect(controller.editing.image(controller.editing.state.icon) != nil)
        #expect(icon.icon != nil)
        #expect(icon.makeMenu().items.map(\.title) == ["Choose Image…", "Remove Image"])
        #expect(icon.makeMenu().items[1].isEnabled)
        #expect(prompts.iconFailures.isEmpty)
    }

    @Test func aFileThatIsNotAnImageIsReported() throws {
        let controller = try makeController(fixture: nil)
        let icon: IconButton = try #require(find("editor-game-icon", in: controller.view))
        prompts.images = [Fixtures.url("NotSplits.txt")]
        icon.chooseImage()
        #expect(prompts.iconFailures.map(\.file) == ["NotSplits.txt"])
        #expect(prompts.iconFailures.map(\.error) == [.notImage])
        #expect(controller.editing.image(controller.editing.state.icon) == nil)
    }

    @Test func cancellingTheImagePanelChangesNothing() throws {
        let controller = try makeController()
        let icon: IconButton = try #require(find("editor-game-icon", in: controller.view))
        prompts.images = [nil]
        icon.chooseImage()
        #expect(icon.icon != nil)
        #expect(prompts.iconFailures.isEmpty)
    }

    @Test func removeImageClearsTheIcon() throws {
        let controller = try makeController()
        let icon: IconButton = try #require(find("editor-game-icon", in: controller.view))
        #expect(icon.icon != nil)
        icon.removeImage()
        #expect(controller.editing.image(controller.editing.state.icon) == nil)
        #expect(icon.icon == nil)
    }

    @Test func okAndCancelCallTheirClosures() throws {
        let controller = try makeController()
        let ok = try button("editor-ok", controller)
        let cancel = try button("editor-cancel", controller)
        #expect(ok.title == "OK")
        #expect(ok.keyEquivalent == "\r")
        #expect(cancel.title == "Cancel")
        #expect(cancel.keyEquivalent == "\u{1b}")
        ok.sendAction(ok.action, to: ok.target)
        cancel.sendAction(cancel.action, to: cancel.target)
        #expect(oks == 1)
        #expect(cancels == 1)
    }

    @Test func refreshKeepsAFieldThatIsBeingEdited() throws {
        let controller = try makeController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = controller
        let game = try field("editor-game", controller)
        #expect(window.makeFirstResponder(game))
        game.currentEditor()?.string = "Typing"
        controller.editing.setCategory("Changed")
        controller.refresh()
        #expect(game.currentEditor()?.string == "Typing")
        #expect(try field("editor-category", controller).stringValue == "Changed")
    }

    @Test func theViewHasAMinimumSizeAndNoAmbiguousLayout() throws {
        let controller = try makeController()
        controller.view.layoutSubtreeIfNeeded()
        #expect(controller.view.fittingSize.width >= 640)
        #expect(controller.view.fittingSize.height >= 420)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: [.titled],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 640, height: 420))
        controller.view.layoutSubtreeIfNeeded()
        func ambiguous(_ view: NSView) -> [NSView] {
            (view.hasAmbiguousLayout ? [view] : []) + view.subviews.flatMap(ambiguous)
        }
        let found = ambiguous(controller.view).map { String(describing: type(of: $0)) }
        #expect(found == [])
    }
}
