import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite final class ConnectSheetTests {
    var connected: [(url: String, text: String)] = []
    var cancelled = 0

    private func makeSheet(prefill: String? = nil) -> ConnectSheet {
        let sheet = ConnectSheet(
            prefill: prefill,
            connect: { [unowned self] in connected.append(($0.url.absoluteString, $1)) },
            cancel: { [unowned self] in cancelled += 1 })
        _ = sheet.view
        return sheet
    }

    private func find<T: NSView>(_ identifier: String, in view: NSView) -> T? {
        if view.accessibilityIdentifier() == identifier, let match = view as? T { return match }
        for subview in view.subviews {
            if let match: T = find(identifier, in: subview) { return match }
        }
        return nil
    }

    private func field(_ sheet: ConnectSheet) throws -> NSTextField {
        try #require(find("connect-url", in: sheet.view))
    }

    private func button(_ identifier: String, _ sheet: ConnectSheet) throws -> NSButton {
        try #require(find(identifier, in: sheet.view))
    }

    private func error(_ sheet: ConnectSheet) throws -> NSTextField {
        try #require(find("connect-error", in: sheet.view))
    }

    /// Types `text` into the field, as the field tells its delegate.
    private func type(_ text: String, in sheet: ConnectSheet) throws {
        let field = try field(sheet)
        field.stringValue = text
        sheet.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    private func press(_ identifier: String, _ sheet: ConnectSheet) throws {
        let button = try button(identifier, sheet)
        button.sendAction(button.action, to: button.target)
    }

    @Test func theLastAddressIsPrefilled() throws {
        let sheet = makeSheet(prefill: "ws://10.0.0.2:9087")
        #expect(try field(sheet).stringValue == "ws://10.0.0.2:9087")
        #expect(try field(sheet).placeholderString == "ws://192.168.1.20:9087")
        #expect(try button("connect-button", sheet).isEnabled)
        #expect(try error(sheet).isHidden)
    }

    @Test func connectIsTheDefaultButtonAndEscCancels() throws {
        let sheet = makeSheet()
        #expect(try button("connect-button", sheet).keyEquivalent == "\r")
        #expect(try button("connect-cancel", sheet).keyEquivalent == "\u{1b}")
        #expect(sheet.makeWindow().accessibilityIdentifier() == "connect-sheet")
    }

    @Test func anEmptyFieldDisablesConnect() throws {
        let sheet = makeSheet()
        #expect(try !button("connect-button", sheet).isEnabled)
        try type("   ", in: sheet)
        #expect(try !button("connect-button", sheet).isEnabled)
        try type("a", in: sheet)
        #expect(try button("connect-button", sheet).isEnabled)
    }

    @Test func anotherSchemeSaysWhyAndTypingClearsIt() throws {
        let sheet = makeSheet()
        try type("http://x", in: sheet)
        try press("connect-button", sheet)
        #expect(connected.isEmpty)
        #expect(try !error(sheet).isHidden)
        #expect(try error(sheet).stringValue == "Use a ws:// or wss:// address.")
        try type("ws://x", in: sheet)
        #expect(try error(sheet).isHidden)
        #expect(try error(sheet).stringValue.isEmpty)
    }

    @Test func noHostSaysWhy() throws {
        let sheet = makeSheet()
        try type("ws://:9087", in: sheet)
        try press("connect-button", sheet)
        #expect(connected.isEmpty)
        #expect(try error(sheet).stringValue == "Enter the server's address.")
    }

    @Test func connectGivesTheAddressAndTheTrimmedText() throws {
        let sheet = makeSheet()
        try type(" 192.168.1.20:9087 ", in: sheet)
        try press("connect-button", sheet)
        #expect(connected.map { $0.url } == ["ws://192.168.1.20:9087"])
        #expect(connected.map { $0.text } == ["192.168.1.20:9087"])
    }

    @Test func cancelCancels() throws {
        let sheet = makeSheet()
        try press("connect-cancel", sheet)
        #expect(cancelled == 1)
        #expect(connected.isEmpty)
    }
}
