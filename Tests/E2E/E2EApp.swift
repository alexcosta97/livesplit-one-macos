import AppKit
import XCTest

/// Launches the app with its own folders, so E2E runs never touch the user's settings and logs
/// (spec §14.2).
///
/// The test runner is sandboxed, with read-only access to the whole disk: it can read what the
/// app writes but can't create files. So the folders are under /private/tmp, outside the
/// runner's container, and the app creates them. The `/private/tmp/lso-e2e-<uuid>` folders stay
/// behind, because the sandboxed runner can't delete them; macOS clears /private/tmp on restart.
@MainActor
final class E2EApp {
    let app = XCUIApplication()
    let root = URL(
        filePath: "/private/tmp/lso-e2e-\(UUID().uuidString)", directoryHint: .isDirectory)

    var logFolder: URL { root.appending(path: "Logs", directoryHint: .isDirectory) }
    var configFolder: URL { root.appending(path: "Config", directoryHint: .isDirectory) }
    var timerWindow: XCUIElement { app.windows["timer-window"] }

    /// A file in the E2E bundle's fixtures, which the app can read. The runner can't create
    /// files, so the tests open these and the app writes the copies.
    func fixture(_ name: String) -> URL {
        Bundle(for: E2EApp.self).resourceURL!
            .appending(path: "Fixtures", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .notDirectory)
    }

    /// A file the app saves in the run's folder.
    func savedFile(_ name: String) -> URL {
        root.appending(path: name, directoryHint: .notDirectory)
    }

    /// Launches the app. `pickedFiles` are the answers the file pickers give, in order: an
    /// absolute path, or `nil` to cancel (spec §14.2).
    func launch(pickedFiles: [String?] = []) {
        app.launchArguments += [
            "-LSOLogDirectory", logFolder.path, "-LSOConfigDirectory", configFolder.path,
        ]
        if !pickedFiles.isEmpty {
            let json = try! JSONSerialization.data(
                withJSONObject: pickedFiles.map { $0 as Any? ?? NSNull() })
            app.launchArguments += ["-LSOPickedFiles", String(decoding: json, as: UTF8.self)]
        }
        app.launch()
    }

    /// Launches the app with file pickers that answer with `picks`, in order: a fixture's
    /// name, or the name of a file to save under the run's folder, as `saved:Name`. Returns once
    /// the timer window shows.
    static func launched(picks: [String?] = []) -> E2EApp {
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

    /// Right-clicks the timer and returns the item `identifier` of its menu, going through
    /// `parents` first, without clicking it.
    func menuItem(_ identifier: String, under parents: [String] = []) -> XCUIElement {
        timerWindow.rightClick()
        var scope: XCUIElement = app
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

    /// Picks an item of the timer's right-click menu, going through `parents` first.
    func choose(_ identifier: String, under parents: [String] = []) {
        menuItem(identifier, under: parents).click()
    }

    /// Closes the open menus: a submenu, then the right-click menu.
    func closeMenus() {
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Waits until the log holds `text` `count` times, and returns the log. Fails the test if it
    /// doesn't within `timeout` seconds.
    @discardableResult
    func waitForLog(_ text: String, count: Int = 1, timeout: TimeInterval = 10) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var log = ""
        while Date() < deadline {
            log = logText(containing: text, timeout: 1) ?? log
            if log.components(separatedBy: text).count - 1 >= count { return log }
        }
        XCTFail("the log doesn't hold \"\(text)\" \(count) times. The log:\n\(log)")
        return log
    }

    /// The element's pixels as RGB values, so two screenshots can be compared, or empty if the
    /// screenshot can't be read.
    func picture(of element: XCUIElement) -> [UInt32] {
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

    /// Waits until the element's picture differs from `before`, and returns it.
    func waitForPicture(
        differentFrom before: [UInt32], in element: XCUIElement, timeout: TimeInterval = 10
    ) -> [UInt32] {
        let deadline = Date().addingTimeInterval(timeout)
        var now = picture(of: element)
        while now == before, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            now = picture(of: element)
        }
        return now
    }

    /// All of the log files' text, once it contains `text`, or `nil` if it doesn't within
    /// `timeout` seconds.
    func logText(containing text: String, timeout: TimeInterval = 10) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let names =
                (try? FileManager.default.contentsOfDirectory(atPath: logFolder.path)) ?? []
            let all = names.filter { $0.hasSuffix(".log") }.sorted()
                .compactMap {
                    try? String(contentsOf: logFolder.appending(path: $0), encoding: .utf8)
                }
                .joined()
            if all.contains(text) { return all }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    /// Quits the app and launches it again with the same folders, as a user relaunching it.
    /// `terminate()` kills the app without letting it save on quit, so the caller must first wait
    /// for whatever the app has to save, such as with `settingsText(containing:)`.
    func relaunch() {
        app.terminate()
        app.launch()
    }

    /// The text of `app.toml` once it contains `text`, or `nil` if it doesn't within `timeout`
    /// seconds.
    func settingsText(containing text: String, timeout: TimeInterval = 10) -> String? {
        let file = configFolder.appending(path: "app.toml")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let all = try? String(contentsOf: file, encoding: .utf8), all.contains(text) {
                return all
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }
}
