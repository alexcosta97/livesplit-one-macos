import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct AcknowledgementsWindowTests {
    @Test func theWindowShowsTheTextToReadAndCopy() throws {
        let controller = AcknowledgementsWindowController(text: "Fira Sans\nOFL")
        let window = try #require(controller.window)
        #expect(window.title == "Acknowledgements")
        #expect(window.accessibilityIdentifier() == "acknowledgements-window")
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.closable))
        let textView = controller.textView
        #expect(textView.string == "Fira Sans\nOFL")
        #expect(textView.accessibilityIdentifier() == "acknowledgements-text")
        #expect(!textView.isEditable)
        #expect(textView.isSelectable)
    }

    /// Help ▸ Acknowledgements opens one window, and opening it again shows the same one.
    @Test func showingItAgainReusesTheWindow() throws {
        let delegate = try #require(NSApplication.shared.delegate as? AppDelegate)
        delegate.showAcknowledgements(nil)
        let first = try #require(delegate.acknowledgementsWindow)
        defer { first.close() }
        #expect(first.window?.isVisible == true)
        #expect(first.textView.string == Acknowledgements.text())
        first.close()
        delegate.showAcknowledgements(nil)
        #expect(delegate.acknowledgementsWindow === first)
        #expect(first.window?.isVisible == true)
    }
}
