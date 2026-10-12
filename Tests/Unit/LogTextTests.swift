import Testing

@testable import LiveSplitOne

@Suite struct LogTextTests {
    @Test func plainTextIsUnchanged() {
        #expect(LogText.escaped("/a/b c.lss") == "/a/b c.lss")
    }

    @Test func lineBreaksAndControlCharactersAreEscaped() {
        #expect(LogText.escaped("/a\nb\r\tc") == "/a\\nb\\r\\tc")
        #expect(LogText.escaped("/a\\b") == "/a\\\\b")
        #expect(LogText.escaped("/a\u{1b}[0m") == "/a\\u{1b}[0m")
    }

    @Test func unicodeLineAndParagraphSeparatorsAreEscaped() {
        #expect(LogText.escaped("a\u{2028}b\u{2029}c") == "a\\u{2028}b\\u{2029}c")
    }
}
