import XCTest

/// Connect to Server with the fake server, as a user does it (spec §8, §14.3): its commands
/// start the timer, a local split reaches it, it drops and the app reconnects, and Disconnect
/// closes the connection.
final class ConnectTests: XCTestCase {
    /// Right-clicks the timer and returns the item `identifier`, going through `parents` first.
    @MainActor
    private func menuItem(
        _ identifier: String, under parents: [String] = [], _ e2e: E2EApp
    ) -> XCUIElement {
        e2e.timerWindow.rightClick()
        var scope: XCUIElement = e2e.app
        for parent in parents {
            let item = scope.menuItems[parent]
            XCTAssertTrue(item.waitForExistence(timeout: 5), parent)
            item.hover()
            scope = item
        }
        let item = scope.menuItems[identifier]
        XCTAssertTrue(item.waitForExistence(timeout: 5), identifier)
        return item
    }

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
        let e2e = E2EApp()
        e2e.launch()
        XCTAssertTrue(e2e.timerWindow.waitForExistence(timeout: 10))

        // Connect.
        let connect = menuItem("timer-connect", e2e)
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

        // The server's command starts the timer; its event comes before its reply.
        server.send(#"{"command":"splitOrStart"}"#)
        let replied = await server.wait { server.messages.count >= 2 }
        XCTAssertTrue(replied)
        XCTAssertEqual(
            Array(server.messages.prefix(2)), [#"{"event":"Started"}"#, #"{"success":null}"#])

        // A local split reaches the server. The default run has one segment: it finishes.
        let split = menuItem("timer-start_split", under: ["timer-control"], e2e)
        XCTAssertEqual(split.title, "Split")
        split.click()
        let finished = await server.waitForMessage { $0 == #"{"event":"Finished"}"# }
        XCTAssertNotNil(finished, "the local split didn't reach the server")

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
        let disconnect = menuItem("timer-connect", e2e)
        XCTAssertEqual(disconnect.title, "Disconnect from \(host)")
        disconnect.click()
        let closed = await server.wait { server.normalCloses == 1 }
        XCTAssertTrue(closed, "the server saw no normal close")
        XCTAssertEqual(menuItem("timer-connect", e2e).title, "Connect to Server…")
        e2e.app.typeKey(.escape, modifierFlags: [])
        let settings = e2e.settingsText(containing: "last_server_url")
        XCTAssertTrue(settings?.contains(server.url.absoluteString) == true, settings ?? "")
    }
}
