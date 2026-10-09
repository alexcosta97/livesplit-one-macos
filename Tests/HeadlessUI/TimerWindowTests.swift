import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct TimerWindowTests {
    @Test func theWindowIsNamedForAccessibility() {
        let window = AppDelegate.makeWindow()
        #expect(window.accessibilityIdentifier() == "timer-window")
        #expect(window.title == "LiveSplit One")
    }

    @Test func theWindowIsNotShownUntilAsked() {
        #expect(!AppDelegate.makeWindow().isVisible)
    }
}
