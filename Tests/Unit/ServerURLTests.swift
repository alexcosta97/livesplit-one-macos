import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct ServerURLTests {
    private func parsed(_ text: String) throws -> ServerURL {
        try ServerURL.parse(text).get()
    }

    private func problem(_ text: String) -> ServerURL.Problem? {
        if case .failure(let problem) = ServerURL.parse(text) { return problem }
        return nil
    }

    @Test func anAddressWithoutASchemeGetsWs() throws {
        let server = try parsed("192.168.1.20:9087")
        #expect(server.url.absoluteString == "ws://192.168.1.20:9087")
        #expect(server.host == "192.168.1.20:9087")
    }

    @Test func aPathIsKeptAndTheHostHasNoPortWhenTheURLNamesNone() throws {
        let server = try parsed("wss://example.com/path")
        #expect(server.url.absoluteString == "wss://example.com/path")
        #expect(server.host == "example.com")
    }

    @Test func spacesAreTrimmed() throws {
        let server = try parsed("  ws://a:1 \n")
        #expect(server.url.absoluteString == "ws://a:1")
        #expect(server.host == "a:1")
    }

    @Test func theSchemeIsReadWhateverItsCase() throws {
        #expect(try parsed("WS://a").url.absoluteString == "ws://a")
        #expect(try parsed("Wss://a").url.absoluteString == "wss://a")
    }

    @Test func anotherSchemeIsRefused() {
        #expect(problem("http://a") == .scheme)
        #expect(problem("http://a")?.message == "Use a ws:// or wss:// address.")
    }

    @Test func anAddressWithoutAHostIsRefused() {
        #expect(problem("ws://") == .host)
        #expect(problem("ws://:9087") == .host)
        #expect(problem("") == .host)
        #expect(problem("ws://")?.message == "Enter the server's address.")
    }

    @Test func anIPv6HostKeepsItsBrackets() throws {
        let server = try parsed("[::1]:9087")
        #expect(server.url.absoluteString == "ws://[::1]:9087")
        #expect(server.host == "[::1]:9087")
    }
}
