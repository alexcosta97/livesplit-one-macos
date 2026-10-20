import XCTest

/// Connect to Server with the fake server, as a user does it (spec §8, §14.3): its commands
/// start and split the timer, a local split reaches it, it drops and the app reconnects, and Disconnect
/// closes the connection.
final class ConnectTests: XCTestCase {
    /// Waits until the overlay notice reads `text`. Returns whether it did within `timeout`.
    @MainActor
    private func waitForNotice(_ text: String, timeout: TimeInterval = 10, _ e2e: E2EApp)
        async -> Bool
    {
        let notice = e2e.timerWindow.staticTexts["overlay-notice"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if notice.exists, notice.value as? String == text { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// Waits until no notice shows. Returns whether none did within `timeout`.
    @MainActor
    private func waitForNoNotice(timeout: TimeInterval = 10, _ e2e: E2EApp) async -> Bool {
        let notice = e2e.timerWindow.staticTexts["overlay-notice"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !notice.exists { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    @MainActor
    func testConnectRunsTheServersCommandsAndReconnects() async throws {
        let server = try FakeServer()
        defer { server.stop() }
        let host = "127.0.0.1:\(server.port)"
        // GameTime.lss has 13 segments, so the run goes on after the server's split and the
        // local one.
        let e2e = E2EApp.launched(picks: ["GameTime.lss"])
        e2e.choose("timer-open-splits-choose", under: ["timer-open-splits"])
        e2e.waitForLog("Opened splits")

        // Connect.
        let connect = e2e.menuItem("timer-connect")
        XCTAssertEqual(connect.title, "Connect to Server…")
        connect.click()
        let field = e2e.app.textFields["connect-url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(server.url.absoluteString)
        e2e.app.buttons["connect-button"].click()
        let connected = await waitForNotice("Connected to \(host)", e2e)
        XCTAssertTrue(connected, "no Connected notice")
        let opened = await server.waitForConnection()
        XCTAssertTrue(opened)

        // The server's commands start and split the timer; each event comes before its reply.
        server.send(#"{"command":"splitOrStart"}"#)
        let started = await server.wait { server.messages.count >= 2 }
        XCTAssertTrue(started)
        XCTAssertEqual(
            Array(server.messages.prefix(2)), [#"{"event":"Started"}"#, #"{"success":null}"#])
        server.send(#"{"command":"splitOrStart"}"#)
        let splitByServer = await server.wait { server.messages.count >= 4 }
        XCTAssertTrue(splitByServer, "the server's split got no reply")
        XCTAssertEqual(
            Array(server.messages.dropFirst(2).prefix(2)),
            [#"{"event":"Splitted"}"#, #"{"success":null}"#])

        // A local split reaches the server.
        let split = e2e.menuItem("timer-start_split", under: ["timer-control"])
        XCTAssertEqual(split.title, "Split")
        split.click()
        let splitLocally = await server.wait { server.messages.count >= 5 }
        XCTAssertTrue(splitLocally, "the local split didn't reach the server")
        XCTAssertEqual(server.messages.dropFirst(4).first, #"{"event":"Splitted"}"#)

        // The server drops; the app says so and reconnects. The first Connected notice goes
        // first, so the second one isn't taken for it.
        let gone = await waitForNoNotice(e2e)
        XCTAssertTrue(gone)
        server.dropConnections()
        let lost = await waitForNotice("Lost connection to \(host), retrying…", e2e)
        XCTAssertTrue(lost, "no Lost connection notice")
        // The retry comes after 1 s; the notice waits for the one before to go, 4 s.
        let reconnected = await waitForNotice("Connected to \(host)", timeout: 15, e2e)
        XCTAssertTrue(reconnected, "no Connected notice after the drop")
        XCTAssertEqual(server.connectionCount, 2)

        // Disconnect.
        let disconnect = e2e.menuItem("timer-connect")
        XCTAssertEqual(disconnect.title, "Disconnect from \(host)")
        disconnect.click()
        // The close code is checked by URLSessionWebSocketTests: here URLSession can reset the
        // connection right after its close frame, and the server's read then fails with it.
        let closed = await server.wait { server.openConnections == 0 }
        XCTAssertTrue(closed, "the server's connection is still open")
        XCTAssertEqual(e2e.menuItem("timer-connect").title, "Connect to Server…")
        e2e.app.typeKey(.escape, modifierFlags: [])
        let settings = e2e.settingsText(containing: "last_server_url")
        XCTAssertTrue(settings?.contains(server.url.absoluteString) == true, settings ?? "")
    }
}
