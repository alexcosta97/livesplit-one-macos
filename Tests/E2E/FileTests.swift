import AppKit
import XCTest

/// Opening, saving and closing files as a user does it (spec §7.1, §14.3).
final class FileTests: XCTestCase {
    /// Launches the app with file pickers that answer with `picks`, in order: a fixture's
    /// name, or the name of a file to save under the run's folder, as `saved:Name`.
    @MainActor
    private func launched(picks: [String?] = []) -> E2EApp {
        let e2e = E2EApp()
        let paths: [String?] = picks.map { pick in
            guard let pick else { return nil }
            if pick.hasPrefix("saved:") {
                return e2e.savedFile(String(pick.dropFirst("saved:".count))).path
            }
            return e2e.fixture(pick).path
        }
        e2e.launch(pickedFiles: paths)
        XCTAssertTrue(e2e.timerWindow.waitForExistence(timeout: 10))
        return e2e
    }

    /// Picks an item of the right-click menu, going through `parents` first.
    @MainActor
    private func choose(_ identifier: String, under parents: [String] = [], _ e2e: E2EApp) {
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
        item.click()
    }

    @MainActor
    private func openSplits(_ e2e: E2EApp) {
        choose("timer-open-splits-choose", under: ["timer-open-splits"], e2e)
    }

    @MainActor
    private func control(_ command: String, _ e2e: E2EApp) {
        choose("timer-\(command)", under: ["timer-control"], e2e)
    }

    @MainActor
    private func waitForLog(_ text: String, _ e2e: E2EApp) {
        XCTAssertNotNil(e2e.logText(containing: text), "the log doesn't hold \"\(text)\"")
    }

    /// The number of different colours in a sample of the element's pixels, and the pixels'
    /// digest, so two screenshots can be compared.
    @MainActor
    private func picture(of element: XCUIElement) -> [UInt32] {
        guard
            let image = element.screenshot().image.cgImage(
                forProposedRect: nil, context: nil, hints: nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return [] }
        let (width, height) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return [] }
        return stride(from: 0, to: pixels.count, by: 4).map {
            UInt32(pixels[$0]) << 16 | UInt32(pixels[$0 + 1]) << 8 | UInt32(pixels[$0 + 2])
        }
    }

    /// Waits until the window's picture differs from `before`, and returns it.
    @MainActor
    private func waitForPicture(
        differentFrom before: [UInt32], in window: XCUIElement, timeout: TimeInterval = 10
    ) -> [UInt32] {
        let deadline = Date().addingTimeInterval(timeout)
        var now = picture(of: window)
        while now == before, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            now = picture(of: window)
        }
        return now
    }

    /// The alert's button `title`, found by its buttons, in whichever window shows it.
    @MainActor
    private func alertButton(_ title: String, _ e2e: E2EApp) -> XCUIElement {
        e2e.app.buttons[title].firstMatch
    }

    /// Presses Start/Split with Space, `times` times.
    @MainActor
    private func split(_ times: Int, _ e2e: E2EApp) {
        for _ in 0..<times { e2e.app.typeKey(" ", modifierFlags: []) }
    }

    @MainActor
    func testOpenedFilesAreReopenedAtTheSameWindowPosition() {
        let e2e = launched(picks: ["GameTime.lss", "TextShadow.ls1l"])
        let window = e2e.timerWindow
        let defaultPicture = picture(of: window)

        openSplits(e2e)
        choose("timer-open-layout-choose", under: ["timer-open-layout"], e2e)
        XCTAssertNotEqual(
            waitForPicture(differentFrom: defaultPicture, in: window), defaultPicture,
            "the window still shows the default run and layout")

        let before = window.frame
        // Built from .zero plus explicit offsets: see TimerWindowTests.
        let middle = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.width / 2, dy: before.height / 2))
        let target = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.width / 2 + 120, dy: before.height / 2 + 80))
        middle.press(forDuration: 0.2, thenDragTo: target)
        let moved = window.frame

        let saved = e2e.settingsText(containing: "x = \(Double(moved.minX))")
        XCTAssertNotNil(saved, "app.toml doesn't hold the moved frame")
        XCTAssertTrue(saved?.contains("[[windows]]") == true, saved ?? "")
        XCTAssertTrue(saved?.contains("TextShadow.ls1l") == true, saved ?? "")
        XCTAssertTrue(saved?.contains("GameTime.lss") == true, saved ?? "")

        e2e.relaunch()
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(window.frame.minX, moved.minX, accuracy: 1)
        XCTAssertEqual(window.frame.minY, moved.minY, accuracy: 1)
        let after = e2e.settingsText(containing: "TextShadow.ls1l") ?? ""
        XCTAssertTrue(after.contains("GameTime.lss"), after)
        XCTAssertTrue(after.contains("TextShadow.ls1l"), after)
    }

    @MainActor
    func testUnsavedChangesAreAskedAboutOnQuit() {
        let e2e = launched(picks: ["GameTime.lss", "saved:Saved.lss"])
        openSplits(e2e)
        choose("timer-save-splits-as", e2e)
        XCTAssertNotNil(e2e.logText(containing: "Saved.lss"))

        // GameTime.lss has 13 segments: one Start and 13 Splits finish an attempt.
        split(14, e2e)
        control("reset", e2e)
        if alertButton("Yes", e2e).waitForExistence(timeout: 5) {
            alertButton("Yes", e2e).click()
        }

        e2e.app.typeKey("q", modifierFlags: .command)
        let cancel = alertButton("Cancel", e2e)
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "quitting didn't ask")
        cancel.click()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertEqual(e2e.app.state, .runningForeground)

        e2e.app.typeKey("q", modifierFlags: .command)
        let save = alertButton("Save", e2e)
        XCTAssertTrue(save.waitForExistence(timeout: 5), "quitting didn't ask again")
        save.click()
        XCTAssertTrue(e2e.app.wait(for: .notRunning, timeout: 10))

        let text = try? String(contentsOf: e2e.savedFile("Saved.lss"), encoding: .utf8)
        XCTAssertNotNil(text, "Saved.lss wasn't written")
        // GameTime.lss has attempts up to id 1788 and an attempt count of 1958: the new attempt
        // takes the next id and the count goes up by one.
        XCTAssertTrue(text?.contains("<Attempt id=\"1789\"") == true, "no new attempt in Saved.lss")
        XCTAssertTrue(
            text?.contains("<AttemptCount>1959<") == true, "the attempt count is the same")
    }

    @MainActor
    func testResetWithNewBestTimesAsksAndRemembersNo() {
        let e2e = launched()
        // The default run has one segment: Start, then Split, finishes with a new best.
        split(2, e2e)
        control("reset", e2e)
        let no = alertButton("No", e2e)
        XCTAssertTrue(no.waitForExistence(timeout: 5), "the reset question didn't show")
        XCTAssertTrue(alertButton("Yes", e2e).exists)
        XCTAssertTrue(alertButton("Don't Reset", e2e).exists)
        no.click()
        XCTAssertNotNil(e2e.settingsText(containing: "reset_saves_best_times = false"))

        split(2, e2e)
        control("reset", e2e)
        // The reset ran, and nothing asked.
        let start = e2e.app.menuItems["timer-control"]
        e2e.timerWindow.rightClick()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.hover()
        let item = start.menuItems["timer-start_split"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual(item.title, "Start")
        XCTAssertFalse(alertButton("Don't Reset", e2e).exists)
        e2e.app.typeKey(.escape, modifierFlags: [])
        e2e.app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testCompareAgainstChangesWhatTheWindowShows() {
        let e2e = launched(picks: ["GameTime.lss"])
        openSplits(e2e)
        e2e.app.typeKey(" ", modifierFlags: [])
        let window = e2e.timerWindow
        let started = picture(of: window)

        choose("Best Segments", under: ["timer-compare-against"], e2e)
        waitForLog("Compare Against Best Segments from the menu", e2e)
        XCTAssertNotEqual(
            waitForPicture(differentFrom: started, in: window), started,
            "the window is the same against Best Segments")
    }

    @MainActor
    func testAFileThatIsNotSplitsShowsTheLoadFailedAlert() {
        let e2e = launched(picks: ["NotSplits.txt"])
        let window = e2e.timerWindow
        let before = picture(of: window)

        openSplits(e2e)
        let ok = alertButton("OK", e2e)
        XCTAssertTrue(ok.waitForExistence(timeout: 5), "no alert for a file that isn't splits")
        ok.click()
        XCTAssertTrue(ok.waitForNonExistence(timeout: 5))
        XCTAssertEqual(picture(of: window), before, "the window changed")
    }

    @MainActor
    func testOpenSplitsIsDisabledWhileAnAttemptRuns() {
        let e2e = launched()
        e2e.app.typeKey(" ", modifierFlags: [])
        waitForLog("Start/Split from the keyboard", e2e)
        e2e.timerWindow.rightClick()
        // The Open Splits item only holds a submenu, so what is disabled is its Open… item.
        let parent = e2e.app.menuItems["timer-open-splits"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        parent.hover()
        let open = parent.menuItems["timer-open-splits-choose"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(open.isEnabled)
        XCTAssertFalse(e2e.app.menuItems["timer-close-splits"].isEnabled)
        XCTAssertTrue(e2e.app.menuItems["timer-save-splits-as"].isEnabled)
        e2e.app.typeKey(.escape, modifierFlags: [])
        e2e.app.typeKey(.escape, modifierFlags: [])
    }
}
