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
    var timerWindow: XCUIElement { app.windows["timer-window"] }

    func launch() {
        app.launchArguments += ["-LSOLogDirectory", logFolder.path]
        app.launch()
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
}
